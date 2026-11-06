shader_type spatial;
uniform vec4 paint_color : source_color = vec4(0.3, 0.35, 0.38, 1.0);
varying vec3 surface_position;
float grain(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}
float wear(vec3 p) {
	vec3 c = floor(p);
	vec3 f = smoothstep(vec3(0.0), vec3(1.0), fract(p));
	return mix(mix(mix(grain(c), grain(c + vec3(1,0,0)), f.x),
		mix(grain(c + vec3(0,1,0)), grain(c + vec3(1,1,0)), f.x), f.y),
		mix(mix(grain(c + vec3(0,0,1)), grain(c + vec3(1,0,1)), f.x),
		mix(grain(c + vec3(0,1,1)), grain(c + vec3(1,1,1)), f.x), f.y), f.z);
}
void vertex() { surface_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	// World-space wear works on the beveled procedural meshes without UV seams.
	float patches = wear(surface_position * 4.0);
	ALBEDO = paint_color.rgb * (0.85 + patches * 0.19);
	ROUGHNESS = 0.8 + patches * 0.12;
	METALLIC = 0.25;
}
