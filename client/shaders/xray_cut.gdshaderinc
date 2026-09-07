uniform vec3 xray_ball = vec3(0.0);
uniform vec3 xray_cam = vec3(0.0);
uniform float xray_radius = 0.0;

void xray_try_discard(vec3 world_pos, float ground_amt) {
	if (xray_radius < 0.08) {
		return;
	}
	// Keep the putting surface around the ball solid. Roofs and walls still cut.
	if (ground_amt > 0.72 && abs(world_pos.y - xray_ball.y) < 0.55) {
		return;
	}
	vec3 axis = xray_ball - xray_cam;
	float span = length(axis);
	vec3 dir = axis / max(span, 0.001);
	float t = clamp(dot(world_pos - xray_cam, dir), 0.0, span);
	float u = t / max(span, 0.001);
	float rad = mix(xray_radius, max(xray_radius * 0.28, 0.4), u * u);
	float dist = length(xray_cam + dir * t - world_pos);
	if (dist < rad) {
		discard;
	}
}
