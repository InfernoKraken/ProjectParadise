extends RefCounted

# Authoritative command schema. Types also identify reference arguments.
const DEFINITIONS := {
	"TextBox": ["string"], "TextBoxYesNo": ["string"], "IfYes": ["block"], "IfNo": ["block"], "Call": ["block"], "Return": [], "End": [],
	"SetFlag": ["identifier"], "ClearFlag": ["identifier"],
	"IfFlag": ["identifier", "block"], "IfNotFlag": ["identifier", "block"],
	"ShowSprite": ["sprite"], "HideSprite": ["sprite"],
	"ShowObject": ["object"], "HideObject": ["object"],
	"FadeOut": [], "FadeIn": [], "GiveFakemon": ["species", "level"],
	"Warp": ["map", "number", "number"], "Lock": [], "Unlock": [],
	"ShowSpritePicture": ["picture", "number", "number"],
	"HideSpritePicture": ["picture"], "SaveGame": [], "HealParty": [],
	"MoveSprite": ["sprite", "move_path"], "FollowSprite": ["actor", "target", "follow_path"],
	"StopFollowing": ["actor"], "ResumeMovement": ["sprite"], "WaitMovement":["actor"], "Wait":["duration"], "FaceSprite": ["actor", "facing"]
}

# Argument names, category, blocking, behavior, example. Types remain above.
const HELP := {
	"TextBox": [["Content"], "Dialogue / UI", true, "Displays quoted text using the dialogue panel; waits for dismissal. Escape cancels the sequence.", 'TextBox "Welcome."'],
	"TextBoxYesNo": [["Content"], "Dialogue / UI", true, "Displays quoted text with Yes and No buttons and waits for an explicit answer. Records the answer for IfYes/IfNo in this script execution only. Escape cancels without choosing. No is initially focused.", 'TextBoxYesNo "Choose Scorchick?"'],
	"IfYes": [["BlockName"], "Control Flow", false, "Calls the Block if the latest TextBoxYesNo answer in this execution was Yes. Return resumes the caller; End ends the sequence. Fails clearly if no question has been answered.", "IfYes ReceiveStarter"],
	"IfNo": [["BlockName"], "Control Flow", false, "Calls the Block if the latest TextBoxYesNo answer in this execution was No. Return resumes the caller; End ends the sequence. Fails clearly if no question has been answered.", "IfNo DeclineStarter"],
	"Call": [["BlockName"], "Control Flow", false, "Calls a named Block. Return resumes the caller; End terminates the entire sequence.", "Call Explanation"],
	"Return": [[], "Control Flow", false, "Returns to the caller, or safely ends execution when no caller exists.", "Return"],
	"End": [[], "Control Flow", false, "Closes a Block and terminates the entire running sequence when reached.", "End"],
	"SetFlag": [["FlagName"], "State", false, "Sets a game-owned persistent flag true.", "SetFlag MetProfessor"],
	"ClearFlag": [["FlagName"], "State", false, "Clears a persistent flag. Unset flags evaluate false.", "ClearFlag MetProfessor"],
	"IfFlag": [["FlagName", "BlockName"], "State", false, "Calls the Block when the flag is true; otherwise continues.", "IfFlag MetProfessor Greeting"],
	"IfNotFlag": [["FlagName", "BlockName"], "State", false, "Calls the Block when the flag is false or unset; otherwise continues.", "IfNotFlag MetProfessor Introduction"],
	"ShowSprite": [["SpriteId"], "World / Visibility", false, "Restores the placed NPC's visibility, authored collision and interaction. Does not restart cancelled movement.", "ShowSprite Professor"],
	"HideSprite": [["SpriteId"], "World / Visibility", false, "Disables a placed NPC's visibility, collision and interaction while preserving its definition; safely cancels Move/Follow. Repeated hiding is safe.", "HideSprite Professor"],
	"ShowObject": [["ObjectId"], "World / Visibility", false, "Restores registered instance-ID artwork. Does not change collision.", "ShowObject placed_4"],
	"HideObject": [["ObjectId"], "World / Visibility", false, "Hides registered instance-ID artwork. Does not change collision.", "HideObject placed_4"],
	"FadeOut": [[], "Dialogue / UI", true, "Fades to black over 0.25 seconds, then continues. Script cleanup removes the overlay.", "FadeOut"],
	"FadeIn": [[], "Dialogue / UI", true, "Fades from the current overlay to clear over 0.25 seconds.", "FadeIn"],
	"GiveFakemon": [["Species", "Level"], "Player / Party", false, "Creates a known species at level 1–100 in the existing party. A full seven-member party fails safely.", "GiveFakemon Sylvafin 5"],
	"Warp": [["MapName", "PositionX", "PositionZ"], "Map", false, "Warps to map-local X/Z on a loaded playable map and terminates execution at the map boundary.", "Warp rainforest_clearing 2 3"],
	"Lock": [[], "Script Control", false, "Idempotently prevents normal player control. Scripted NPC movement still runs. Cleanup releases the lock.", "Lock"],
	"Unlock": [[], "Script Control", false, "Idempotently restores player control.", "Unlock"],
	"ShowSpritePicture": [["Filename", "X", "Y"], "Dialogue / UI", false, "Shows a PNG from assets/overworld at viewport pixel coordinates; cleanup removes script pictures.", "ShowSpritePicture indoor_aquarium_long.png 10 20"],
	"HideSpritePicture": [["Filename"], "Dialogue / UI", false, "Removes the named script picture. Repeated removal is safe.", "HideSpritePicture indoor_aquarium_long.png"],
	"HealParty": [[], "Player / Party", false, "Restores all party HP and clears persistent conditions using the medical ward healing service, then autosaves.", "HealParty"],
	"SaveGame": [[], "Save", false, "Uses the existing save service and selected manual slot, including persistent flags. Service restrictions still apply.", "SaveGame"],
	"MoveSprite": [["SpriteId", "PathName"], "Movement", true, "Moves an NPC through every ordered MOVE node, including its approach to node one. Waits for completion. Attempts bounded local detours. If the player is the remaining blocker, pauses with a step-aside prompt and resumes when clear; other sustained blockage fails safely.", "MoveSprite Professor ProfessorApproach"],
	"FollowSprite": [["ActorId", "TargetId", "PathName"], "Movement", false, "Starts NPC or Player following at close distance. Omit PathName to reuse the guide's actual traveled route, including a completed Move; supply a FOLLOW path to constrain travel to its corridor. Recorded routes retain turns and local detours. Player following uses normal collision and temporarily owns manual movement; StopFollowing Player or Escape releases it. Continues after End; stops near the target and retries blocked movement without teleporting.", "FollowSprite Professor Player InstituteTour"],
	"StopFollowing": [["ActorId"], "Movement", false, "Ends follow mode and holds the NPC at its current position, or restores manual Player control. Repeating is safe.", "StopFollowing Professor"],
	"ResumeMovement": [["SpriteId"], "Movement", false, "Cancels scripted Move/Follow or held movement and restores the NPC's authored idle preset and range around its original placement. Returns gradually into range using normal collision; does not teleport, reveal hidden NPCs or change saved settings. Repeating while idle is safe. NPCs only.", "ResumeMovement NPC1"],
	"WaitMovement": [["ActorId"], "Movement", true, "Waits for an active move to finish, a random walking leg, or one successful loop returning to its start after leaving. Stationary/completed actors resume immediately; cancellation fails safely.", "WaitMovement NPC3"],
	"Wait": [["Seconds"], "Script Control", true, "Pauses execution for a finite non-negative duration in seconds. Cancelling the script prevents delayed continuation.", "Wait 15"],
	"FaceSprite": [["ActorId", "DirectionOrTarget"], "Movement", false, "Immediately turns an NPC or Player to a cardinal direction or toward another actor. The first argument is the actor being turned; the second is its direction or target.", "FaceSprite Professor Player"]
}

