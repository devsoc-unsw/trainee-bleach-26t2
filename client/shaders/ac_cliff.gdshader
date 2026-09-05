shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, unshaded, shadows_disabled, specular_disabled, fog_disabled;

#include "res://shaders/xray_cut.gdshaderinc"

uniform vec4 dirt : source_color = vec4(0.42, 0.3, 0.18, 1.0);
uniform vec4 rock : source_color = vec4(0.55, 0.42, 0.28, 1.0);
uniform vec4 moss : source_color = vec4(0.28, 0.34, 0.18, 1.0);
uniform vec4 abyss : source_color = vec4(0.0, 0.0, 0.0, 1.0);

varying vec3 v_world;
varying vec2 v_uv;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	v += a * noise(p); p *= 2.07; a *= 0.5;
	v += a * noise(p); p *= 2.03; a *= 0.5;
	v += a * noise(p); p *= 2.11; a *= 0.5;
	v += a * noise(p);
	return v;
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_uv = UV;
}

void fragment() {
	xray_try_discard(v_world, 0.0);
	vec2 along = vec2(v_world.x * 0.55 + v_world.z * 0.48, v_world.y * 0.62);
	float grain = fbm(along * 1.35);
	float grit = fbm(along * 4.8 + 17.0);
	float pebbles = step(0.78, noise(along * 7.3));
	float strata = 0.5 + 0.5 * sin(v_world.y * 2.4 + grain * 3.5);
	float recess = smoothstep(0.28, 0.72, grain);
	vec3 col = mix(dirt.rgb, rock.rgb, clamp(strata * 0.55 + grit * 0.35, 0.0, 1.0));
	col = mix(col, moss.rgb, (1.0 - recess) * 0.28);
	col *= 0.72 + grit * 0.38;
	col = mix(col, col * 0.55, pebbles * 0.45);
	float t = clamp(v_uv.y, 0.0, 1.0);
	t = smoothstep(0.06, 0.94, t);
	t = t * t * (3.0 - 2.0 * t);
	ALBEDO = mix(col, abyss.rgb, t);
}
