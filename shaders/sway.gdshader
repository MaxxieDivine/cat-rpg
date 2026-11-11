// Wind sway for grass, flowers, bushes and tree canopies. The top edge of
// the sprite slides sideways by a whole number of world pixels (the bottom
// stays put), in a slow wave that travels across the meadow, with an
// occasional stronger gust. Whole pixels keep the art crisp.
shader_type canvas_item;

uniform float amp_px = 1.0;
uniform float speed = 1.4;
uniform float wavelength = 110.0;
uniform float gust_every = 7.0;

void vertex() {
	vec2 wp = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	float phase = TIME * speed - wp.x / wavelength * 6.2831853 + wp.y * 0.013;
	float gust = smoothstep(0.75, 1.0, sin(TIME * 6.2831853 / gust_every - wp.x / (wavelength * 3.0)));
	float s = sin(phase) * 0.6 + sin(phase * 0.47 + 1.7) * 0.4 + gust * 0.8;
	VERTEX.x += round(s * amp_px) * (1.0 - UV.y);
}
