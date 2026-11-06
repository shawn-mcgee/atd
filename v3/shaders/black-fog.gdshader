shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform sampler2D visibility_map : filter_linear, repeat_disable;
uniform float map_span = 76.0;
uniform float fog_time = 0.0;
uniform float memory_opacity = 0.58;
uniform float edge_opacity = 0.82;
uniform float edge_reach = 1.6;
uniform float drift_speed = 0.09;
uniform float noise_scale = 1.25;
varying vec2 ground_position;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x),
		mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
void vertex() { ground_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz; }
void fragment() {
	vec2 uv = ground_position / map_span + vec2(0.5);
	vec2 field = texture(visibility_map, uv).rg;
	float reach = edge_reach / map_span;
	float surround = (texture(visibility_map, uv + vec2(reach, 0)).g
		+ texture(visibility_map, uv - vec2(reach, 0)).g
		+ texture(visibility_map, uv + vec2(0, reach)).g
		+ texture(visibility_map, uv - vec2(0, reach)).g) * 0.25;
	// Only the fringe curls into visible ground. The interior stays clear.
	float fringe = clamp((1.0 - surround) * field.g * 2.4, 0.0, 1.0);
	float t = fog_time * drift_speed;
	vec2 p = ground_position * noise_scale;
	vec2 curl = vec2(noise(p * 0.45 + vec2(t, -t * 0.4)),
		noise(p * 0.45 + vec2(7.1 - t * 0.3, 3.2 + t * 0.6)));
	vec2 warped = p + (curl - 0.5) * 3.6 + vec2(t * 0.3, -t);
	float smoke = noise(warped * 0.7) * 0.7 + noise(warped * 1.7) * 0.3;
	float tendrils = pow(1.0 - abs(sin(warped.x * 1.8 + warped.y * 0.6 + smoke * 7.0)), 3.0);
	float unexplored = 1.0 - smoothstep(0.04, 0.82, field.r);
	float remembered = (1.0 - smoothstep(0.05, 0.95, field.g)) * memory_opacity;
	float edge = fringe * edge_opacity * (0.2 + smoothstep(0.2, 0.85, smoke) * 0.45 + tendrils * 0.35);
	ALPHA = clamp(max(unexplored, remembered * (0.7 + smoke * 0.3)) + edge, 0.0, 1.0);
	// Deep unknown space remains opaque black; charcoal billows live at its rim.
	float billow = clamp(surround * (1.0 - field.g) * 2.0 + fringe * 0.4, 0.0, 1.0);
	ALBEDO = vec3(0.016, 0.022, 0.028) * smoke * billow;
}
