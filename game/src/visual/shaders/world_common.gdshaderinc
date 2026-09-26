// Shared world shader helpers: fog of war and day/night globals.
// Globals are declared in project.godot [shader_globals] and driven by the game at runtime:
//   fog_tex      R8 texture, 1 texel per world tile, 1.0 = explored
//   fog_rect     xy = world (x, z) of texel (0, 0), zw = world size covered by the texture
//   fog_enabled  0 = everything explored (galleries, tools), 1 = use fog_tex
//   night_amount 0 = day .. 1 = deep night (window / lamp glow boost)
global uniform sampler2D fog_tex : filter_linear;
global uniform vec4 fog_rect;
global uniform float fog_enabled;
global uniform float night_amount;

const vec3 FOG_MIST = vec3(0.36, 0.41, 0.50);

float fog_explored(vec3 wp) {
	if (fog_enabled < 0.5) {
		return 1.0;
	}
	vec2 uv = (wp.xz - fog_rect.xy) / fog_rect.zw;
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
		return 0.0;
	}
	return texture(fog_tex, uv).r;
}

// Unexplored areas fade into a soft, desaturated mist (the "unknown frontier").
vec3 fog_apply(vec3 albedo, float explored) {
	float lum = dot(albedo, vec3(0.299, 0.587, 0.114));
	vec3 mist = mix(vec3(lum) * 0.8, FOG_MIST, 0.82);
	return mix(mist, albedo, smoothstep(0.05, 0.95, explored));
}
