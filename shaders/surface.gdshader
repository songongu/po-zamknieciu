shader_type spatial;
global uniform float madness;
uniform vec3 base_col : source_color = vec3(0.7);
uniform float breathe = 1.0;
uniform float tiles = 0.0;
uniform float rough = 0.85;
varying vec3 wpos;
varying vec3 wnorm;

float hash(vec2 p){ return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p){
	vec2 i = floor(p); vec2 f = fract(p); vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 p){ float v = 0.0; float a = 0.5; for (int i = 0; i < 4; i++){ v += a * noise(p); p *= 2.03; a *= 0.5; } return v; }

void vertex(){
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float b = sin(TIME * 1.1 + wp.x * 0.35 + wp.y * 0.6 + wp.z * 0.3) * 0.5 + 0.5;
	VERTEX += NORMAL * b * 0.22 * madness * madness * breathe;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment(){
	vec2 p = abs(wnorm.y) > 0.5 ? wpos.xz : vec2(wpos.x + wpos.z, wpos.y);
	float a = fbm(p * 0.18 + vec2(TIME * 0.03 * madness)) * 12.566;
	vec2 dir = vec2(cos(a), sin(a));
	vec2 q = vec2(dot(p, dir), dot(p, vec2(-dir.y, dir.x)));
	float stroke = noise(q * vec2(1.5, 14.0));
	vec3 c = base_col * (0.8 + 0.32 * stroke);
	if (tiles > 0.0){
		vec2 g = abs(fract(p / tiles) - 0.5);
		float line = smoothstep(0.47, 0.49, max(g.x, g.y));
		c *= 1.0 - line * 0.45;
		c *= 0.9 + 0.2 * noise(floor(p / tiles) * 3.1);
	}
	ALBEDO = c;
	ROUGHNESS = rough;
	float sw = fbm(p * 0.22 + vec2(sin(TIME * 0.1), cos(TIME * 0.13)) * madness * 3.0);
	vec3 pal = 0.5 + 0.5 * cos(6.2831 * (vec3(0.0, 0.33, 0.67) + sw * 2.0 + TIME * 0.05));
	float band = smoothstep(0.55, 0.8, sin(sw * 30.0 + TIME * 1.5) * 0.5 + 0.5);
	float m = clamp(madness - 0.15, 0.0, 1.0);
	EMISSION = pal * band * (0.4 + stroke) * m * m * 0.7;
}
