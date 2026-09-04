shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_toon, specular_disabled, shadows_disabled;

uniform vec4 grass_lit : source_color = vec4(0.27, 0.45, 0.28, 1.0);
uniform vec4 grass_shade : source_color = vec4(0.16, 0.32, 0.2, 1.0);
uniform float check_size : hint_range(0.2, 4.0) = 0.85;

uniform vec3 cup_pos = vec3(0.0);
uniform float cup_radius = 0.0;

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (cup_radius > 0.001) {
		vec2 d = v_world.xz - cup_pos.xz;
		if (dot(d, d) < cup_radius * cup_radius) {
			discard;
		}
	}
	vec2 grid = v_world.xz / max(check_size, 0.2);
	float check = mod(floor(grid.x) + floor(grid.y), 2.0);
	ALBEDO = mix(grass_lit.rgb, grass_shade.rgb, check);
	ROUGHNESS = 0.92;
	METALLIC = 0.0;
	RIM = 0.08;
	RIM_TINT = 0.15;
}

void light() {
	float wrapped = clamp(dot(NORMAL, LIGHT), 0.0, 1.0) * 0.5 + 0.5;
	float band = mix(0.62, 0.88, step(0.5, wrapped));
	DIFFUSE_LIGHT += ATTENUATION * LIGHT_COLOR * band;
}
