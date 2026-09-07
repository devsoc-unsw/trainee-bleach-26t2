shader_type canvas_item;

uniform float selected : hint_range(0.0, 1.0) = 0.0;
uniform float time = 0.0;
uniform vec4 idle : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 gold_lit : source_color = vec4(1.0, 0.92, 0.34, 1.0);
uniform vec4 gold_shade : source_color = vec4(0.72, 0.42, 0.06, 1.0);
uniform float check_size = 7.0;

varying vec2 v_px;

void vertex() {
	v_px = VERTEX;
}

void fragment() {
	vec4 src = texture(TEXTURE, UV);
	float check = mod(
		floor((v_px.x + time * 42.0) / max(check_size, 2.0))
		+ floor((v_px.y + time * 10.0) / max(check_size, 2.0)),
		2.0
	);
	vec3 gold = mix(gold_shade.rgb, gold_lit.rgb, check);
	gold *= 0.86 + 0.16 * sin(time * 5.5 + v_px.x * 0.05);
	float fill = smoothstep(0.22, 0.68, dot(src.rgb, vec3(0.3, 0.56, 0.14)));
	vec3 tinted = mix(src.rgb, gold, fill);
	vec3 col = mix(src.rgb * idle.rgb, tinted, selected);
	COLOR = vec4(col, src.a);
}
