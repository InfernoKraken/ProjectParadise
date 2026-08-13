class_name FakemonAnimator
extends AnimationPlayer


func _ready() -> void:
	# AnimationPlayer's default animation root is its parent (the Fakemon art).
	# A ".." track would therefore reach the BattleScreen and rotate the full UI.
	root_node = NodePath("..")
	var library := AnimationLibrary.new()
	var bob := Animation.new()
	bob.length = 1.6
	bob.loop_mode = Animation.LOOP_LINEAR
	var track := bob.add_track(Animation.TYPE_VALUE)
	bob.track_set_path(track, NodePath(".:rotation"))
	bob.track_insert_key(track, 0.0, -0.012)
	bob.track_insert_key(track, 0.8, 0.012)
	bob.track_insert_key(track, 1.6, -0.012)
	library.add_animation("bob", bob)
	add_animation_library("battle", library)
	play("battle/bob")
