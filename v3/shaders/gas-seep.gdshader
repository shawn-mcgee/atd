shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform sampler2D visibility_map : filter_linear, repeat_disable;
uniform float map_span = 76.0;
uniform float drift_time = 0.0;
uniform float opacity = 0.22;
varying vec2 ground_position;
void vertex() { ground_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz; }
void fragment() {
	vec2 p = (UV - vec2(0.5)) * 2.0;
	float t = drift_time * 0.65;
	p += vec2(sin(t + ground_position.y * 2.0), cos(t * 0.7 + ground_position.x)) * 0.13;
	float r = length(p);
	float eddies = 0.55 + 0.25 * sin(p.x * 13.0 + t * 1.7 + sin(p.y * 7.0 - t));
	float visible = texture(visibility_map, ground_position / map_span + vec2(0.5)).g;
	ALBEDO = vec3(0.13, 0.19, 0.18);
	ALPHA = (1.0 - smoothstep(0.1, 0.95, r)) * eddies * opacity * visible;
}
