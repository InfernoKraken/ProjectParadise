shader_type canvas_item;

uniform sampler2D occlusion_mask : filter_nearest, repeat_disable;
uniform vec2 canvas_size = vec2(208.0, 336.0);
varying vec2 canvas_uv;

void vertex() {
	// Use the full base canvas, independent of its packed atlas UVs/margins.
	canvas_uv = VERTEX / canvas_size + vec2(0.5);
}

void fragment() {
	COLOR.a *= 1.0 - texture(occlusion_mask, canvas_uv).a;
}
