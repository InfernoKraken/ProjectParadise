shader_type spatial;
render_mode unshaded, cull_disabled;
uniform vec4 night_tint : source_color = vec4(1.0);
uniform sampler2D light_data : filter_nearest, repeat_disable;
uniform int light_count = 0;
float illumination(vec2 pixel) {
 float amount = 0.0;
 for (int i = 0; i < light_count; i++) {
  vec4 light = texelFetch(light_data, ivec2(i, 0), 0);
  float distance_to_light = length((pixel - light.xy) / max(light.zw, vec2(0.001)));
  amount = max(amount, 1.0 - smoothstep(0.15, 1.0, distance_to_light));
 }
 return amount;
}
uniform sampler2D albedo_texture : source_color, filter_nearest, repeat_enable;
uniform vec2 viewport_size = vec2(1.0);
uniform vec2 uv_scale = vec2(1.0);
uniform vec2 uv_offset = vec2(0.0);
uniform vec4 base_color : source_color = vec4(1.0);
uniform bool billboard_enabled = false;
void vertex() {
 if (billboard_enabled) {
  MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
   INV_VIEW_MATRIX[0] * length(MODEL_MATRIX[0].xyz),
   INV_VIEW_MATRIX[1] * length(MODEL_MATRIX[1].xyz),
   INV_VIEW_MATRIX[2] * length(MODEL_MATRIX[2].xyz),
   MODEL_MATRIX[3]);
 }
}
void fragment() {
 vec4 tex = texture(albedo_texture, UV * uv_scale + uv_offset) * base_color;
 ALBEDO = tex.rgb * mix(night_tint.rgb, vec3(1.0), illumination(SCREEN_UV * viewport_size));
 ALPHA = tex.a;
 ALPHA_SCISSOR_THRESHOLD = 0.01;
}
