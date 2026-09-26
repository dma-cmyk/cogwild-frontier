shader_type spatial;
// Trees, rocks, ore, bushes and other world props from one atlas, drawn with MultiMesh.
// Per instance: transform (position, scale = card size in metres), COLOR = tint,
// INSTANCE_CUSTOM = atlas rect (u, v, w, h) in UV units with the base centred at the bottom.
render_mode skip_vertex_transform, cull_disabled;

#include "res://src/visual/shaders/sprite_common.gdshaderinc"

uniform sampler2D atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform float depth_bias = 0.35;
// Wind sway amplitude in metres at the top of the card (0 for rocks).
uniform float sway = 0.0;

varying vec2 atlas_uv;
varying vec3 base_pos;
varying vec3 tint;

void vertex() {
	vec2 size = card_size(MODEL_MATRIX);
	vec2 local = vec2(UV.x - 0.5, 1.0 - UV.y) * size;
	base_pos = MODEL_MATRIX[3].xyz;
	if (sway > 0.0) {
		float h = 1.0 - UV.y;
		float phase = base_pos.x * 0.37 + base_pos.z * 0.61;
		local.x += sway * h * h * (sin(TIME * 1.3 + phase) * 0.7 + sin(TIME * 2.9 + phase * 1.7) * 0.3);
	}
	vec3 world = card_world(MODEL_MATRIX, INV_VIEW_MATRIX, local, depth_bias);
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	NORMAL = vec3(0.0, 0.0, 1.0);
	atlas_uv = INSTANCE_CUSTOM.xy + UV * INSTANCE_CUSTOM.zw;
	tint = COLOR.rgb;
}

void fragment() {
	vec4 tex = texture(atlas, atlas_uv);
	float lod = textureQueryLod(atlas, atlas_uv).x;
	ALBEDO = fog_apply(tex.rgb * tint, fog_explored(base_pos));
	ALPHA = coverage(tex.a, lod);
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
