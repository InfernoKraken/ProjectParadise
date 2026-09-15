extends SceneTree

const WorldClockScript := preload("res://world/world_clock.gd")
const DayNightControllerScript := preload("res://world/day_night_controller.gd")

func _init() -> void:
	var clock := WorldClockScript.new()
	clock.minutes_per_real_second = 2.0
	clock.world_minutes = 480.0
	clock._process(30.0)
	assert(is_equal_approx(clock.world_minutes, 540.0), "The world clock must advance independently of rendering.")
	assert(is_equal_approx(clock.get_day_progress(), 9.0 / 24.0), "Day progress must normalize the shared world time.")
	clock.set_time(23, 59)
	clock._process(31.0)
	assert(clock.day == 1 and clock.formatted_time() == "01:01", "The clock must wrap at midnight and count days.")
	var controller := DayNightControllerScript.new()
	controller._ready()
	controller.setup(clock, null)
	var dawn := controller.sampled_color(6.0 / 24.0)
	var noon := controller.sampled_color(12.0 / 24.0)
	var night := controller.sampled_color(0.0)
	assert(dawn.r > dawn.b and noon.r > 0.9 and night.b > night.r, "The curve must provide warm dawn, neutral day, and cool night colors.")
	controller.set_map_type("Indoor")
	assert(not controller.is_day_night_enabled() and controller.canvas_modulate.color == Color.WHITE, "Indoor maps must opt out of day/night tinting.")
	controller.set_map_type("Lush_Cave")
	assert(controller.is_day_night_enabled(), "Only Indoor maps should opt out; other tags remain available to engine events.")
	print("DAY_NIGHT_TEST_PASSED")
	controller.free()
	clock.free()
	quit()
