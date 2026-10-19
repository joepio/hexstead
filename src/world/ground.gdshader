shader_type spatial;
// Everything on the island that MeshKit builds: painted per face with vertex
// colours, with a few things a flat material can't do. Plants bend in the
// wind (MeshKit stores how much in UV.x), light glows through leaves, and
// whatever lies under the sea catches dancing caustics.
render_mode cull_back, specular_schlick_ggx, diffuse_burley;

uniform float sea_level = 0.0;
uniform float ground = 0.5;
uniform float wind_strength = 0.035;
uniform vec3 caustic_color : source_color = vec3(0.85, 1.0, 0.95);
// For meshes without MeshKit data (the sea floor): a flat colour, no wind.
uniform vec3 tint : source_color = vec3(1.0);
uniform bool kit_mesh = true;
// The sea floor shelves away from the island so the sea deepens to blue.
uniform float shelf_start = 1000.0;
uniform float shelf_end = 1001.0;
uniform float shelf_drop = 0.0;

varying vec3 world_pos;
varying float sway;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

// Gusts roll across the island as a slow wave with a quicker flutter on top.
vec2 wind(vec2 p, float t) {
	float gust = vnoise(p * 0.18 + vec2(t * 0.35, t * 0.1));
	float flutter = sin(t * 2.3 + p.x * 1.7 + p.y * 1.1) * 0.35 + sin(t * 3.7 + p.y * 2.3) * 0.15;
	return vec2(0.9, 0.45) * (gust * 1.2 + flutter * 0.5 - 0.35);
}

// Two layers of bright, wavy cells, like sunlight through ripples.
float caustics(vec2 p, float t) {
	float c = 0.0;
	for (int i = 0; i < 2; i++) {
		vec2 q = p * (1.6 + float(i) * 0.9) + vec2(t * 0.3, -t * 0.22) * (1.0 + float(i));
		q += vec2(sin(q.y * 1.3 + t), cos(q.x * 1.1 - t * 0.8)) * 0.45;
		vec2 f = fract(q) - 0.5;
		float d = length(f);
		c += smoothstep(0.42, 0.5, d) * 0.6 + pow(1.0 - abs(sin(q.x * 3.14159) * sin(q.y * 3.14159)), 8.0) * 0.5;
	}
	return c * 0.5;
}

void vertex() {
	sway = kit_mesh ? UV.x : 0.0;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float shelf = smoothstep(shelf_start, shelf_end, length(world_pos.xz)) * shelf_drop;
	VERTEX.y -= shelf;
	world_pos.y -= shelf;
	if (sway > 0.0) {
		float h = max(world_pos.y - ground, 0.0);
		vec2 w = wind(world_pos.xz, TIME) * wind_strength * sway * h * h * 6.0;
		VERTEX.xz += w;
		// Bending sideways also lowers the tip a little.
		VERTEX.y -= dot(w, w) * 2.0;
		world_pos.xz += w;
	}
}

void fragment() {
	// MeshKit colours are sRGB.
	vec3 col = pow(COLOR.rgb, vec3(2.2)) * tint;
	// Break up the flat faces with a soft, large-scale wash.
	float wash = vnoise(world_pos.xz * 0.9) * 0.5 + vnoise(world_pos.xz * 3.1) * 0.5;
	col *= 0.93 + wash * 0.14;
	if (sway > 0.0) {
		// Foliage is darker near the ground, as if shaded by itself.
		float h = clamp((world_pos.y - ground + 0.02) / 0.9, 0.0, 1.0);
		col *= mix(0.62, 1.08, h);
		BACKLIGHT = col * 0.55;
		ROUGHNESS = 0.75;
	} else {
		ROUGHNESS = 0.88;
	}
	SPECULAR = 0.25;
	// Under the sea: sunlit caustics, fading out with depth.
	float under = sea_level - world_pos.y;
	if (under > 0.0) {
		float fade = smoothstep(0.0, 0.08, under) * exp(-under * 0.9);
		EMISSION = caustic_color * caustics(world_pos.xz, TIME) * fade * 0.28;
		col *= mix(1.0, 0.8, clamp(under, 0.0, 1.0));
	}
	ALBEDO = col;
}
