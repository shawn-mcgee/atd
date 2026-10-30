shader_type canvas_item;
render_mode unshaded;
varying vec4 field_color;
void vertex() { field_color = COLOR; }
void fragment() { COLOR = vec4(field_color.rgb, 1.0); }
