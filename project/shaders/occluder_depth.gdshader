shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled;
uniform float camera_far = 200.0;
vec3 to_linear(vec3 rgb) {
	return mix(rgb / 12.92, pow((rgb + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), rgb));
}
void fragment() {
	int code = clamp(int(floor(-VERTEX.z / camera_far * 4094.0)) + 1, 1, 4095);
	vec3 rgb = vec3(float(32 + ((code >> 8) & 15) * 14), float(32 + ((code >> 4) & 15) * 14), float(32 + (code & 15) * 14)) / 255.0;
	ALBEDO = OUTPUT_IS_SRGB ? rgb : to_linear(rgb);
}
