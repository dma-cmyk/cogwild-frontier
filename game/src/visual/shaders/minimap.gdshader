shader_type canvas_item;
// Minimap: terrain colours for the shown window of the world, darkened where unexplored.

global uniform sampler2D fog_tex : filter_linear;
global uniform vec4 fog_rect;
uniform sampler2D terrain_tex : filter_nearest;
uniform vec4 view_rect;  // world x, z of the top-left corner, width, height shown

void fragment() {
	vec2 wp = view_rect.xy + UV * view_rect.zw;
	vec2 uv = (wp - fog_rect.xy) / fog_rect.zw;
	float e = 0.0;
	vec3 c = vec3(0.1);
	if (uv.x >= 0.0 && uv.y >= 0.0 && uv.x <= 1.0 && uv.y <= 1.0) {
		e = texture(fog_tex, uv).r;
		c = texture(terrain_tex, uv).rgb;
	}
	vec3 mist = vec3(0.11, 0.14, 0.19);
	COLOR = vec4(mix(mist, c, e), 1.0);
}
