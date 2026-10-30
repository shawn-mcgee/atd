shader_type canvas_item;
render_mode unshaded, blend_add;
varying vec4 source_data;

void vertex() {
	source_data = COLOR;
}

void fragment() {
	vec2 offset = (UV - vec2(0.5)) * 2.0;
	float distance_from_center = length(offset);
	float strength = 1.0 - smoothstep(0.55, 1.0, distance_from_center);
	float cone = source_data.b * 2.0 - 1.0;
	if (cone > -0.5 && distance_from_center > 0.0001) {
		vec2 direction = source_data.rg * 2.0 - vec2(1.0);
		float alignment = dot(offset / distance_from_center, direction);
		strength *= smoothstep(cone, cone + 0.12, alignment);
	}
	// Parameters arrive as vertex colors, avoiding a fixed-size light uniform array.
	float value = strength * source_data.a * 4.0;
	COLOR = vec4(value, value, value, 1.0);
}
