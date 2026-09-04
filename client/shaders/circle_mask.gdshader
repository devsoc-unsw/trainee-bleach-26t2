shader_type canvas_item;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	if (r > 1.0) {
		discard;
	}
	COLOR.a *= smoothstep(1.0, 0.86, r);
}
