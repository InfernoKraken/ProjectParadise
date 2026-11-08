extends RefCounted

const Registry = preload("command_registry.gd")

static func render() -> String:
	var text := """# Project Paradise Scripting Reference

<!-- Generated from world/scripting/command_registry.gd. Do not hand-edit command entries. -->

## Script Structure

```text
Block Example:
    Lock
    TextBox "Hello."
    Unlock
End
```

Blocks have unique names. End closes a Block in source and ends the entire running
sequence when reached. Call enters another Block; Return resumes the caller or ends
safely without one. Maximum call depth is 32. Direct recursive calls are warned about.
Blank lines and indentation are insignificant. `//` starts a comment outside strings.
TextBox requires quoted text and supports escaped quotes, backslashes, newline, and tab.
Commands and references are case sensitive. Arguments are separated by whitespace;
quote species names containing spaces. Numeric arguments are literals, not expressions.
Persistent string-named flags are game-owned and survive saves; unset flags are false.
There are no variables, expressions, loops, custom commands, or arbitrary Godot execution.

## Yes/No dialogue and starters

TextBoxYesNo waits for an explicit Yes or No. Use the mouse or focus a button
with the keyboard and press Enter/Space; No is initially focused. Escape cancels
the script without an answer. IfYes and IfNo call named Blocks using the latest
answer in this execution. Return resumes the caller; End ends the whole sequence.
A new question replaces the previous answer. Answers reset at script boundaries,
are never saved, and branching without an answered question fails clearly.

```text
Block OfferStarter:
    TextBoxYesNo "Choose Scorchick?"
    IfYes ReceiveStarter
    IfNo DeclineStarter
End
Block ReceiveStarter:
    GiveFakemon Scorchick 5
    SetFlag Starter
    SetFlag StarterFire
    HideSprite NPC2
End
Block DeclineStarter:
    TextBox "Take your time."
    Return
End
```

New adventures start after player appearance selection with no party. The Institute
starter interactions use the persistent Starter flag to prevent choosing twice.
StarterFire/StarterWater/StarterGrass remember which placed starter to hide on every
map entry. Declining or cancelling grants nothing. GiveFakemon uses the existing
party service and initializes the follower when the first Fakemon is received.
Pre-starter adventures can be saved/loaded; battles wait until there is a party.
Older saves that already began with a Fakemon are treated as having chosen a starter.
The map editor's Test Map still supplies its existing test party for exploration.

## Map resources and authoring

The map JSON root owns `script_source`, `script_interactions`, optional
`script_sprite_names` aliases, and `script_paths`. Placement/NPC definitions are separate.
Numeric NPC IDs and `NPC1`, `NPC2`, etc. work without aliases. Set an alias such as
Professor by selecting the NPC in SCRIPT → Source. Player can be a FollowSprite
follower or target; MoveSprite still requires an NPC. North/South/East/West are reserved direction names.

```json
{
  "script_sprite_names": {"Professor": 1},
  "script_paths": [
    {"name": "ProfessorApproach", "type": "MOVE", "nodes": [[0, 0], [2, 0]]},
    {"name": "InstituteTour", "type": "FOLLOW", "nodes": [[0, 0], [2, 0], [2, 4]]}
  ]
}
```

SCRIPT → Paths creates, renames, deletes, and selects paths. Add Node appends a point;
Insert After creates a midpoint; Delete Node removes it. Edit X/Z or drag a handle.
Enable Add nodes by clicking map to append snapped points on the canvas. Nodes are
ordered, map-local X/Z. MOVE requires one node; FOLLOW requires two distinct nodes.
Coordinates must be finite and within ±1,000,000 for engine safety.
MOVE is solid orange with arrows; FOLLOW is dashed cyan with
arrows. Both are labeled by type/name and disappear outside SCRIPT. Rename/delete
does not rewrite source; stale references are validation errors. Map undo/save/load
preserves path data. Legacy maps need none of these optional fields.

MOVE visits all nodes and waits; FOLLOW uses the ordered route as a corridor, not
a mandatory tour sequence. Followers project themselves and the target onto the
route, approach the corridor, and progress in either direction via intervening bends.
They stop within 1.25 world units of their target. Targets more than 3 units from the
route pause pursuit until reachable again. NPCs use existing speed, collision sweeps,
and animation; blocked followers retry without pushing the player or teleporting.
Move fails after 2 seconds of sustained collision blockage. Paths do not override
NPC ground/flying/swimming rules. Prefer simple routes without branching or crossings.

Following survives successful script completion; StopFollowing holds the actor at
its current position. Follow state ends on map transitions, new adventures, or loads
and is not saved. ResumeMovement NPC1 releases scripted Move/Follow/Hold and
restores its authored idle preset and range around the original placement. An NPC
outside its range returns gradually with normal collision before wandering; the
command never teleports or reveals hidden actors. StopFollowing instead holds
the NPC in place. Script cancellation ends active Move requests and
releases input locks; established Follow modes are independent of the interpreter.
Editor collision warnings cover known extracted static boxes; runtime physics also
checks other colliders and the approach to the first node. Red segments denote
warnings, not proof that all other segments are clear. Collision is never disabled.

Show/Hide changes artwork, not collision. Pictures use viewport pixels and PNGs in
assets/overworld. GiveFakemon uses the seven-member party; full parties fail rather
than creating a storage system. Warp ends execution at the map boundary. SaveGame
uses the selected manual slot. Script-owned dialogue, pictures, and fades are cleared
on completion/cancellation/failure; flags already executed are not rolled back.

## Command inventory

Blocking describes whether the command waits on an engine operation. Call/conditions
still execute their target Block sequentially, which can contain blocking commands.

"""
	var categories: Array[String] = []
	for command: String in Registry.DEFINITIONS:
		var category: String = Registry.metadata(command).category
		if not category in categories: categories.append(category)
	for category in categories:
		text += "## %s\n\n" % category
		for command: String in Registry.DEFINITIONS:
			var meta := Registry.metadata(command)
			if meta.category != category: continue
			var signature := command
			if not meta.argument_names.is_empty(): signature += " " + " ".join(meta.argument_names.slice(0,2)) + " [PathName]" if command == "FollowSprite" else " " + " ".join(meta.argument_names)
			text += "### %s\n\nSyntax:\n\n```text\n%s\n```\n\nArguments:\n\n" % [command, signature]
			if meta.argument_names.is_empty(): text += "None.\n\n"
			for i in meta.argument_names.size(): text += "- `%s` (%s): %s\n" % [meta.argument_names[i], meta.argument_types[i], Registry.TYPE_HELP[meta.argument_types[i]]]
			text += "\nBehavior: %s\n\nExample:\n\n```text\n%s\n```\n\nErrors: %s\n\nBlocking: **%s**.\n\n" % [meta.description, meta.example, Registry.errors(command), "Yes" if meta.blocking else "No"]
	text += "## Regenerating this reference\n\nRun `godot --headless --rendering-driver opengl3 --path . --script res://world/scripting/generate_reference.gd`. The reference regression test compares this file to registry-generated output and checks metadata and examples.\n"
	text += """
## Map Scripts on entry

Under the editor's MAP tab, click + Add Map Script. Each entry has a Flag and
multiline command editors for the true and false/unset outcomes. Block wrappers
and unique Block names are created automatically; type several commands in each
outcome. Code completion suggests commands, NPC aliases, flags and Block names.
Inline diagnostics and the save banner explain invalid commands or references.

The editors share the map's existing script_source with NPC interactions. Both
outcomes are required and evaluated anew on each entry and save restoration.
Multiple headers execute in list order; flag changes affect subsequent headers.
Legacy map_script_header records remain supported. Their true_block/false_block
fields contain Block names, not commands; editing their outcome bodies repairs
old command-filled references without deleting the other map scripts.

Example map field:

~~~json
"map_script_headers": [{
  "flag": "StarterChosen",
  "true_block": "ProfessorPresent",
  "false_block": "ProfessorAbsent"
}]
~~~

Example source (replace NPC2 with your professor's map-local ID or alias):

~~~text
Block ProfessorPresent:
    ShowSprite NPC2
    HideSprite NPC3
    FaceSprite NPC2 South
    End

Block ProfessorAbsent:
    HideSprite NPC2
    ShowSprite NPC3
    End
~~~

Headers permit ShowSprite, HideSprite, FaceSprite, SetFlag, ClearFlag, Call,
IfFlag, IfNotFlag, Return and End. Both branches and every reachable helper are
validated before any header runs. Missing targets, recursion, dialogue, movement,
waits, fades, save commands, party changes and warps are rejected. Execution is synchronous
after NPC registration and before interaction on entry, including same-map reloads.

HideSprite preserves the NPC definition and registry entry while disabling visual,
body collision, interaction and script activation. It cancels Move/Follow safely.
ShowSprite restores authored collision and interaction without resuming cancelled
movement. Repeated Show/Hide is safe. Editor NPCs stay visible and selectable.
The NPC Inspector's Hidden checkbox sets the initial runtime state (legacy NPCs
default to visible). It is stored as a boolean hidden field in the NPC companion
definition. ShowSprite and HideSprite override that state at runtime without
changing the authored checkbox. New games and save restoration apply the authored
default before the map header evaluates both flag outcomes.
## Guided player tours and waits

FollowSprite accepts Player or an NPC as follower. No trail argument is needed:
FollowSprite Player NPC11 automatically reuses the guide's actual traveled route,
including turns and collision detours. The route is recorded before any follower
exists and retained after MoveSprite completes. Late followers join near their
current position and replay forward. Future Move commands extend the route.
A separate FOLLOW path remains optional when an explicitly drawn corridor is wanted.

With MoveSprite before FollowSprite, the guide finishes its walk first and the
follower then catches up along that recorded route. Put FollowSprite before MoveSprite
to walk together from the start. WaitMovement Player waits for route catch-up before
dialogue; StopFollowing Player ends the tour. The follower stops about 1.25 units
behind the guide along the route, with normal actor collision still enabled.
Routes are transient, bounded to 512 samples per guide and 64 guides, and cleared on
map reset or when a guide is hidden. Teleports reset the trace instead of creating a
fake traversable segment. No saved path nodes or NPC definitions are rewritten.

Player following accounts for the player's terrain footprint and existing bridge
ramps. Ground-level samples incompatible with a raised deck are skipped rather
than repeatedly steering onto and off the deck. Existing bounded obstacle handling
remains a fallback for changed obstacles; route replay is the normal steering method.
Script errors release guided Player control.

Guided movement uses normal player
collision and temporarily owns movement input. StopFollowing Player or Escape
restores manual control. Hiding the guide also releases the player.

~~~text
Block Tour:
    Lock
    FollowSprite Player Professor
    MoveSprite Professor ProfessorApproach
    WaitMovement Player
    StopFollowing Player
    Wait 15
    Unlock
    End
~~~

MoveSprite already blocks until its walk ends. WaitMovement can await an existing
NPC walk or follower independently. A stationary actor finishes immediately;
a looping walk must leave its first node and complete a successful cycle back to
it. Closed FOLLOW paths also require visiting all nodes; open or direct follows finish
when the follower catches up to a guide whose scripted Move has ended. Blocked
walks do not count as completed cycles. Wait accepts finite, non-negative seconds.
NPCs walk at 4.5 map units per second (player walking speed: 5). Scripted Move
and direct Follow use a configurable circular local search radius (default 2.5
map units). Full collider sweeps and terrain footprint checks reject obstacles,
water for ground actors, missing tiles and map edges. Move rejoins the nearest
reachable sampled forward point on the current authored segment; required nodes
remain ordered and unchanged. Search defaults cap visited nodes at 160, segment
checks at 1200, and retries per required waypoint at 5, with a 0.4-second cooldown.
A progress deadline includes expected remaining travel time plus a five-second
allowance and is not reset by intermittent movement. Continuous blockage also
fails after two seconds. Failure identifies the required node that was not reached.
A player-blocked doorway is an explicit exception: if collision would clear without
the player, Move stays pending instead of failing. A step-aside prompt appears and
walking is temporarily allowed even under Lock. Active Player following is released
so manual movement can resolve the blockage. The NPC keeps collision enabled and
resumes from its current position when the player moves clear; Hide/flags run only
after real arrival. Escape, hiding the moving NPC or leaving the map cancels the
pending continuation normally. Static obstructions retain bounded failure behavior.
Configuration lives in npc_script_movement.gd's avoidance dictionary; limits are
clamped. No navigation mesh or global route search is involved.
Both waits are forbidden in map headers, which execute only immediate commands.

Runtime visibility and movement are transient; persisted game flags and the header
establish the correct state after loading a save.
"""
	return text
