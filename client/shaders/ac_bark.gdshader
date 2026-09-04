shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_toon, specular_disabled, shadows_disabled;

uniform vec4 albedo : source_color = vec4(0.86, 0.74, 0.5, 1.0);
uniform vec4 mark : source_color = vec4(0.48, 0.32, 0.18, 1.0);
uniform vec4 shade : source_color = vec4(0.42, 0.3, 0.18, 1.0);
uniform int style : hint_range(0, 1) = 0;

varying vec3 v_local;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	v_local = VERTEX;
}

void fragment() {
	float ang = atan(v_local.z, v_local.x);
	float h = v_local.y;
	float pattern = 0.0;
	if (style < 1) {
		float swirl = sin(ang * 2.2 + h * 11.0) * 0.55 + sin(ang * 5.0 - h * 7.0) * 0.25;
		pattern = smoothstep(0.12, 0.62, swirl * 0.5 + 0.42);
	} else {
		vec2 cell = vec2(floor((ang / 6.283185 + 0.5) * 9.0), floor(h * 7.0 + 3.0));
		vec2 f = fract(vec2((ang / 6.283185 + 0.5) * 9.0, h * 7.0 + 3.0)) - 0.5;
		float d = length(f * vec2(1.0, 1.45));
		pattern = (1.0 - smoothstep(0.12, 0.34, d)) * step(0.42, hash21(cell));
	}
	ALBEDO = mix(albedo.rgb, mark.rgb, pattern * 0.72);
	ROUGHNESS = 0.86;
	METALLIC = 0.0;
	RIM = 0.16;
	RIM_TINT = 0.25;
}

void light() {
	float wrapped = dot(NORMAL, LIGHT) * 0.55 + 0.45;
	float band = mix(0.78, 1.0, smoothstep(0.32, 0.62, wrapped));
	DIFFUSE_LIGHT += ATTENUATION * LIGHT_COLOR * band;
	DIFFUSE_LIGHT += shade.rgb * 0.22;
}