const TYPE_HELP := {
	"string":"Quoted string; escapes: quote, backslash, newline, tab.", "block":"Existing Block name.", "identifier":"ASCII identifier: letter/underscore, followed by letters/digits/underscores.",
	"sprite":"Existing placed NPC: numeric ID, NPC<ID>, or an alias from SCRIPT mode.", "object":"Existing object instance_id with registered artwork.",
	"species":"Existing Fakemon species; quote names containing spaces.", "level":"Integer from 1 to 100.", "map":"Loaded playable map filename or basename.", "number":"Finite numeric literal.",
	"picture":"PNG filename in assets/overworld; directory traversal is forbidden.", "move_path":"Existing MOVE path with at least one node.", "follow_path":"Existing FOLLOW path with at least two distinct nodes.",
	"actor":"Player or an existing map-local NPC ID/alias.", "duration":"Finite non-negative seconds.",
	"target":"Player or another existing placed NPC on the current map.", "facing":"North, South, East, West, Player, or another current-map NPC."
}

static func minimum_arguments(command: String) -> int:
	return 2 if command == "FollowSprite" else DEFINITIONS[command].size()

static func metadata(command: String) -> Dictionary:
	var info: Array = HELP[command]
	return {"name":command, "argument_names":info[0], "argument_types":DEFINITIONS[command], "category":info[1], "blocking":info[2], "description":info[3], "example":info[4]}

