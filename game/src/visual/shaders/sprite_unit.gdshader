shader_type spatial;
// Character / machine chip sheets: grid of frames (columns = animation frames, rows = facing).
// One material per sheet; everything per unit is an instance uniform, so all units using the
// same sheet share one material.
render_mode skip_vertex_transform, cull_disabled;

#include "res://src/visual/shaders/sprite_common.gdshaderinc"

uniform sampler2D sheet : source_color, filter_linear_mipmap, repeat_disable;
uniform vec2 grid = vec2(3.0, 4.0);
// Anchor (feet or hover centre) inside one cell, 0..1 with y from the top.
uniform vec2 anchor = vec2(0.5, 0.97);
uniform float depth_bias = 0.45;
// Portrait / preview viewports render outside the map.
uniform bool no_fog = false;

instance uniform vec2 frame = vec2(1.0, 0.0);
instance uniform vec4 flash = vec4(1.0, 1.0, 1.0, 0.0);
instance uniform float roll = 0.0;
instance uniform float hue_shift = 0.0;
instance uniform vec2 offset = vec2(0.0, 0.0);

varying vec2 cell_uv;
varying vec3 base_pos;

void vertex() {
	vec2 local = vec2(UV.x - anchor.x, anchor.y - UV.y) * card_size(MODEL_MATRIX);
	float c = cos(roll);
	float s = sin(roll);
	local = vec2(c * local.x - s * local.y, s * local.x + c * local.y) + offset;
	vec3 world = card_world(MODEL_MATRIX, INV_VIEW_MATRIX, local, depth_bias);
	base_pos = MODEL_MATRIX[3].xyz;
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	NORMAL = vec3(0.0, 0.0, 1.0);
	cell_uv = (frame + UV) / grid;
}

void fragment() {
	vec4 tex = texture(sheet, cell_uv);
	float lod = textureQueryLod(sheet, cell_uv).x;
	vec3 col = shift_company_blue(tex.rgb, hue_shift);
	col = mix(col, flash.rgb, flash.a);
	float explored = no_fog ? 1.0 : fog_explored(base_pos);
	ALBEDO = fog_apply(col, explored);
	ALPHA = coverage(tex.a, lod);
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	EMISSION = flash.rgb * flash.a * 0.6;
}
