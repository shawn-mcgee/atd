shader_type canvas_item;
render_mode unshaded;

uniform sampler2D silhouette : filter_linear, repeat_disable;
uniform vec2 pixel_size = vec2(0.00078125, 0.00125);
uniform float width_pixels : hint_range(1.0, 5.0) = 1.7;
uniform vec4 outline_color : source_color = vec4(0.482, 0.957, 0.816, 1.0);

void fragment() {
	vec2 step_uv = pixel_size * width_pixels;
	float center = texture(silhouette, UV).a;
	float around = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			around = max(around, texture(silhouette, UV + vec2(float(x), float(y)) * step_uv).a);
		}
	}
	// Exterior of the combined body/head/connection mask only; no internal seams.
	COLOR = vec4(outline_color.rgb, max(0.0, around - center) * outline_color.a);
}
