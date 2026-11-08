extends SceneTree

const Parser = preload("res://world/scripting/script_parser.gd")
const Registry = preload("res://world/scripting/command_registry.gd")
const Runner = preload("res://world/scripting/script_runner.gd")
const Flags = preload("res://world/scripting/game_flags.gd")
var checks := 0
var failures := 0
var trace: Array[String] = []
var errors: Array[Dictionary] = []
var cleaned := 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(label)

func execute(command: String, args: Array, _resume: Callable) -> Dictionary:
	trace.append(command + (":" + str(args[0]) if not args.is_empty() else "")); return {}

func run(source: String, entry := "A", state: RefCounted = null) -> RefCounted:
	var runner := Runner.new()
	runner.failed.connect(func(details):errors.append(details))
	runner.start(source, entry, "fixture", state if state != null else Flags.new(), execute, func():cleaned += 1)
	return runner

func _initialize() -> void:
	var good := Parser.parse('// comment\n\nBlock A:\n TextBox "hello // world, \\\"quoted\\\"" // tail\nEnd\nBlock B:\nReturn\nEnd'.replace('\\\"', '\\"'))
	check(good.valid and good.blocks.size() == 2, "Multiple blocks, comments and blanks")
	if good.valid: check(good.blocks.A[0].arguments[0] == 'hello // world, "quoted"', "Quoted contents preserved")
	for source in ['Block A:\nSetFlg Foo\nEnd', 'Block A:\nTextBox unquoted\nEnd', 'Block A:\nTextBox "unterminated\nEnd', 'Block A:\nReturn extra\nEnd', 'Block A:\nEnd\nBlock A:\nEnd', 'Block A:\nReturn', 'Block A\nEnd', 'Block A:\nWarp cave nope 0\nEnd', 'Block A:\nGiveFakemon Foo 101\nEnd', 'Block A:\nGiveFakemon Foo 0\nEnd', 'Block A:\nSetFlag 5bad\nEnd', 'Block A:\nCall Missing\nEnd', 'Block A:\nIfFlag Foo Missing\nEnd', 'Block A:\nIfNotFlag Foo Missing\nEnd', 'Block A:\nTextBox "a"b\nEnd', 'Block A:\nTextBox "bad\\q"\nEnd']:
		check(not Parser.parse(source).valid, "Reject: " + source)
	check(Parser.parse('Block A:\nSetFlg Foo\nEnd').diagnostics[0].message.contains('SetFlag'), "Typo suggestion")
	check(Registry.suggestion("zzzzzzzz").is_empty(), "No unrelated suggestion")
	check(Parser.parse(" Block   A :\n End ").valid, "Declaration whitespace insignificant")
	check(Parser.parse("Block A:\nCall A\nEnd").diagnostics[0].severity == "warning", "Direct recursion warning")
	check(Parser.parse('Block A:\nSetFlag Foo\nEnd').diagnostics.is_empty(), "Valid command has no typo diagnostics")
	for pair in [["Tex", "TextBox"], ["SetF", "SetFlag"], ["IfN", "IfNotFlag"], ["Call Prof", "Professor"], ["IfFlag Foo Prof", "Professor"], ["IfNotFlag Foo Prof", "Professor"]]:
		check(pair[1] in Registry.completions(pair[0], {"Professor":[]}), "Completion: " + pair[0])
	check(Registry.completions('TextBox hello ', {}).is_empty(), "No command completion inside arguments")
	check(not Parser.parse('Block A:\nGiveFakemon Foo 5\nEnd', {"species":["Bar"]}).valid, "Species registry validation")
	check(not Parser.parse('Block A:\nWarp missing 0 0\nEnd', {"map":["known"]}).valid, "Map registry validation")
	var flags := Flags.new(); check(not flags.has_flag("Foo"), "Unset flag false")
	run('Block A:\nSetFlag Foo\nEnd', "A", flags); check(flags.has_flag("Foo"), "SetFlag")
	var restored := Flags.new(); restored.restore(JSON.parse_string(JSON.stringify(flags.values))); check(restored.has_flag("Foo"), "Flag serialized/restored")
	run('Block A:\nClearFlag Foo\nEnd', "A", flags); check(not flags.has_flag("Foo"), "ClearFlag")
	trace.clear()
	run('Block A:\nTextBox "before"\nCall B\nTextBox "after"\nEnd\nBlock B:\nTextBox "inside"\nReturn\nEnd')
	check(trace == ["TextBox:before", "TextBox:inside", "TextBox:after"], "Call and Return ordering")
	trace.clear(); run('Block A:\nCall B\nTextBox "unreachable"\nEnd\nBlock B:\nEnd'); check(trace.is_empty(), "End stops whole execution")
	check(not run('Block A:\nReturn\nEnd').running, "Top-level Return terminates")
	trace.clear(); run('Block A:\nIfFlag Foo B\nIfNotFlag Foo C\nEnd\nBlock B:\nTextBox "true"\nReturn\nEnd\nBlock C:\nTextBox "false"\nReturn\nEnd', "A", flags); check(trace == ["TextBox:false"], "False condition")
	flags.set_flag("Foo", true); trace.clear(); run('Block A:\nIfFlag Foo B\nIfNotFlag Foo C\nEnd\nBlock B:\nTextBox "true"\nReturn\nEnd\nBlock C:\nTextBox "false"\nReturn\nEnd', "A", flags); check(trace == ["TextBox:true"], "True condition")
	var recursive := run('Block A:\nCall A\nEnd'); check(not recursive.running and errors[-1].reason.contains("32"), "Depth guard")
	check(errors[-1].map == "fixture" and errors[-1].block == "A" and errors[-1].line == 2 and errors[-1].command == "Call", "Failure context")
	trace.clear(); run('Block A:\nInvalid Command\nEnd'); check(trace.is_empty(), "Invalid command never dispatched")
	check(errors[-1].line == 2 and errors[-1].command == "Invalid", "Invalid source reports offending line/token")
	var fail_runner := Runner.new(); fail_runner.failed.connect(func(details):errors.append(details))
	fail_runner.start('Block A:\nLock\nEnd', "A", "fixture", flags, func(_c, _a, _r):return {"error":"failure"}, func():cleaned += 1)
	check(not fail_runner.running and errors[-1].reason == "failure", "Host failure stops safely")
	var pending := Runner.new(); var callbacks: Array[Callable] = []
	pending.start('Block A:\nTextBox "wait"\nSetFlag Resumed\nEnd', "A", "fixture", flags, func(_c, _a, resume):callbacks.append(resume);return {"pending":true}, func():cleaned += 1)
	check(pending.waiting and not flags.has_flag("Resumed"), "Dialogue waits")
	callbacks[0].call(); check(not pending.running and flags.has_flag("Resumed"), "Dialogue resumes")
	callbacks[0].call(); check(not pending.running, "Stale callback ignored")
	var fixture := FileAccess.get_file_as_string("res://tests/fixtures/research_institute.paradise")
	check(Parser.parse(fixture).valid, "Integration fixture parses")
	trace.clear(); run(fixture, "ProfessorIntroduction", flags)
	check(flags.has_flag("MetProfessor") and trace.size() == 5, "Integration fixture executes")
	for sample in ['TextBoxYesNo "Choose?"', 'IfYes B', 'IfNo B']:
		check(Parser.parse('Block A:\n'+sample+'\nEnd\nBlock B:\nReturn\nEnd').valid,"Choice syntax: "+sample)
	for sample in ['TextBoxYesNo unquoted','IfYes Missing','IfNo Missing']:
		check(not Parser.parse('Block A:\n'+sample+'\nEnd').valid,"Invalid choice syntax: "+sample)
	check("B" in Registry.completions("IfYes ",{"B":[]}) and "B" in Registry.completions("IfNo ",{"B":[]}),"Choice branches autocomplete Block names")
	var choice_source := 'Block A:\nTextBoxYesNo "Choose?"\nIfYes Y\nIfNo N\nSetFlag Continued\nEnd\nBlock Y:\nSetFlag YesBranch\nReturn\nEnd\nBlock N:\nSetFlag NoBranch\nReturn\nEnd'
	for yes: bool in [true,false]:
		var answer_state := Flags.new(); var choice := Runner.new()
		choice.start(choice_source,"A","fixture",answer_state,func(_c,_a,_r):return {"pending":true},func():pass)
		check(choice.waiting and answer_state.values.is_empty(),"Yes/no does not proceed before answer")
		choice.answer_choice(choice.generation,yes)
		check(answer_state.has_flag("YesBranch") == yes and answer_state.has_flag("NoBranch") != yes and answer_state.has_flag("Continued"),"Answer takes only matching branch and Return resumes")
		check(choice.last_answer == -1 and not choice.running,"Answer cleared at execution boundary")
	var no_question := run('Block A:\nIfYes B\nEnd\nBlock B:\nEnd')
	check(not no_question.running and errors[-1].reason.contains("answered TextBoxYesNo"),"Branch without answer fails clearly")
	var cancelled := Runner.new(); var cancel_flags := Flags.new()
	cancelled.start(choice_source,"A","fixture",cancel_flags,func(_c,_a,_r):return {"pending":true},func():pass)
	var old_ticket := cancelled.generation; cancelled.stop(); cancelled.answer_choice(old_ticket,true)
	check(cancel_flags.values.is_empty() and cancelled.last_answer == -1,"Cancelled question cannot grant rewards")
	cancelled.start(choice_source,"A","fixture",cancel_flags,func(_c,_a,_r):return {"pending":true},func():pass)
	cancelled.answer_choice(old_ticket,true)
	check(cancelled.waiting and cancelled.last_answer == -1,"Old answer cannot affect a new execution")
	cancelled.stop()
	print("SCRIPTING_TEST: %d checks, %d failures" % [checks, failures]); quit(1 if failures else 0)
