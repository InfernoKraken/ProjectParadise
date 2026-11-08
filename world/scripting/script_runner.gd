extends RefCounted

const Parser = preload("script_parser.gd")
const MAX_CALL_DEPTH := 32
signal finished
signal failed(details: Dictionary)
var running := false
var waiting := false
var script_data: Dictionary = {}
var stack: Array[Dictionary] = []
var context: Dictionary = {}
var flags: RefCounted
var dispatch: Callable
var cleanup: Callable
var generation := 0
var pumping := false
# -1 is unanswered; choices belong to this execution, never persistent flags.
var last_answer := -1

# Host returns {error: reason} or {pending: true}; pending operations invoke resume.
func start(source: String, block: String, map_name: String, state: RefCounted, handler: Callable, on_cleanup: Callable, references: Dictionary = {}) -> bool:
	if running: return false
	script_data = Parser.parse(source, references)
	context = {"map":map_name, "block":block, "line":0, "command":""}
	flags = state; dispatch = handler; cleanup = on_cleanup
	if not script_data.valid:
		for issue: Dictionary in script_data.diagnostics:
			if issue.severity == "error":
				context.line = issue.line; context.command = issue.token
				_fail(String(issue.message)); return false
	if not script_data.blocks.has(block):
		_fail("Missing entry Block: " + block); return false
	last_answer = -1
	generation += 1; running = true; waiting = false; stack = [{"block":block, "index":0}]
	_pump()
	return true

func resume(ticket: int) -> void:
	if ticket != generation or not running or not waiting: return
	waiting = false
	if not pumping: _pump()

func answer_choice(ticket: int, yes: bool) -> void:
	if ticket != generation or not running or not waiting or context.get("command", "") != "TextBoxYesNo": return
	last_answer = 1 if yes else 0
	resume(ticket)

func stop() -> void:
	last_answer = -1
	generation += 1; running = false; waiting = false; stack.clear()
	if cleanup.is_valid(): cleanup.call()
	finished.emit()

func fail(reason: String, ticket: int) -> void:
	if running and ticket == generation: _fail(reason)

func _fail(reason: String) -> void:
	var details := context.duplicate(); details.reason = reason
	failed.emit(details)
	stop()

func _pump() -> void:
	pumping = true
	var budget := 4096
	while running and not waiting:
		budget -= 1
		if budget < 0: _fail("Instruction safety budget exceeded."); break
		if stack.is_empty(): stop(); break
		var frame: Dictionary = stack[-1]
		var instructions: Array = script_data.blocks[frame.block]
		if frame.index >= instructions.size(): _fail("Block has no terminating instruction."); break
		var instruction: Dictionary = instructions[frame.index]; frame.index += 1
		context.merge({"block":frame.block, "index":frame.index - 1, "line":instruction.line, "command":instruction.command, "arguments":instruction.arguments}, true)
		var args: Array = instruction.arguments
		match instruction.command:
			"End": stop()
			"Return": stack.pop_back()
			"SetFlag", "ClearFlag": flags.set_flag(args[0], instruction.command == "SetFlag")
			"Call", "IfFlag", "IfNotFlag", "IfYes", "IfNo":
				var target: String = args[-1]
				var enter: bool = instruction.command == "Call"
				if instruction.command in ["IfYes", "IfNo"]:
					if last_answer < 0: _fail("IfYes/IfNo requires an answered TextBoxYesNo in this execution."); break
					enter = last_answer == (1 if instruction.command == "IfYes" else 0)
				elif instruction.command != "Call": enter = flags.has_flag(args[0]) == (instruction.command == "IfFlag")
				if enter:
					if stack.size() >= MAX_CALL_DEPTH: _fail("Maximum call depth (32) exceeded."); break
					stack.append({"block":target, "index":0})
			_:
				if instruction.command == "TextBoxYesNo": last_answer = -1
				waiting = true
				var ticket := generation
				var result: Dictionary = dispatch.call(instruction.command, args, func():resume(ticket))
				if result.has("error"): _fail(String(result.error)); break
				if not result.get("pending", false): waiting = false
	pumping = false
