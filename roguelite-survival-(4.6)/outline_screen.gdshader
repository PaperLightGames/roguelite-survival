shader_type canvas_item;

// Outline Screen Shader for Godot 4.6.x (canvas_item)
// Uses Sobel edge detection on the screen color buffer.
//
// Setup:
//   1. Add a CanvasLayer (layer = 100 or higher).
//   2. Add a ColorRect child, set to Full Rect (anchors all corners).
//   3. Assign a ShaderMaterial with this shader.
//   That's it — no SubViewport needed.

group_uniforms outline;
/// The color of the outline.
uniform vec4 outline_color : source_color = vec4(0.05, 0.05, 0.05, 1.0);
/// Outline thickness in pixels.
uniform float outline_thickness : hint_range(0.5, 5.0, 0.5) = 1.5;
/// Edge detection sensitivity — lower values detect more edges.
uniform float edge_threshold : hint_range(0.01, 1.0, 0.01) = 0.08;

group_uniforms shadow;
/// If enabled, outlines will also appear on shadow edges.
uniform bool outline_shadows = false;
/// Shadow edge suppression — higher values filter out more soft shadow edges.
uniform float shadow_threshold : hint_range(0.0, 0.5, 0.01) = 0.12;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;

float luminance(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

void fragment() {
	vec2 px = outline_thickness / vec2(textureSize(screen_texture, 0));

	// 3x3 neighborhood luminance for Sobel
	float tl = luminance(texture(screen_texture, SCREEN_UV + vec2(-px.x,  px.y)).rgb);
	float tc = luminance(texture(screen_texture, SCREEN_UV + vec2(  0.0,  px.y)).rgb);
	float tr = luminance(texture(screen_texture, SCREEN_UV + vec2( px.x,  px.y)).rgb);
	float ml = luminance(texture(screen_texture, SCREEN_UV + vec2(-px.x,   0.0)).rgb);
	float mr = luminance(texture(screen_texture, SCREEN_UV + vec2( px.x,   0.0)).rgb);
	float bl = luminance(texture(screen_texture, SCREEN_UV + vec2(-px.x, -px.y)).rgb);
	float bc = luminance(texture(screen_texture, SCREEN_UV + vec2(  0.0, -px.y)).rgb);
	float br = luminance(texture(screen_texture, SCREEN_UV + vec2( px.x, -px.y)).rgb);

	// Sobel gradients
	float gx = -tl - 2.0 * ml - bl + tr + 2.0 * mr + br;
	float gy = -tl - 2.0 * tc - tr + bl + 2.0 * bc + br;
	float sobel = sqrt(gx * gx + gy * gy);

	// Color-channel edge detection for better silhouette handling
	vec3 c_l = texture(screen_texture, SCREEN_UV + vec2(-px.x, 0.0)).rgb;
	vec3 c_r = texture(screen_texture, SCREEN_UV + vec2( px.x, 0.0)).rgb;
	vec3 c_t = texture(screen_texture, SCREEN_UV + vec2(0.0,  px.y)).rgb;
	vec3 c_b = texture(screen_texture, SCREEN_UV + vec2(0.0, -px.y)).rgb;
	float color_edge = (length(c_r - c_l) + length(c_t - c_b)) * 0.5;

	float edge_strength = max(sobel, color_edge);

	// Apply threshold — when shadows are disabled, raise it to skip soft gradients
	float thresh = edge_threshold;
	if (!outline_shadows) {
		thresh += shadow_threshold;
	}
	float edge = smoothstep(thresh * 0.5, thresh, edge_strength);

	// Composite
	vec4 screen_col = texture(screen_texture, SCREEN_UV);
	COLOR = mix(screen_col, outline_color, edge * outline_color.a);
}
