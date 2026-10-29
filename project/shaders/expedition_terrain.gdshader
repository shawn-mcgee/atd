shader_type spatial;
render_mode unshaded;
uniform int light_count = 0;
uniform vec4 light_data[64];
uniform vec4 light_directions[64];
uniform vec4 tint : source_color = vec4(0.13, 0.21, 0.24, 1.0);
varying vec2 ground;
varying float surface_shade;
void vertex() {
	ground = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
	vec3 world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	surface_shade = 0.58 + 0.42 * max(world_normal.y, 0.0);
}
void fragment() {
	float light = 0.0;
	for (int i = 0; i < 64; i++) {
		if (i >= light_count) { break; }
		vec2 offset = ground - light_data[i].xy;
		float distance = length(offset);
		float radius = light_data[i].z;
		if (distance >= radius) { continue; }
		float strength = 1.0 - smoothstep(radius * 0.55, radius, distance);
		if (light_data[i].w > -0.5 && distance > 0.01) {
			float alignment = dot(offset / distance, light_directions[i].xy);
			strength *= smoothstep(light_data[i].w, light_data[i].w + 0.12, alignment);
		}
		light += strength * light_directions[i].z;
	}
	light = min(light, 1.0);
	float grain = 0.94 + 0.06 * sin(ground.x * 2.7 + cos(ground.y * 1.9));
	ALBEDO = tint.rgb * light * grain * surface_shade;
}
