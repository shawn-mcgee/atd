shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, shadows_disabled;
uniform vec4 silhouette_color : source_color = vec4(0.55, 0.8, 0.88, 0.6);
void vertex() { VERTEX += NORMAL * 0.018; }
void fragment() { ALBEDO = silhouette_color.rgb; ALPHA = silhouette_color.a; }
