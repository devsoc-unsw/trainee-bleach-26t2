shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_toon, specular_disabled, shadows_disabled;

#include "res://shaders/xray_cut.gdshaderinc"

uniform vec4 albedo : source_color = vec4(0.96, 0.9, 0.78, 1.0);
uniform vec4 shade : source_color = vec4(0.78, 0.62, 0.48, 1.0);
uniform float toon_cutoff : hint_range(0.0, 1.0) = 0.48;
uniform int pattern = 0;
uniform float pattern_scale = 1.0;
uniform vec4 pattern_color : source_color = vec4(0.32, 0.52, 0.62, 1.0);
uniform float xray_cut = 0.0;

varying vec3 v_world;
varying vec3 v_world_n;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_n = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}

void fragment() {
	if (xray_cut > 0.5) {
		xray_try_discard(v_world, abs(normalize(v_world_n).y));
	}
	vec3 col = albedo.rgb;
	if (pattern == 1) {
		vec3 wn = abs(normalize(v_world_n));
		float scale = max(pattern_scale, 0.05);
		vec2 cell;
		if (wn.y >= wn.x && wn.y >= wn.z) {
			cell = v_world.xz / scale;
		} else if (wn.x >= wn.z) {
			cell = v_world.zy / scale;
		} else {
			cell = v_world.xy / scale;
		}
		vec2 f = fract(cell);
		float grout = 1.0 - step(0.08, f.x) * step(0.08, f.y);
		float shift = fract((floor(cell.x) + floor(cell.y)) * 0.13);
		col = mix(col * (0.9 + shift * 0.06), col * 0.58, grout);
	} else if (pattern == 2) {
		vec3 wn = abs(normalize(v_world_n));
		float horiz = wn.x >= wn.z ? v_world.z : v_world.x;
		float row = floor(v_world.y / max(pattern_scale * 0.42, 0.12));
		vec2 cell = vec2(horiz + row * 0.38, v_world.y) / vec2(max(pattern_scale, 0.2), max(pattern_scale * 0.42, 0.12));
		vec2 f = fract(cell);
		float mortar = 1.0 - step(0.1, f.x) * step(0.16, f.y);
		col = mix(col, col * 0.68, mortar);
	} else if (pattern == 3 && abs(normalize(v_world_n).y) < 0.62) {
		vec3 wn = normalize(v_world_n);
		float horiz = abs(wn.x) > abs(wn.z) ? v_world.z : v_world.x;
		vec2 cell = vec2(horiz, v_world.y) / vec2(max(pattern_scale, 0.4), max(pattern_scale * 1.05, 0.5));
		vec2 f = fract(cell);
		float win = step(0.16, f.x) * step(f.x, 0.84) * step(0.2, f.y) * step(f.y, 0.78);
		float storey = step(0.12, fract(v_world.y / 3.35));
		col = mix(col, pattern_color.rgb, win * storey * 0.88);
	} else if (pattern == 4) {
		float blot = sin(v_world.x * 2.3) * sin(v_world.z * 1.9) * sin(v_world.y * 2.8);
		col = mix(col * 0.86, col * 1.08, blot * 0.5 + 0.5);
	} else if (pattern == 5) {
		float slat = step(0.4, fract(v_world.y / max(pattern_scale, 0.07)));
		col = mix(col * 0.28, col, slat);
	}
	ALBEDO = col;
	ROUGHNESS = pattern == 3 ? 0.42 : 0.92;
	METALLIC = 0.0;
	SPECULAR = 0.0;
	float facing_up = abs(normalize(v_world_n).y);
	RIM = mix(0.1, 0.0, smoothstep(0.55, 0.85, facing_up));
	RIM_TINT = 0.35;
}

void light() {
	float wrapped = clamp(dot(NORMAL, LIGHT), 0.0, 1.0) * 0.5 + 0.5;
	float band = mix(0.52, 0.82, smoothstep(toon_cutoff - 0.08, toon_cutoff + 0.12, wrapped));
	DIFFUSE_LIGHT += ATTENUATION * LIGHT_COLOR * band;
}
