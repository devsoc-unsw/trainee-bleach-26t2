shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform float speed : hint_range(1.0, 16.0) = 7.2;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	COLOR = vec4(0.0);
	for (int i = 0; i < 8; i++) {
		float t = float(i) / 7.0;
		float ang = TIME * speed + t * 6.2831853;
		vec2 dot_p = vec2(cos(ang), sin(ang)) * 0.62;
		float blob = smoothstep(0.24, 0.07, length(p - dot_p));
		COLOR = max(COLOR, vec4(vec3(1.0), blob * mix(0.2, 1.0, t)));
	}
}
