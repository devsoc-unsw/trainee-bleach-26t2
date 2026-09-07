shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_toon, specular_toon, shadows_disabled;

uniform vec4 color_lit : source_color = vec4(1.0, 0.97, 0.9, 1.0);
uniform vec4 color_shade : source_color = vec4(0.86, 0.72, 0.62, 1.0);
uniform vec4 dimple_color : source_color = vec4(0.93, 0.84, 0.74, 1.0);
uniform vec4 stripe_color : source_color = vec4(0.93, 0.38, 0.34, 1.0);
uniform vec4 spec_color : source_color = vec4(1.0, 0.98, 0.94, 1.0);
uniform float toon_cutoff : hint_range(0.0, 1.0) = 0.52;
uniform float wrap : hint_range(0.0, 1.0) = 0.55;
uniform float dimple_amount : hint_range(0.0, 1.0) = 0.55;
uniform float stripe_width : hint_range(0.0, 0.4) = 0.07;

varying vec3 v_model;

void vertex() {
	v_model = VERTEX;
}

float dimple_mask(vec3 p) {
	vec3 n = normalize(p);
	float u = atan(n.z, n.x) / TAU + 0.5;
	float v = n.y * 0.5 + 0.5;
	vec2 grid = vec2(u * 18.0, v * 11.0);
	if (mod(floor(grid.y), 2.0) > 0.5) {
		grid.x += 0.5;
	}
	vec2 cell = fract(grid) - 0.5;
	float polar = smoothstep(0.12, 0.32, abs(n.y));
	return smoothstep(0.28, 0.12, length(cell)) * polar;
}

void fragment() {
	vec3 p = v_model;
	float dimple = dimple_mask(p) * dimple_amount;

	vec3 base = mix(color_lit.rgb, dimple_color.rgb, dimple);

	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.6);
	base = mix(base, spec_color.rgb, fresnel * 0.18);

	ALBEDO = base;
	ROUGHNESS = 0.42;
	METALLIC = 0.0;
	RIM = 0.35;
	RIM_TINT = 0.4;
}

void light() {
	float ndotl = dot(NORMAL, LIGHT);
	float wrapped = ndotl * (1.0 - wrap) + wrap;
	float band = mix(0.62, 1.0, step(toon_cutoff, wrapped));
	DIFFUSE_LIGHT += ATTENUATION * LIGHT_COLOR * band + color_lit.rgb * 0.2;

	vec3 half_v = normalize(VIEW + LIGHT);
	float spec = pow(max(dot(NORMAL, half_v), 0.0), 48.0);
	spec = smoothstep(0.35, 0.55, spec);
	SPECULAR_LIGHT += spec * spec_color.rgb * ATTENUATION * 0.65;
}
