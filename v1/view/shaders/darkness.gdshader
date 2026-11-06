shader_type canvas_item;
render_mode unshaded;

uniform sampler2D light_field : filter_linear, repeat_disable;
uniform sampler2D terrain_field : filter_linear, repeat_disable;
uniform bool use_terrain_field = false;
uniform vec2 field_min = vec2(-112.0);
uniform vec2 field_size = vec2(224.0);
uniform vec2 viewport_size = vec2(1280.0, 800.0);
uniform vec2 camera_focus = vec2(0.0);
uniform float camera_angle = 0.0;
uniform float camera_zoom = 18.0;
uniform float visual_time = 0.0;
uniform vec4 darkness_color : source_color = vec4(0.012, 0.015, 0.020, 1.0);
uniform vec4 wisp_color : source_color = vec4(0.065, 0.072, 0.082, 1.0);
uniform float wisp_scale : hint_range(0.03, 1.0) = 0.28;
uniform float drift_speed : hint_range(0.0, 1.0) = 0.09;
uniform float opacity : hint_range(0.0, 1.0) = 0.96;
uniform float edge_padding : hint_range(0.0, 3.0) = 0.28;
uniform float edge_wisp_strength : hint_range(0.0, 1.0) = 0.85;

float hash_point(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

float noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash_point(cell), hash_point(cell + vec2(1.0, 0.0)), f.x),
		mix(hash_point(cell + vec2(0.0, 1.0)), hash_point(cell + vec2(1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float result = 0.0;
	float weight = 0.57;
	for (int i = 0; i < 3; i++) {
		result += noise(p) * weight;
		p = mat2(vec2(1.7, 1.2), vec2(-1.2, 1.7)) * p + vec2(9.4, 3.1);
		weight *= 0.5;
	}
	return result;
}

void fragment() {
	// Inverse of the view's projection: texture stays anchored while panning/orbiting.
	vec2 screen = (UV * viewport_size - viewport_size * 0.5) / camera_zoom;
	float c = cos(camera_angle);
	float s = sin(camera_angle);
	vec2 world = vec2(c * screen.x + s * screen.y, -s * screen.x + c * screen.y) + camera_focus;
	vec2 field_uv = (world - field_min) / field_size;
	float inside = step(0.0, field_uv.x) * step(0.0, field_uv.y) * step(field_uv.x, 1.0) * step(field_uv.y, 1.0);
	float light = texture(light_field, clamp(field_uv, vec2(0.0), vec2(1.0))).r * inside;
	vec2 flow = vec2(visual_time * drift_speed, -visual_time * drift_speed * 0.53);
	vec2 p = world * wisp_scale;
	// Broad, isotropic density layers: no folded ridges or specular-looking ribbons.
	vec2 curl = vec2(noise(p * 0.6 + flow * 0.6), noise(p * 0.6 + vec2(17.3) - flow * 0.4)) - vec2(0.5);
	float billows = fbm(p + curl * 1.1 + flow);
	float breakup = fbm(p * 2.3 - flow * 0.75 + vec2(23.1, 8.7));
	float smoke = smoothstep(0.22, 0.78, billows * 0.7 + breakup * 0.3);
	// Expand the visual clearing into darkness; never let smoke eat into light.
	vec2 filament_uv = vec2(p.x * 2.4, p.y * 0.85) + curl * 2.2 + flow;
	float filaments = fbm(filament_uv);
	float edge_density = smoothstep(0.26, 0.68, billows * 0.45 + filaments * 0.55);
	float spread = edge_padding * mix(1.45, 0.75, edge_density * edge_wisp_strength);
	vec2 padding_uv = vec2(spread) / field_size;
	float expanded_light = light;
	for (int i = 0; i < 8; i++) {
		float angle = float(i) * 0.78539816339;
		vec2 sample_uv = field_uv + vec2(cos(angle), sin(angle)) * padding_uv;
		float sample_inside = step(0.0, sample_uv.x) * step(0.0, sample_uv.y) * step(sample_uv.x, 1.0) * step(sample_uv.y, 1.0);
		expanded_light = max(expanded_light, texture(light_field, clamp(sample_uv, vec2(0.0), vec2(1.0))).r * sample_inside);
	}
	// The original light is a protected clearing, even for dim one-tile sources.
	// The noisy outer halo is cosmetic: discovery and targeting still use the core.
	float clear = max(smoothstep(0.002, 0.035, light), smoothstep(0.008, 0.055, expanded_light));
	// Do not expose the empty canvas beyond the actual rendered terrain.
	if (use_terrain_field) {
		float coverage = texture(terrain_field, clamp(field_uv, vec2(0.0), vec2(1.0))).a * inside;
		clear *= smoothstep(0.0, 0.5, coverage);
	}
	float veil = (1.0 - clear) * opacity * mix(0.93, 1.0, smoke);
	vec3 color = mix(darkness_color.rgb, wisp_color.rgb, smoke * 0.72);
	COLOR = vec4(color, veil);
}
