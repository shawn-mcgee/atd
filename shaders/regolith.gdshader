shader_type spatial;
render_mode diffuse_burley, specular_disabled, depth_prepass_alpha;
uniform sampler2D ground_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D visibility_map : filter_linear, repeat_disable;
uniform float map_span = 76.0;
varying vec3 world_position;
void vertex() { world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec4 field = texture(visibility_map, world_position.xz / map_span + vec2(0.5));
	vec3 grain = mix(vec3(0.14), texture(ground_texture, world_position.xz / 5.5).rgb, 0.55);
	vec3 shade = mix(vec3(0.13, 0.17, 0.20), vec3(0.35, 0.40, 0.39), field.g);
	shade = mix(shade, vec3(0.69, 0.64, 0.49), field.b * 0.68);
	shade = mix(shade, vec3(0.25, 0.13, 0.20), field.a * 0.72);
	ALBEDO = grain * shade * 2.2;
	ROUGHNESS = 0.98;
	EMISSION = ALBEDO * 0.045;
	ALPHA = smoothstep(0.06, 0.73, field.r);
}
void light() {
	float mask = LIGHT_IS_DIRECTIONAL ? 1.0 : texture(visibility_map, world_position.xz / map_span + vec2(0.5)).b;
	DIFFUSE_LIGHT += max(dot(NORMAL, LIGHT), 0.0) * ATTENUATION * LIGHT_COLOR * mask / PI;
}
