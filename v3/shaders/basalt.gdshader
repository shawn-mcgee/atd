shader_type spatial;
render_mode specular_disabled;
uniform float strata_strength = 0.32;
varying vec3 stone_position;
varying vec3 stone_tint;
void vertex() {
	stone_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	stone_tint = COLOR.rgb;
}
void fragment() {
	float folded = stone_position.y * 19.0 + sin(stone_position.x * 3.2 + stone_position.z * 2.4) * 1.7;
	float seams = smoothstep(0.68, 0.94, sin(folded) * 0.5 + 0.5);
	float flecks = sin(stone_position.x * 29.0) * sin(stone_position.z * 31.0 + stone_position.y * 17.0);
	ALBEDO = stone_tint * (1.0 - seams * strata_strength + flecks * 0.035);
	ROUGHNESS = 0.97;
}
