shader_type canvas_item;
// 受击半透：1.0=原图不透，0.0=完全透明。受击半透建议 0.5
// 调整此默认值即可控制受击半透程度
uniform float hit_alpha : hint_range(0.0, 1.0) = 0.5;

void fragment() {
	vec4 base = texture(TEXTURE, UV);
	COLOR = vec4(base.rgb, base.a * hit_alpha);
}
