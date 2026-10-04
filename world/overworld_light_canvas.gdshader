shader_type canvas_item;
render_mode unshaded;
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
uniform vec2 viewport_size = vec2(1.0);
uniform bool light_source = false;
varying vec4 vertex_color;
void vertex() { vertex_color = COLOR; }
void fragment() {
 COLOR = vertex_color * texture(TEXTURE, UV);
 COLOR.rgb *= mix(night_tint.rgb, vec3(1.0), light_source ? 1.0 : illumination(SCREEN_UV * viewport_size));
}
