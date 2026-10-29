shader_type spatial;
render_mode unshaded, fog_disabled, depth_draw_never, depth_test_disabled, shadows_disabled;
uniform sampler2D occluder_depth : repeat_disable, filter_nearest;
uniform float camera_far = 200.0;
uniform vec4 highlight_color : source_color = vec4(0.35, 1.0, 0.8, 0.65);
void fragment() {
	vec3 encoded = texture(occluder_depth, SCREEN_UV).rgb * 255.0;
	if (max(encoded.r, max(encoded.g, encoded.b)) < 20.0) { discard; }
	ivec3 channels = ivec3(round((encoded - vec3(32.0)) / 14.0));
	int code = (channels.r << 8) + (channels.g << 4) + channels.b;
	float visible_depth = float(code - 1) / 4094.0 * camera_far;
	if (-VERTEX.z <= visible_depth + 0.15) { discard; }
	float rim = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 2.0);
	ALBEDO = highlight_color.rgb;
	ALPHA = highlight_color.a * (0.35 + 0.65 * rim);
}
