shader_type spatial;
// Painted isometric building on a camera-facing card. Each pixel gets the depth it would have if
// it lay on the building's two front walls (the footprint box edges nearest to the camera), so
// units walking in front of, beside or behind the building are occluded like with real geometry
// and the terrain inside the footprint never cuts into the picture. Works for any camera yaw and
// in the sun's shadow pass (the card then faces the sun and casts the building's silhouette).
render_mode skip_vertex_transform, cull_disabled;

#include "res://src/visual/shaders/sprite_common.gdshaderinc"

uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D glow_tex : hint_default_black, filter_linear_mipmap, repeat_disable;
// Footprint centre in the picture, 0..1 (y from the top).
uniform vec2 anchor = vec2(0.5, 0.8);
// Footprint half extents in metres along the node's local X and Z.
uniform vec2 half_size = vec2(1.5, 1.5);
uniform float glow_strength = 2.4;
// Extra metres toward the camera (the scaffold card sits in front of the picture).
uniform float depth_toward = 0.05;
uniform bool no_fog = false;

// 0..1 part of the picture shown, from the bottom (construction progress).
uniform float reveal = 1.0;
uniform float hue_shift = 0.0;
uniform vec4 flash = vec4(1.0, 1.0, 1.0, 0.0);

varying vec2 card;
varying vec3 base_pos;

void vertex() {
	vec2 local = vec2(UV.x - anchor.x, anchor.y - UV.y) * card_size(MODEL_MATRIX);
	card = local;
	base_pos = MODEL_MATRIX[3].xyz;
	VERTEX = (VIEW_MATRIX * vec4(card_world(MODEL_MATRIX, INV_VIEW_MATRIX, local, 0.0), 1.0)).xyz;
	NORMAL = vec3(0.0, 0.0, 1.0);
}

// Forward distance (away from the camera, metres, relative to the footprint centre) of the
// footprint's near boundary at screen-right offset x.
float front_edge(float x, vec3 rh, vec3 fh, vec3 ax, vec3 az) {
	float s1 = half_size.x * dot(ax, rh);
	float s2 = half_size.y * dot(az, rh);
	float f1 = half_size.x * dot(ax, fh);
	float f2 = half_size.y * dot(az, fh);
	float s_front = -sign(f1) * s1 - sign(f2) * s2;
	float f_front = -abs(f1) - abs(f2);
	float s_left = -abs(s1) - abs(s2);
	float f_left = -sign(s1) * f1 - sign(s2) * f2;
	float s_right = abs(s1) + abs(s2);
	float f_right = sign(s1) * f1 + sign(s2) * f2;
	if (x <= s_front) {
		float t = clamp((x - s_left) / max(s_front - s_left, 1.0e-3), 0.0, 1.0);
		return mix(f_left, f_front, t);
	}
	float t = clamp((x - s_front) / max(s_right - s_front, 1.0e-3), 0.0, 1.0);
	return mix(f_front, f_right, t);
}

void fragment() {
	if (UV.y < 1.0 - reveal) {
		discard;
	}
	vec4 c = texture(tex, UV);
	float lod = manual_lod(UV, vec2(textureSize(tex, 0)));
	vec3 col = shift_company_blue(c.rgb, hue_shift);
	col = mix(col, flash.rgb, flash.a);
	float explored = no_fog ? 1.0 : fog_explored(base_pos);
	ALBEDO = fog_apply(col, explored);
	ALPHA = coverage(c.a, lod);
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	float night = no_fog ? 0.0 : night_amount;
	EMISSION = col * texture(glow_tex, UV).r * glow_strength * (0.2 + 1.8 * night) * explored;

	// per-pixel depth on the front walls
	vec3 r = INV_VIEW_MATRIX[0].xyz;
	vec3 b = INV_VIEW_MATRIX[2].xyz;
	vec3 rh = normalize(vec3(r.x, 0.0, r.z));
	vec3 fh = normalize(vec3(-b.x, 0.0, -b.z) + vec3(1.0e-5, 0.0, 0.0));
	float sin_p = clamp(b.y, 0.05, 1.0);
	float cos_p = max(INV_VIEW_MATRIX[1].y, 0.05);
	vec3 ax = normalize(vec3(MODEL_MATRIX[0].x, 0.0, MODEL_MATRIX[0].z));
	vec3 az = normalize(vec3(MODEL_MATRIX[2].x, 0.0, MODEL_MATRIX[2].z));
	float f = front_edge(card.x, rh, fh, ax, az);
	float h = (card.y - f * sin_p) / cos_p;
	float toward = h >= 0.0 ? (-f * cos_p + h * sin_p) : (-card.y * cos_p / sin_p);
	vec3 anchor_view = (VIEW_MATRIX * vec4(base_pos, 1.0)).xyz;
	vec4 clip = PROJECTION_MATRIX * vec4(anchor_view + vec3(card.x, card.y, toward + depth_toward), 1.0);
	// Forward+/Mobile use reverse Z in 0..1; Compatibility (OpenGL / WebGL2) maps NDC -1..1.
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	DEPTH = clip.z / clip.w * 0.5 + 0.5;
#else
	DEPTH = clip.z / clip.w;
#endif
}
