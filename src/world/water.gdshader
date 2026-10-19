shader_type spatial;
// The sea (and the lake). Light passes through: we look through the surface at
// what lies below, bent by the ripples, and the water swallows red first, so
// sand turns turquoise and then deep blue. The surface reflects the sky at
// grazing angles, catches the sun, and breaks into surf at the shore.
render_mode blend_mix, depth_draw_always, cull_back, specular_schlick_ggx;

uniform vec3 shallow : source_color = vec3(0.32, 0.78, 0.76);
uniform vec3 deep : source_color = vec3(0.04, 0.22, 0.40);
uniform vec3 foam_color : source_color = vec3(0.97, 0.98, 1.0);
uniform vec3 sky_top : source_color = vec3(0.45, 0.65, 0.88);
uniform vec3 sky_horizon : source_color = vec3(0.92, 0.86, 0.76);
// How fast each colour fades with depth: red goes first.
uniform vec3 absorb = vec3(0.9, 0.32, 0.22);
uniform float depth_scale = 2.2;
uniform float foam_width = 0.45;
uniform float wave_height = 0.05;
uniform float refraction = 0.035;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear_mipmap;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;

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

// A few long swells from different directions.
float swell(vec2 p, float t) {
	float h = 0.0;
	h += sin(dot(p, vec2(0.42, 0.18)) + t * 0.9) * 0.5;
	h += sin(dot(p, vec2(-0.21, 0.47)) + t * 0.75) * 0.35;
	h += sin(dot(p, vec2(0.9, -0.6)) + t * 1.5) * 0.15;
	return h;
}

// Fine ripples: noise sliding two ways, so it never looks like a scroll.
float ripples(vec2 p, float t) {
	return vnoise(p * 1.7 + vec2(t * 0.25, t * 0.12)) * 0.5
		+ vnoise(p * 3.9 - vec2(t * 0.18, -t * 0.31)) * 0.3
		+ vnoise(p * 9.0 + vec2(-t * 0.5, t * 0.4)) * 0.2;
}

float height(vec2 p, float t) {
	return swell(p, t) + ripples(p, t) * 0.6;
}

vec3 linear_depth_pos(vec2 uv, mat4 inv_proj) {
	float d = texture(depth_tex, uv).r;
	vec4 v = inv_proj * vec4(uv * 2.0 - 1.0, d, 1.0);
	return v.xyz / v.w;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += swell(world_pos.xz, TIME) * wave_height;
}

void fragment() {
	vec2 p = world_pos.xz;
	float t = TIME;
	// Surface normal from the height field.
	float e = 0.06;
	float h0 = height(p, t);
	float hx = height(p + vec2(e, 0.0), t);
	float hz = height(p + vec2(0.0, e), t);
	vec3 wn = normalize(vec3(-(hx - h0) / e * 0.06, 1.0, -(hz - h0) / e * 0.06));
	vec3 n = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);

	// How much water lies between the surface and what is under it.
	float thick = max(VERTEX.z - linear_depth_pos(SCREEN_UV, INV_PROJECTION_MATRIX).z, 0.0);
	// Look through the ripples, but never at something in front of the water.
	vec2 bent = clamp(SCREEN_UV + wn.xz * refraction * clamp(thick, 0.0, 1.0), vec2(0.002), vec2(0.998));
	float bent_thick = VERTEX.z - linear_depth_pos(bent, INV_PROJECTION_MATRIX).z;
	if (bent_thick < 0.0) {
		bent = SCREEN_UV;
		bent_thick = thick;
	}
	bent_thick = max(bent_thick, 0.0);
	vec3 below = textureLod(screen_tex, bent, 0.0).rgb;
	float d = bent_thick / depth_scale;
	vec3 through = exp(-absorb * d * 3.0);
	float murk = clamp(1.0 - exp(-d * 1.4), 0.0, 1.0);
	vec3 body = mix(shallow, deep, smoothstep(0.0, 1.0, murk));
	vec3 water = below * through + body * (1.0 - through) * 0.9;

	// Sky in the surface, strongest at grazing angles.
	vec3 v = normalize(VIEW);
	float fresnel = 0.02 + 0.98 * pow(1.0 - clamp(dot(n, v), 0.0, 1.0), 5.0);
	vec3 r = reflect(-v, n);
	vec3 r_world = (INV_VIEW_MATRIX * vec4(r, 0.0)).xyz;
	vec3 sky = mix(sky_horizon, sky_top, clamp(r_world.y * 1.6, 0.0, 1.0));
	vec3 col = mix(water, sky, fresnel * 0.85);

	// Surf: a band at the shore and lines that roll in, broken by noise.
	float n1 = ripples(p * 1.3, t);
	float edge = 1.0 - smoothstep(0.0, foam_width, thick + (n1 - 0.5) * 0.18);
	float roll = smoothstep(0.62, 0.8, sin(thick * 14.0 - t * 2.0 + n1 * 4.0) * 0.5 + 0.5)
		* (1.0 - smoothstep(0.0, foam_width * 2.8, thick));
	float foam = clamp(edge + roll * 0.6, 0.0, 1.0);
	foam *= smoothstep(0.25, 0.45, n1 + edge * 0.45);

	// Lit by the scene only lightly; what we see through it is already lit.
	ALBEDO = mix(body * 0.25, foam_color, foam);
	EMISSION = col * (1.0 - foam) * 0.92;
	ROUGHNESS = mix(0.04, 0.7, foam);
	SPECULAR = 0.6;
	NORMAL = n;
	ALPHA = 1.0;
}
