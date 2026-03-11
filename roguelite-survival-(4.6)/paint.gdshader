shader_type canvas_item;

// ============================================================
// Painterly / Watercolor Post-Processing Shader for Godot 4.5.x
// ============================================================
// Usage: Apply to a ColorRect or TextureRect that covers the full screen.
//        Set the SCREEN_TEXTURE as the source via the built-in hint.
//        Place this node as a child of a CanvasLayer (layer 100+).
//
// For SubViewport approach: render your 3D scene into a SubViewportContainer,
// then apply this shader to a TextureRect displaying that viewport's texture.
// ============================================================

// --- Compat --- 
uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;


// --- Core Controls ---
group_uniforms core;
/// How strongly the painterly effect is applied (0 = off, 1 = full).
uniform float effect_strength : hint_range(0.0, 1.0, 0.01) = 0.85;
/// Overall color saturation boost for a watercolor feel.
uniform float saturation : hint_range(0.0, 2.0, 0.01) = 1.15;
/// Warm/cool paper tint blended in.
uniform vec4 paper_tint : source_color = vec4(0.98, 0.96, 0.91, 1.0);
/// How much paper tint bleeds into the image.
uniform float paper_blend : hint_range(0.0, 0.5, 0.01) = 0.08;

// --- Brush Stroke Simulation ---
group_uniforms brush;
/// Size of directional brush strokes in pixels.
uniform float stroke_size : hint_range(1.0, 12.0, 0.5) = 3.5;
/// Number of samples along the stroke direction (higher = smoother but costlier).
uniform int stroke_samples : hint_range(2, 12) = 6;
/// Randomness of stroke angle. 0 = follows edges, 1 = chaotic.
uniform float stroke_randomness : hint_range(0.0, 1.0, 0.01) = 0.25;

// --- Edge Darkening (Ink Lines) ---
group_uniforms edges;
/// Strength of dark edge lines (set to 0 to disable).
uniform float edge_strength : hint_range(0.0, 3.0, 0.01) = 0.6;
/// Thickness of edge detection kernel.
uniform float edge_thickness : hint_range(0.5, 4.0, 0.1) = 1.2;
/// Color of the edge lines.
uniform vec4 edge_color : source_color = vec4(0.15, 0.12, 0.10, 1.0);

// --- Color Quantization (Flat Color Areas) ---
group_uniforms quantize;
/// Number of discrete color levels per channel (lower = more posterized/painterly).
uniform float color_levels : hint_range(4.0, 64.0, 1.0) = 18.0;
/// Smoothness of the quantization transition.
uniform float quantize_softness : hint_range(0.0, 1.0, 0.01) = 0.4;

// --- Watercolor Bleed / Diffusion ---
group_uniforms watercolor;
/// Radius of the wet-edge color bleeding effect.
uniform float bleed_radius : hint_range(0.0, 8.0, 0.1) = 2.5;
/// Intensity of pigment concentration at edges.
uniform float pigment_density : hint_range(0.0, 1.0, 0.01) = 0.35;
/// Animated wobble speed for the paint (0 = static).
uniform float wobble_speed : hint_range(0.0, 2.0, 0.01) = 0.3;
/// Grain / paper texture noise intensity.
uniform float grain_intensity : hint_range(0.0, 0.5, 0.01) = 0.08;

// ============================================================
// Hash & Noise Utilities
// ============================================================

float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

// Simplex-ish value noise for smooth variation.
float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f); // smoothstep

	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));

	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Fractal Brownian Motion for organic texture.
float fbm(vec2 p, int octaves) {
	float value = 0.0;
	float amplitude = 0.5;
	float frequency = 1.0;
	for (int i = 0; i < octaves; i++) {
		value += amplitude * value_noise(p * frequency);
		frequency *= 2.0;
		amplitude *= 0.5;
	}
	return value;
}

// ============================================================
// Color Utilities
// ============================================================

vec3 rgb_to_hsl(vec3 c) {
	float cmax = max(c.r, max(c.g, c.b));
	float cmin = min(c.r, min(c.g, c.b));
	float delta = cmax - cmin;
	float l = (cmax + cmin) * 0.5;
	float s = 0.0;
	float h = 0.0;

	if (delta > 0.001) {
		s = delta / (1.0 - abs(2.0 * l - 1.0));
		if (cmax == c.r) {
			h = mod((c.g - c.b) / delta, 6.0);
		} else if (cmax == c.g) {
			h = (c.b - c.r) / delta + 2.0;
		} else {
			h = (c.r - c.g) / delta + 4.0;
		}
		h /= 6.0;
	}
	return vec3(h, s, l);
}

float hue2rgb(float p, float q, float t) {
	if (t < 0.0) t += 1.0;
	if (t > 1.0) t -= 1.0;
	if (t < 1.0 / 6.0) return p + (q - p) * 6.0 * t;
	if (t < 0.5) return q;
	if (t < 2.0 / 3.0) return p + (q - p) * (2.0 / 3.0 - t) * 6.0;
	return p;
}

