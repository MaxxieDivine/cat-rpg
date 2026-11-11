// The pond: moving glints on the water pixels (found by colour: blue
// clearly above red and green), whole-pixel sharp. "night" darkens and
// cools the water on top of the scene's colour grade.
shader_type canvas_item;

uniform float night = 0.0;
uniform vec4 night_tint : source_color = vec4(0.36, 0.42, 0.63, 1.0);
uniform vec4 glint : source_color = vec4(0.84, 0.93, 0.96, 1.0);

void fragment() {
	// COLOR already holds texture x modulate.
	vec4 c = COLOR;
	vec2 px = floor(UV / TEXTURE_PIXEL_SIZE);
	bool water = c.b > c.r + 0.12 && c.b > c.g + 0.04;
	if (water) {
		float row = sin(px.y * 2.1 + floor(TIME * 1.5));
		float w = sin(px.x * 0.42 - TIME * 1.7 + px.y * 1.3) * row;
		float w2 = sin(px.x * 0.19 + TIME * 0.9 - px.y * 0.6);
		float g = (w > 0.82 ? 1.0 : 0.0) * (w2 > 0.1 ? 1.0 : 0.0) * (1.0 - night * 0.7);
		c.rgb = mix(c.rgb, glint.rgb, g * 0.75);
		c.rgb = mix(c.rgb, c.rgb * night_tint.rgb, night);
	}
	COLOR = c;
}
