shader_type spatial;
// The sea (and the lake): clear and turquoise over sand, deep blue further
// out, with surf where it meets the shore.
render_mode blend_mix, depth_draw_opaque, cull_back, specular_schlick_ggx;

uniform vec3 shallow : source_color = vec3(0.32, 0.78, 0.76);
uniform vec3 deep : source_color = vec3(0.06, 0.29, 0.47);
uniform vec3 foam_color : source_color = vec3(0.97, 0.98, 1.0);
uniform float depth_scale = 2.2;
uniform float foam_width = 0.45;
uniform float wave_height = 0.05;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear_mipmap;

varying vec3 world_pos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float waves(vec2 p, float t) {
	return sin(p.x * 0.55 + t * 0.8) * 0.5 + sin(p.y * 0.7 - t * 0.65) * 0.35 + sin((p.x + p.y) * 1.3 + t * 1.4) * 0.15;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += waves(world_pos.xz, TIME) * wave_height;
}

void fragment() {
	float depth = texture(depth_tex, SCREEN_UV).r;
	vec4 behind = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	behind.xyz /= behind.w;
	// How much water lies between the surface and whatever is under it.
	float thick = max(VERTEX.z - behind.z, 0.0);
	float t = clamp(thick / depth_scale, 0.0, 1.0);
	vec3 col = mix(shallow, deep, smoothstep(0.0, 1.0, t));

	vec2 p = world_pos.xz;
	float n = vnoise(p * 2.2 + vec2(TIME * 0.15, -TIME * 0.1)) * 0.6 + vnoise(p * 5.0 - TIME * 0.2) * 0.4;
	// Surf: a band at the shore, with ripples that roll in.
	float edge = 1.0 - smoothstep(0.0, foam_width, thick + (n - 0.5) * 0.12);
	float roll = smoothstep(0.55, 0.75, sin(thick * 18.0 - TIME * 2.2 + n * 3.0) * 0.5 + 0.5) * (1.0 - smoothstep(0.0, foam_width * 2.6, thick));
	float foam = clamp(edge + roll * 0.7, 0.0, 1.0);
	foam *= step(0.32, n + edge * 0.5);
	ALBEDO = mix(col, foam_color, foam);
	ALPHA = clamp(mix(0.55, 0.96, t) + foam, 0.0, 1.0);
	ROUGHNESS = mix(0.06, 0.6, foam);
	SPECULAR = 0.5;
	float dx = waves(p + vec2(0.1, 0.0), TIME) - waves(p, TIME);
	float dz = waves(p + vec2(0.0, 0.1), TIME) - waves(p, TIME);
	vec3 wn = normalize(vec3(-dx * 0.6, 1.0, -dz * 0.6) + vec3(n - 0.5, 0.0, vnoise(p * 4.0 + TIME * 0.3) - 0.5) * 0.04);
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
}
