shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float madness = 0.1;
uniform float danger = 0.0;
uniform float flash = 0.0;
uniform float hurt = 0.0;
uniform float t = 0.0;

float hash(vec2 p){ return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p){
	vec2 i = floor(p); vec2 f = fract(p); vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 p){ float v = 0.0; float a = 0.5; for (int i = 0; i < 4; i++){ v += a * noise(p); p *= 2.03; a *= 0.5; } return v; }
vec3 hue_shift(vec3 c, float h){
	vec3 k = vec3(0.57735);
	float ca = cos(h);
	return c * ca + cross(k, c) * sin(h) + k * dot(k, c) * (1.0 - ca);
}

void fragment(){
	vec2 uv = SCREEN_UV;
	vec2 res = 1.0 / SCREEN_PIXEL_SIZE;
	float asp = res.x / res.y;
	vec2 p = vec2(uv.x * asp, uv.y);
	float m = madness;
	vec2 cen = vec2(0.5);
	vec2 d = uv - cen;
	float r = length(d * vec2(asp, 1.0));
	// vortex swirl
	float sw = m * m * 0.8 * sin(t * 0.27) * smoothstep(0.9, 0.0, r);
	float ss = sin(sw); float cs = cos(sw);
	d = mat2(vec2(cs, ss), vec2(-ss, cs)) * d;
	uv = cen + d;
	// liquid wobble
	uv += (vec2(fbm(p * 3.0 + t * 0.2), fbm(p * 3.0 + 7.3 - t * 0.2)) - 0.5) * 0.018 * m * m;
	uv.x += sin(uv.y * 40.0 + t * 8.0) * 0.004 * danger * danger;
	// flow-field brush smear (van gogh strokes)
	float a = fbm(p * 2.5 + t * 0.03) * 12.566;
	vec2 fdir = vec2(cos(a), sin(a)) * SCREEN_PIXEL_SIZE * (1.2 + 4.0 * m);
	vec3 smear = vec3(0.0);
	for (int i = -3; i <= 3; i++){
		smear += texture(screen_tex, uv + fdir * float(i)).rgb;
	}
	smear /= 7.0;
	vec2 ca = (uv - cen) * (0.003 + 0.012 * m + 0.012 * danger);
	vec3 col;
	col.r = mix(smear.r, texture(screen_tex, uv + ca).r, 0.6);
	col.g = smear.g;
	col.b = mix(smear.b, texture(screen_tex, uv - ca).b, 0.6);
	// brush texture
	vec2 q = vec2(dot(p, vec2(cos(a), sin(a))), dot(p, vec2(-sin(a), cos(a))));
	float stroke = noise(q * vec2(10.0, 140.0));
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	col *= 0.86 + 0.28 * stroke * (0.4 + m);
	// saturation + hue drift
	col = mix(vec3(lum), col, 1.15 + m * 0.8);
	col = hue_shift(col, m * m * (sin(t * 0.5) * 1.6 + (fbm(p * 1.5 + t * 0.1) - 0.5) * 2.5));
	col = mix(col, floor(col * 6.0) / 6.0, m * 0.35);
	// shadows toward deep indigo
	col += vec3(0.012, 0.0, 0.035) * (1.0 - smoothstep(0.0, 0.3, lum));
	// vignette & danger
	float vig = smoothstep(1.05, 0.25, r);
	col *= mix(1.0, vig, 0.75 + 0.2 * m);
	float pulse = 0.5 + 0.5 * sin(t * (6.0 + 6.0 * danger));
	col = mix(col, vec3(0.45, 0.0, 0.04), danger * (1.0 - vig) * (0.4 + 0.4 * pulse));
	col.r += hurt * 0.6;
	col = mix(col, vec3(1.0, 0.95, 0.9), flash);
	col += (hash(uv * res + fract(t) * 100.0) - 0.5) * (0.05 + 0.05 * m);
	COLOR = vec4(col, 1.0);
}