vec3 hsl_to_rgb(vec3 hsl) {
	float h = hsl.x, s = hsl.y, l = hsl.z;
	if (s < 0.001) return vec3(l);
	float q = l < 0.5 ? l * (1.0 + s) : l + s - l * s;
	float p = 2.0 * l - q;
	return vec3(
		hue2rgb(p, q, h + 1.0 / 3.0),
		hue2rgb(p, q, h),
		hue2rgb(p, q, h - 1.0 / 3.0)
	);
}

// ============================================================
// Sobel Edge Detection
// ============================================================

float get_luminance(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

float sobel_edge(sampler2D tex, vec2 uv, vec2 pixel_size) {
	vec2 step_val = pixel_size * edge_thickness;

	float tl = get_luminance(texture(tex, uv + vec2(-step_val.x, -step_val.y)).rgb);
	float tc = get_luminance(texture(tex, uv + vec2(0.0, -step_val.y)).rgb);
	float tr = get_luminance(texture(tex, uv + vec2(step_val.x, -step_val.y)).rgb);
	float ml = get_luminance(texture(tex, uv + vec2(-step_val.x, 0.0)).rgb);
	float mr = get_luminance(texture(tex, uv + vec2(step_val.x, 0.0)).rgb);
	float bl = get_luminance(texture(tex, uv + vec2(-step_val.x, step_val.y)).rgb);
	float bc = get_luminance(texture(tex, uv + vec2(0.0, step_val.y)).rgb);
	float br = get_luminance(texture(tex, uv + vec2(step_val.x, step_val.y)).rgb);

	float gx = -tl - 2.0 * ml - bl + tr + 2.0 * mr + br;
	float gy = -tl - 2.0 * tc - tr + bl + 2.0 * bc + br;

	return sqrt(gx * gx + gy * gy);
}

// Gradient direction for stroke alignment.
vec2 sobel_gradient(sampler2D tex, vec2 uv, vec2 pixel_size) {
	vec2 step_val = pixel_size * 1.5;

	float tl = get_luminance(texture(tex, uv + vec2(-step_val.x, -step_val.y)).rgb);
	float tc = get_luminance(texture(tex, uv + vec2(0.0, -step_val.y)).rgb);
	float tr = get_luminance(texture(tex, uv + vec2(step_val.x, -step_val.y)).rgb);
	float ml = get_luminance(texture(tex, uv + vec2(-step_val.x, 0.0)).rgb);
	float mr = get_luminance(texture(tex, uv + vec2(step_val.x, 0.0)).rgb);
	float bl = get_luminance(texture(tex, uv + vec2(-step_val.x, step_val.y)).rgb);
	float bc = get_luminance(texture(tex, uv + vec2(0.0, step_val.y)).rgb);
	float br = get_luminance(texture(tex, uv + vec2(step_val.x, step_val.y)).rgb);

	float gx = -tl - 2.0 * ml - bl + tr + 2.0 * mr + br;
	float gy = -tl - 2.0 * tc - tr + bl + 2.0 * bc + br;

	return vec2(gx, gy);
}

// ============================================================
// Directional Brush Stroke Blur
// ============================================================

vec3 brush_stroke(sampler2D tex, vec2 uv, vec2 pixel_size, float time_val) {
	// Get gradient to align strokes perpendicular to edges.
	vec2 grad = sobel_gradient(tex, uv, pixel_size);
	// Stroke direction is tangent to the edge (perpendicular to gradient).
	vec2 tangent = vec2(-grad.y, grad.x);
	float tang_len = length(tangent);

	// Add noise-based randomness for organic feel.
	float wobble = fbm(uv * 80.0 + time_val * wobble_speed * 0.5, 2) * 6.28318;
	vec2 random_dir = vec2(cos(wobble), sin(wobble));

	vec2 stroke_dir;
	if (tang_len > 0.01) {
		tangent = normalize(tangent);
		stroke_dir = normalize(mix(tangent, random_dir, stroke_randomness));
	} else {
		stroke_dir = normalize(random_dir);
	}

	// Sample along stroke direction.
	vec3 color_sum = vec3(0.0);
	float weight_sum = 0.0;
	float step_len = stroke_size / float(stroke_samples);

	for (int i = 0; i < stroke_samples; i++) {
		float t = (float(i) / float(stroke_samples - 1)) * 2.0 - 1.0; // -1 to 1
		vec2 offset = stroke_dir * t * stroke_size * pixel_size;
		// Gaussian-ish weight: center-weighted.
		float w = exp(-2.0 * t * t);
		color_sum += texture(tex, uv + offset).rgb * w;
		weight_sum += w;
	}

	return color_sum / weight_sum;
}

// ============================================================
// Watercolor Bleed (Bilateral-ish diffusion)
// ============================================================

vec3 watercolor_bleed_pass(sampler2D tex, vec2 uv, vec2 pixel_size, float time_val) {
	if (bleed_radius < 0.1) {
		return texture(tex, uv).rgb;
	}

	vec3 center = texture(tex, uv).rgb;
	float center_lum = get_luminance(center);
	vec3 bleed_sum = center;
	float w_sum = 1.0;

	// Irregular sampling offsets driven by noise.
	int samples = 8;
	for (int i = 0; i < samples; i++) {
		float angle = float(i) / float(samples) * 6.28318;
		// Wobble the angle organically.
		angle += fbm(uv * 40.0 + float(i) * 1.7 + time_val * wobble_speed, 2) * 1.5;
		float radius = bleed_radius * (0.5 + 0.5 * hash11(float(i) + uv.x * 13.0 + uv.y * 7.0));
		vec2 offset = vec2(cos(angle), sin(angle)) * radius * pixel_size;

		vec3 sample_col = texture(tex, uv + offset).rgb;
		float sample_lum = get_luminance(sample_col);

		// Bilateral weight: similar colors bleed more (pigment pools).
		float color_dist = distance(center, sample_col);
		float bilateral_w = exp(-color_dist * 8.0);
		// Pigment concentration: darker colors bleed into lighter areas.
		float pigment_w = mix(1.0, smoothstep(0.0, 0.5, center_lum - sample_lum + 0.2), pigment_density);

		float w = bilateral_w * pigment_w;
		bleed_sum += sample_col * w;
		w_sum += w;
	}

	return bleed_sum / w_sum;
}

// ============================================================
// Soft Color Quantization
// ============================================================

vec3 quantize_color(vec3 col) {
	if (color_levels >= 64.0) return col;

	vec3 hsl = rgb_to_hsl(col);
	// Quantize lightness and saturation in HSL for more natural banding.
	float levels = color_levels;
	float soft = quantize_softness;

	float l_quant = floor(hsl.z * levels + 0.5) / levels;
	float s_quant = floor(hsl.y * (levels * 0.5) + 0.5) / (levels * 0.5);

	hsl.z = mix(l_quant, hsl.z, soft);
	hsl.y = mix(s_quant, hsl.y, soft * 0.7);

	return hsl_to_rgb(hsl);
}

// ============================================================
// Main Fragment
// ============================================================

void fragment() {
	vec2 pixel_size = SCREEN_PIXEL_SIZE;
	vec2 uv = SCREEN_UV;
	float time_val = TIME;

	// --- 1. Directional Brush Stroke Blur ---
	vec3 stroked = brush_stroke(SCREEN_TEXTURE, uv, pixel_size, time_val);

	// --- 2. Watercolor Bleed / Diffusion ---
	// We approximate by sampling the screen again with bleed; in practice
	// the brush strokes feed into this giving a layered painterly look.
	vec3 base_bleed = watercolor_bleed_pass(SCREEN_TEXTURE, uv, pixel_size, time_val);
	vec3 painted = mix(stroked, base_bleed, 0.4);

	// --- 3. Soft Color Quantization ---
	vec3 quantized = quantize_color(painted);
	painted = mix(painted, quantized, effect_strength * 0.6);

	// --- 4. Saturation Adjustment ---
	float lum = get_luminance(painted);
	painted = mix(vec3(lum), painted, saturation);

	// --- 5. Paper Grain ---
	float grain = fbm(uv * 500.0 + time_val * 0.1, 3);
	float fine_grain = hash21(uv * 2000.0 + time_val * 0.05);
	float combined_grain = mix(grain, fine_grain, 0.3);
	painted += (combined_grain - 0.5) * grain_intensity;

	// --- 6. Paper Tint ---
	painted = mix(painted, paper_tint.rgb, paper_blend);

	// --- 7. Edge Darkening (Ink/Pencil Lines) ---
	if (edge_strength > 0.01) {
		float edge = sobel_edge(SCREEN_TEXTURE, uv, pixel_size);
		edge = smoothstep(0.05, 0.3, edge * edge_strength);
		// Soften edge with noise for hand-drawn feel.
		float edge_noise = fbm(uv * 200.0, 2);
		edge *= 0.7 + 0.3 * edge_noise;
		painted = mix(painted, edge_color.rgb, edge * edge_color.a);
	}

	// --- 8. Vignette (subtle, like watercolor paper darkening at edges) ---
	float vignette = 1.0 - smoothstep(0.4, 1.4, length((uv - 0.5) * 1.8));
	painted *= mix(1.0, vignette, 0.15);

	// --- Final Mix with Original ---
	vec3 original = texture(SCREEN_TEXTURE, uv).rgb;
	COLOR.rgb = mix(original, painted, effect_strength);
	COLOR.a = 1.0;
}
