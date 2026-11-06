shader_type canvas_item;
render_mode unshaded;
void fragment() {
	COLOR = vec4(vec3(1.0), texture(TEXTURE, UV).a);
}
