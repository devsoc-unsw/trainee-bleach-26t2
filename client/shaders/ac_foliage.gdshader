shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_toon, specular_toon, shadows_disabled;

#include "res://shaders/xray_cut.gdshaderinc"

uniform vec4 albedo : source_color = vec4(0.58, 0.82, 0.36, 1.0);
uniform vec4 shade : source_color = vec4(0.18, 0.38, 0.22, 1.0);
uniform float wrap : hint_range(0.0, 1.0) = 0.82;
uniform float toon_soft : hint_range(0.0, 0.6) = 0.28;
uniform float invert_tip : hint_range(0.0, 1.0) = 0.0;

varying float v_tip;
varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float up = clamp(normalize(VERTEX).y * 0.5 + 0.55, 0.0, 1.0);
	float down = clamp(-VERTEX.y, 0.0, 1.0);
	v_tip = mix(up, down, invert_tip);
}

void fragment() {
	xray_try_discard(v_world, 0.0);
	vec3 tint = albedo.rgb * COLOR.rgb;
	float blot = sin(v_world.x * 2.15) * sin(v_world.z * 1.85) * sin(v_world.y * 2.4);
	vec3 mottled = mix(tint * 0.9, tint * 1.06, blot * 0.5 + 0.5);
	ALBEDO = mix(mottled, tint * 1.04, v_tip * 0.35);
	ROUGHNESS = 0.78;
	METALLIC = 0.0;
	SPECULAR = 0.12;
	RIM = 0.22;
	RIM_TINT = 0.35;
}

void light() {
	float wrapped = dot(NORMAL, LIGHT) * wrap + (1.0 - wrap);
	float lo = 0.4 - toon_soft;
	float hi = 0.4 + toon_soft;
	float band = mix(0.78, 1.0, smoothstep(lo, hi, wrapped));
	DIFFUSE_LIGHT += ATTENUATION * LIGHT_COLOR * band;
	DIFFUSE_LIGHT += shade.rgb * 0.22;
	vec3 half_dir = normalize(LIGHT + VIEW);
	float spec = pow(max(dot(NORMAL, half_dir), 0.0), 42.0) * 0.05;
	SPECULAR_LIGHT += ATTENUATION * LIGHT_COLOR * spec;
}
