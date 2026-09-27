shader_type spatial;
// Screen-facing health/energy bar drawn on top of the world. Per-instance ratio and colour.
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, fog_disabled, shadows_disabled;

uniform float ratio = 1.0;
uniform vec4 fill_color : source_color = vec4(0.35, 0.85, 0.35, 1.0);
uniform float ratio2 = -1.0;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

void fragment() {
	vec2 uv = UV;
	bool border = uv.x < 0.035 || uv.x > 0.965 || uv.y < 0.14 || uv.y > 0.86;
	vec3 col = vec3(0.10, 0.10, 0.13);
	if (ratio2 >= 0.0 && uv.y > 0.62) {
		if (uv.x < ratio2) {
			col = vec3(0.30, 0.62, 1.0);
		}
	} else if (uv.x < ratio) {
		col = fill_color.rgb;
	}
	if (border) {
		col = vec3(0.03, 0.03, 0.05);
	}
	ALBEDO = col;
}
