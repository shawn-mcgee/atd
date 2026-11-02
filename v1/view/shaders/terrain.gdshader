shader_type canvas_item;
render_mode unshaded;
uniform sampler2D light_field : filter_linear, repeat_disable;
uniform vec2 field_min;
uniform vec2 field_size;
uniform bool cliff = false;
varying vec2 world_position;
void vertex() { world_position = VERTEX + INSTANCE_CUSTOM.xy; }
void fragment() {
	vec2 field_uv = (world_position - field_min) / field_size;
	float light = texture(light_field, clamp(field_uv, vec2(0.0), vec2(1.0))).r;
	float brightness = cliff ? 0.3 + light * 0.7 : 0.15 + light * 0.5;
	vec3 tint = cliff ? vec3(brightness) : vec3(brightness * 0.9, brightness, brightness * 1.05);
	COLOR = texture(TEXTURE, UV) * vec4(tint, 1.0);
}
