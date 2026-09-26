shader_type spatial;
// Terrain chunks: vertex colours (linear) with a subtle painterly grain, underwater tint and the
// fog-of-war mist. Flat-shaded geometry gives the low-poly facets.
render_mode diffuse_lambert_wrap, specular_schlick_ggx;

#include "res://src/visual/shaders/world_common.gdshaderinc"

uniform vec3 water_tint : source_color = vec3(0.10, 0.34, 0.42);

varying vec3 wpos;

float hash12(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 c = COLOR.rgb;
	float g = hash12(floor(wpos.xz * 3.0));
	c *= 0.95 + g * 0.08;
	if (wpos.y < 0.02) {
		float d = clamp(-wpos.y / 1.4, 0.0, 1.0);
		c = mix(c, water_tint, 0.25 + d * 0.6);
	}
	float e = fog_explored(wpos);
	ALBEDO = fog_apply(c, e);
	ROUGHNESS = 0.96;
	SPECULAR = 0.08;
}
