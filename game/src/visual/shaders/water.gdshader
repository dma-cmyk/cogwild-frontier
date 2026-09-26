shader_type spatial;
// Rivers and lakes: translucent, gently rippling water with sun glints, hidden under the mist
// in unexplored areas.
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_schlick_ggx;

#include "res://src/visual/shaders/world_common.gdshaderinc"

uniform vec3 shallow_color : source_color = vec3(0.30, 0.64, 0.72);
uniform vec3 deep_color : source_color = vec3(0.13, 0.40, 0.55);

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float t = TIME;
	vec2 p = wpos.xz;
	float w1 = sin(p.x * 0.9 + t * 1.2) * sin(p.y * 0.7 - t * 1.0);
	float w2 = sin((p.x + p.y) * 1.6 - t * 1.8);
	float w3 = sin(p.x * 2.3 - p.y * 1.9 + t * 2.4);
	vec3 n = normalize(vec3(w1 * 0.16 + w3 * 0.05, 1.0, w2 * 0.12 - w1 * 0.08));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	float e = fog_explored(wpos);
	vec3 col = mix(deep_color, shallow_color, 0.5 + w1 * 0.3);
	float glint = smoothstep(0.9, 1.0, sin(p.x * 3.1 + t * 2.1) * sin(p.y * 2.6 - t * 1.7));
	ALBEDO = fog_apply(col, e);
	EMISSION = vec3(0.9, 0.95, 1.0) * glint * 0.35 * e;
	ALPHA = mix(0.9, 0.62, e);
	ROUGHNESS = 0.12;
	SPECULAR = 0.55;
}
