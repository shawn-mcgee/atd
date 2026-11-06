shader_type canvas_item;
render_mode unshaded;

void fragment() {
	float alpha = texture(TEXTURE, UV).a * COLOR.a;
	COLOR = vec4(vec3(1.0), smoothstep(0.15, 0.35, alpha));
}
