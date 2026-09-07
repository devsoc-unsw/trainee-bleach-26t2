shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque, shadows_disabled;

uniform vec4 outline_color : source_color = vec4(0.42, 0.27, 0.22, 1.0);

void fragment() {
	ALBEDO = outline_color.rgb;
}
