extends RefCounted

signal transferred(party_removed_index: int)

const PARTY_CAPACITY := 7

var party: Array[Dictionary] = []
var cloud: Array[Dictionary] = []


# Returns true when the catch was sent to the Cloud.
func add_capture(mon: Dictionary) -> bool:
	if party.size() < PARTY_CAPACITY:
		party.append(mon)
		return false
	cloud.append(mon)
	return true


func store(index: int) -> String:
	if index < 0 or index >= party.size():
		return "Select a party Fakemon to store."
	if party.size() == 1:
		return "Keep at least one Fakemon in your party."
	cloud.append(party.pop_at(index))
	transferred.emit(index)
	return ""


func withdraw(index: int) -> String:
	if index < 0 or index >= cloud.size():
		return "Select a Cloud Fakemon to withdraw."
	if party.size() >= PARTY_CAPACITY:
		return "Your party is full (%d)." % PARTY_CAPACITY
	party.append(cloud.pop_at(index))
	transferred.emit(-1)
	return ""


func restore(saved_party: Variant, saved_cloud: Variant) -> bool:
	if not saved_party is Array or not saved_cloud is Array or saved_party.size() > PARTY_CAPACITY:
		return false
	for roster: Array in [saved_party, saved_cloud]:
		for mon: Variant in roster:
			if not mon is Dictionary or mon.is_empty():
				return false
	party.assign(saved_party)
	cloud.assign(saved_cloud)
	return true
