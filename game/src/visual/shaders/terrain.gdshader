shader_type spatial;
// Terrain chunks painted with the generated ground textures (Texture2DArray, 8 layers: grass,
// meadow, forest floor, sand, dirt, rock, farmland, paving). CUSTOM0/CUSTOM1 carry per-vertex
// layer weights; the blend is sharpened by texture brightness for painterly, irregular borders.
// Steep faces sample rock triplanar. COLOR is a brightness tint (tile jitter, high ground).
// Without the layer texture (use_layers = false) COLOR holds the flat tile colours instead.
render_mode diffuse_lambert_wrap, specular_schlick_ggx;

#include "res://src/visual/shaders/world_common.gdshaderinc"

uniform sampler2DArray layers : source_color, filter_linear_mipmap, repeat_enable;
uniform bool use_layers = false;
uniform bool detail_enabled = true;
// Metres covered by one texture repeat.
uniform float tile_m = 9.0;
uniform float rock_tile_m = 5.0;
uniform vec3 water_tint : source_color = vec3(0.10, 0.34, 0.42);

varying vec3 wpos;
varying vec3 wnrm;
varying vec4 w_a;
varying vec4 w_b;

float hash12(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x), mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	w_a = CUSTOM0;
	w_b = CUSTOM1;
}

vec3 sample_layer(int i, vec2 uv) {
	return texture(layers, vec3(uv, float(i))).rgb;
}

vec3 sample_rock(vec3 p, vec3 n) {
	vec3 bw = pow(abs(n), vec3(4.0));
	bw /= (bw.x + bw.y + bw.z);
	vec3 c = vec3(0.0);
	if (bw.x > 0.01) c += sample_layer(5, p.zy / rock_tile_m) * bw.x;
	if (bw.y > 0.01) c += sample_layer(5, p.xz / rock_tile_m) * bw.y;
	if (bw.z > 0.01) c += sample_layer(5, p.xy / rock_tile_m) * bw.z;
	return c;
}

void fragment() {
	vec3 c = COLOR.rgb;
	if (use_layers) {
		float w[8] = float[8](w_a.x, w_a.y, w_a.z, w_a.w, w_b.x, w_b.y, w_b.z, w_b.w);
		vec2 uv = wpos.xz / tile_m;
		vec3 cols[8];
		float score[8];
		float best = 0.0;
		for (int i = 0; i < 8; i++) {
			score[i] = -1.0;
			if (w[i] > 0.003) {
				cols[i] = i == 5 && detail_enabled ? sample_rock(wpos, wnrm) : sample_layer(i, uv);
				score[i] = w[i] + dot(cols[i], vec3(0.3, 0.59, 0.11)) * 0.45;
				best = max(best, score[i]);
			}
		}
		vec3 acc = vec3(0.0);
		float sum = 0.0;
		for (int i = 0; i < 8; i++) {
			float k = max(score[i] - best + 0.22, 0.0);
			if (k > 0.0) {
				acc += cols[i] * k;
				sum += k;
			}
		}
		vec3 painted = acc / max(sum, 1.0e-4);
		if (detail_enabled) {
			float macro = value_noise(wpos.xz * 0.06) * 0.6 + value_noise(wpos.xz * 0.17) * 0.4;
			painted *= 0.9 + macro * 0.2;
		}
		c = painted * COLOR.rgb;
	} else {
		float g = hash12(floor(wpos.xz * 3.0));
		c *= 0.95 + g * 0.08;
	}
	if (wpos.y < 0.02) {
		float d = clamp(-wpos.y / 1.4, 0.0, 1.0);
		c = mix(c, water_tint, 0.25 + d * 0.6);
	}
	float e = fog_explored(wpos);
	ALBEDO = fog_apply(c, e);
	ROUGHNESS = 0.96;
	SPECULAR = 0.08;
}