static func errors(command: String) -> String:
	if command in ["MoveSprite", "FollowSprite"]: return "Missing actor/target/path; wrong path type; invalid nodes; self-follow. Move also fails after sustained collision blockage or cancellation."
	if command == "FaceSprite": return "Missing actor or invalid direction/target."
	return "Invalid argument count/type or missing referenced resource; game service failure where applicable."

static func identifier(value: String) -> bool:
	if value.is_empty(): return false
	for i in value.length():
		var c := value.unicode_at(i)
		if not (c == 95 or c >= 65 and c <= 90 or c >= 97 and c <= 122 or i > 0 and c >= 48 and c <= 57): return false
	return true

static func distance(a: String, b: String) -> int:
	var row: Array[int] = []
	for j in b.length() + 1: row.append(j)
	for i in a.length():
		var next: Array[int] = [i + 1]
		for j in b.length(): next.append(mini(mini(next[j] + 1, row[j + 1] + 1), row[j] + (0 if a[i] == b[j] else 1)))
		row = next
	return row[-1]

static func suggestion(word: String) -> String:
	var best := ""
	var score := 999
	for name: String in DEFINITIONS:
		var d := distance(word.to_lower(), name.to_lower())
		if d < score: score = d; best = name
	return best if score <= mini(2, maxi(1, word.length() / 3)) else ""

static func completions(before_caret: String, blocks: Dictionary, references: Dictionary = {}) -> Array[String]:
	var tokens := before_caret.strip_edges(true, false).replace("\t", " ").split(" ", false)
	var argument := before_caret.ends_with(" ") or before_caret.ends_with("\t")
	var prefix := "" if argument or tokens.is_empty() else String(tokens[-1])
	var pool: Array = []
	var index := tokens.size() if argument else tokens.size() - 1
	if index <= 0: pool = ["Block"] + DEFINITIONS.keys()
	elif DEFINITIONS.has(tokens[0]):
		var types: Array = DEFINITIONS[tokens[0]]
		if index <= types.size() and types[index - 1] == "block": pool = blocks.keys()
		elif index <= types.size(): pool = references.get(types[index - 1], [])
	var result: Array[String] = []
	for value: String in pool:
		if value.begins_with(prefix): result.append(value)
	return result
