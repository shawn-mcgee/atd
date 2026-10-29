shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled;
uniform vec3 pick_rgb = vec3(0.0);
vec3 to_linear(vec3 rgb) {
	vec3 low = rgb / 12.92;
	vec3 high = pow((rgb + vec3(0.055)) / 1.055, vec3(2.4));
	return mix(high, low, vec3(1.0) - step(vec3(0.04045), rgb));
}
void fragment() {
	ALBEDO = OUTPUT_IS_SRGB ? pick_rgb : to_linear(pick_rgb);
}
