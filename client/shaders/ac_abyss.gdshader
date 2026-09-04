shader_type spatial;
render_mode unshaded, shadows_disabled, specular_disabled, fog_disabled;

uniform vec4 deep : source_color = vec4(0.008, 0.01, 0.03, 1.0);
uniform vec4 mist : source_color = vec4(0.07, 0.05, 0.12, 1.0);

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float d = length(v_world.xz) * 0.006;
	float rings = 0.5 + 0.5 * sin(length(v_world.xz) * 0.055 + v_world.y * 0.2);
	vec3 col = mix(mist.rgb, deep.rgb, smoothstep(0.05, 1.4, d));
	col *= 0.78 + rings * 0.08;
	ALBEDO = col;
}
