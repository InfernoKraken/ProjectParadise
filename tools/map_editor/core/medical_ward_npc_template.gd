extends RefCounted

const SOURCE := """Block %s:
    Lock
    TextBox "Welcome to the medical ward."
    TextBox "Leave your Fakemon with me for a moment, and I will restore them to full health."
    HealParty
    TextBox "Your party is fully rested. We hope to see you again!"
    Unlock
    End
"""

# The existing map-owned script and NPC companion format remain authoritative.
static func install(map:Dictionary,definitions:Dictionary,position:Array=[0,0,0])->int:
	var id:=1
	for record in map.get("npcs",[]):id=maxi(id,int(record.get("id",0))+1)
	for key in definitions:if str(key).is_valid_int():id=maxi(id,int(key)+1)
	var source:=str(map.get("script_source",""))
	var block_name:="MedicalWardCare"
	var suffix:=2
	while source.contains(block_name):
		block_name="MedicalWardCare%d"%suffix;suffix+=1
	if not map.has("npcs"):map["npcs"]=[]
	map.npcs.append({"id":id,"position":position.duplicate(),"facing":"down"})
	definitions[str(id)]={"type":"human","sprite":"Young Woman","interaction_text":"","hidden":false}
	map["script_source"]=source+("\n" if not source.is_empty() else "")+SOURCE%block_name
	if not map.has("script_interactions"):map["script_interactions"]={}
	map.script_interactions["npc:%d"%id]=block_name
	return id
