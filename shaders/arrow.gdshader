shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;
global uniform float madness;
uniform vec3 col : source_color = vec3(1.0, 0.8, 0.1);

void fragment(){
	vec2 uv = UV * 2.0 - 1.0;
	vec3 np = NODE_POSITION_WORLD;
	float ph = np.x * 1.7 + np.z * 2.3;
	float m = clamp(madness - 0.3, 0.0, 1.0);
	float ang = m * m * (sin(TIME * 0.6 + ph) * 3.14159 + TIME * 2.0 * step(0.5, fract(ph * 0.13)));
	float s = sin(ang); float c = cos(ang);
	uv = mat2(vec2(c, s), vec2(-s, c)) * uv;
	float shaft = step(abs(uv.x), 0.17) * step(-0.05, uv.y) * step(uv.y, 0.8);
	float head = step(uv.y, 0.0) * step(-0.85, uv.y) * step(abs(uv.x), (uv.y + 0.85) * 0.8);
	float a = max(shaft, head);
	if (a < 0.5) discard;
	float pulse = 0.55 + 0.25 * sin(TIME * 2.0 - uv.y * 3.0 + ph);
	vec3 cc = mix(col, 0.5 + 0.5 * cos(6.2831 * (vec3(0.0, 0.33, 0.67) + TIME * 0.2 + ph)), m);
	ALBEDO = cc * pulse;
}
