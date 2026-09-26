// Painted sprites (characters, machines, trees, rocks, buildings) drawn as camera-facing cards.
// The card is anchored at the node origin (feet, trunk base or footprint centre) and faces the
// camera of the current pass: in the colour pass it faces the player's camera (constant depth, so
// sprites sort like classic isometric art), in the shadow pass it faces the sun and casts the
// sprite's silhouette. Card size in metres = node scale (x = width, y = height).
// Needs `render_mode skip_vertex_transform` in the including shader.
#include "res://src/visual/shaders/world_common.gdshaderinc"

// Flat cards have no useful normal: every light uses a constant pseudo N.L instead.
uniform float light_wrap = 0.62;
// 1 = the sun's shadow map darkens the card (standing in a building's shadow).
uniform float receive_shadow = 1.0;

// World position on a card: `local` metres right/up from the anchor, `toward` metres toward the
// pass camera.
vec3 card_world(mat4 model, mat4 inv_view, vec2 local, float toward) {
	return model[3].xyz + inv_view[0].xyz * local.x + inv_view[1].xyz * local.y + inv_view[2].xyz * toward;
}

vec2 card_size(mat4 model) {
	return vec2(length(model[0].xyz), length(model[1].xyz));
}

// Alpha rescaled by mip level so thin shapes (needles, hair) do not erode when zoomed out.
float coverage(float a, float lod) {
	return clamp(a * (1.0 + max(lod, 0.0) * 0.28), 0.0, 1.0);
}

vec3 rgb_to_hsv(vec3 c) {
	vec4 k = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, k.wz), vec4(c.gb, k.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + 1.0e-10)), d / (q.x + 1.0e-10), q.x);
}

vec3 hsv_to_rgb(vec3 c) {
	vec3 p = abs(fract(c.xxx + vec3(1.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
	return c.z * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
}

// Company colour: the painted art uses blue for company cloth and banners; rotate only strongly
// blue pixels by `shift` turns (0 keeps the painted blue).
vec3 shift_company_blue(vec3 col, float shift) {
	if (abs(shift) < 0.001) {
		return col;
	}
	vec3 hsv = rgb_to_hsv(col);
	float w = smoothstep(0.52, 0.56, hsv.x) * (1.0 - smoothstep(0.70, 0.74, hsv.x)) * smoothstep(0.2, 0.38, hsv.y);
	hsv.x = fract(hsv.x + shift * w);
	return mix(col, hsv_to_rgb(hsv), step(0.001, w));
}

void light() {
	float a = ATTENUATION;
	if (LIGHT_IS_DIRECTIONAL) {
		a = mix(1.0, ATTENUATION, receive_shadow);
	}
	DIFFUSE_LIGHT += LIGHT_COLOR * a * (light_wrap / PI);
}
