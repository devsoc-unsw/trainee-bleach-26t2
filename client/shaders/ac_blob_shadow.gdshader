shader_type spatial;
render_mode unshaded, shadows_disabled, depth_draw_never, blend_mix;

uniform vec4 shadow_color : source_color = vec4(0.28, 0.18, 0.14, 0.34);

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float d = length(uv);
	float alpha = (1.0 - smoothstep(0.35, 1.0, d)) * shadow_color.a;
	ALBEDO = shadow_color.rgb;
	ALPHA = alpha;
}
