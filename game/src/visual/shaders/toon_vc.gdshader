shader_type spatial;
// Shared material for every procedural mesh (MeshKit). Vertex colour = albedo (already linear).
// Vertex alpha < 1 marks emissive parts: emission = colour * (1 - alpha) * glow_strength,
// boosted at night (windows, lamps, robot eyes). Soft wrap lighting keeps shadows cozy.
render_mode diffuse_lambert_wrap, specular_schlick_ggx;

#include "res://src/visual/shaders/world_common.gdshaderinc"

uniform float glow_strength = 2.0;
uniform float night_glow_boost = 1.5;
// MultiMesh instances can pass a tint through INSTANCE_CUSTOM (rgb multiplier, a = 1 when used).
uniform bool use_instance_tint = false;
// Portraits and previews render outside the map: ignore the fog of war there.
uniform bool no_fog = false;

varying vec3 world_pos;
varying vec3 tint;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	tint = vec3(1.0);
	if (use_instance_tint && INSTANCE_CUSTOM.a > 0.5) {
		tint = INSTANCE_CUSTOM.rgb;
	}
}

void fragment() {
	vec3 base = COLOR.rgb * tint;
	float glow = clamp(1.0 - COLOR.a, 0.0, 1.0);
	float explored = no_fog ? 1.0 : fog_explored(world_pos);
	ALBEDO = fog_apply(base, explored);
	ROUGHNESS = 0.88;
	SPECULAR = 0.2;
	EMISSION = base * glow * glow_strength * (1.0 + night_amount * night_glow_boost) * explored;
}
