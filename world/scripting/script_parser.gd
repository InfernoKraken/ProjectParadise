extends RefCounted

const Registry = preload("command_registry.gd")

static func diagnostic(out: Dictionary, line: int, token: String, message: String) -> void:
	out.diagnostics.append({"severity":"error", "line":line, "token":token, "message":message})
	out.valid = false

# Pure parsing/validation; optional reference pools come from the caller's registries.
static func parse(source: String, references: Dictionary = {}) -> Dictionary:
	var out := {"valid":true, "blocks":{}, "diagnostics":[]}
	var current := ""
	var declaration_line := 0
	var lines := source.split("\n")
	for index in lines.size():
		var line := index + 1
		var lex := tokenize(lines[index])
		if not lex.error.is_empty(): diagnostic(out, line, "", lex.error); continue
		var tokens: Array = lex.tokens
		if tokens.is_empty(): continue
		var command: String = tokens[0].value
		if command == "Block" and not tokens[0].quoted:
			if tokens.size() == 3 and not tokens[1].quoted and not tokens[2].quoted and tokens[2].value == ":":
				tokens[1].value += ":"; tokens.pop_back()
			if not current.is_empty(): diagnostic(out, line, command, "Missing End for Block %s (line %d)." % [current, declaration_line])
			current = ""
			if tokens.size() != 2 or tokens[1].quoted or not String(tokens[1].value).ends_with(":") or not Registry.identifier(String(tokens[1].value).trim_suffix(":")):
				diagnostic(out, line, command, "Expected Block Name:"); continue
			current = String(tokens[1].value).trim_suffix(":")
			declaration_line = line
			if out.blocks.has(current): diagnostic(out, line, current, "Duplicate Block name."); current = ""; continue
			out.blocks[current] = []
			continue
		if current.is_empty(): diagnostic(out, line, command, "Command must be inside a Block."); continue
		if tokens[0].quoted or not Registry.DEFINITIONS.has(command):
			var guess := Registry.suggestion(command)
			diagnostic(out, line, command, 'Unknown command "%s".%s' % [command, ' Did you mean "%s"?' % guess if not guess.is_empty() else ""]); continue
		var types: Array = Registry.DEFINITIONS[command]
		if tokens.size() - 1 < Registry.minimum_arguments(command) or tokens.size() - 1 > types.size():
			diagnostic(out, line, command, "Expected 2 or 3 arguments (optional FOLLOW path)." if command == "FollowSprite" else "Expected %d arguments." % types.size()); continue
		var args: Array = []
		for i in tokens.size() - 1:
			var token: Dictionary = tokens[i + 1]
			var value: String = token.value
			var type: String = types[i]
			var good := true
			match type:
				"string": good = token.quoted
				"identifier", "block": good = not token.quoted and Registry.identifier(value)
				"level": good = not token.quoted and value.is_valid_int() and int(value) >= 1 and int(value) <= 100
				"number", "duration": good = not token.quoted and value.is_valid_float() and is_finite(float(value)) and (type != "duration" or float(value) >= 0)
				"picture": good = value == value.get_file() and value.to_lower().ends_with(".png")
			if not good: diagnostic(out, line, value, "Invalid %s argument for %s." % [type, command])
			if references.has(type) and not value in references[type]: diagnostic(out, line, value, "Unknown %s reference." % type)
			args.append(int(value) if type == "level" else (float(value) if type in ["number", "duration"] else value))
		out.blocks[current].append({"command":command, "arguments":args, "line":line})
		if command == "End": current = ""
	if not current.is_empty(): diagnostic(out, declaration_line, current, "Missing End for Block %s." % current)
	for block: String in out.blocks:
		for instruction: Dictionary in out.blocks[block]:
			var types: Array = Registry.DEFINITIONS[instruction.command]
			for i in instruction.arguments.size():
				if types[i] == "block" and not out.blocks.has(instruction.arguments[i]): diagnostic(out, instruction.line, instruction.arguments[i], "Target Block does not exist.")
				elif types[i] == "block" and instruction.arguments[i] == block:
					out.diagnostics.append({"severity":"warning", "line":instruction.line, "token":block, "message":"Recursive Block call; runtime stops at depth 32."})
	return out

static func tokenize(text: String) -> Dictionary:
	var result := {"tokens":[], "error":""}
	var i := 0
	while i < text.length():
		if text[i] in [" ", "\t", "\r"]: i += 1; continue
		if text.substr(i, 2) == "//": break
		var quoted := text[i] == '"'
		var value := ""
		if quoted:
			i += 1
			var closed := false
			while i < text.length():
				if text[i] == '"': closed = true; i += 1; break
				if text[i] == "\\":
					i += 1
					if i >= text.length() or not text[i] in ['"', "\\", "n", "t"]: result.error = "Invalid string escape."; return result
					value += "\n" if text[i] == "n" else ("\t" if text[i] == "t" else text[i])
				else: value += text[i]
				i += 1
			if not closed: result.error = "Unterminated quoted string."; return result
			if i < text.length() and not text[i] in [" ", "\t", "\r"] and text.substr(i, 2) != "//": result.error = "Expected whitespace after string."; return result
		else:
			while i < text.length() and not text[i] in [" ", "\t", "\r"] and text.substr(i, 2) != "//":
				if text[i] == '"': result.error = "Quote must begin an argument."; return result
				value += text[i]; i += 1
		result.tokens.append({"value":value, "quoted":quoted})
	return result
