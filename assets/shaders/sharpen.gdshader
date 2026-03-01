shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform float strength : hint_range(0.0, 1.0) = 0.1;
// Blacks: 1.0 = no change, 0.8 = deepen shadows ~20% (darker darks, highlights unchanged)
uniform float blacks : hint_range(0.0, 1.0) = 0.8;
// Grain: 0 = off, 0.04 = 4% intensity
uniform float grain : hint_range(0.0, 1.0) = 0.04;
// Vignette: 0 = off, 0.15 = edges darkened by ~15%
uniform float vignette : hint_range(0.0, 1.0) = 0.15;

vec3 apply_blacks(vec3 c, float amount) {
	float L = dot(c, vec3(0.299, 0.587, 0.114));
	float f = amount + (1.0 - amount) * L;
	return c * f;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 px = vec2(1.0) / vec2(textureSize(screen_texture, 0));
	vec4 raw_center = texture(screen_texture, uv);
	vec4 raw_blur = (
		texture(screen_texture, uv + vec2(-px.x, 0.0)) +
		texture(screen_texture, uv + vec2(px.x, 0.0)) +
		texture(screen_texture, uv + vec2(0.0, -px.y)) +
		texture(screen_texture, uv + vec2(0.0, px.y))
	) * 0.25;
	vec4 center = vec4(apply_blacks(raw_center.rgb, blacks), raw_center.a);
	vec4 blur = vec4(apply_blacks(raw_blur.rgb, blacks), raw_blur.a);
	COLOR = center + strength * (center - blur);
	// Film grain: per-pixel noise, centered so it brightens/darkens slightly
	if (grain > 0.0) {
		float n = hash(FRAGCOORD.xy) * 2.0 - 1.0;
		COLOR.rgb += n * grain;
		COLOR = clamp(COLOR, vec4(0.0), vec4(1.0));
	}
	// Vignette: darken edges (center stays bright)
	if (vignette > 0.0) {
		vec2 vuv = SCREEN_UV - 0.5;
		float v = length(vuv) * 2.0;
		float vig = 1.0 - vignette * (v * v);
		COLOR.rgb *= max(0.0, vig);
	}
}
