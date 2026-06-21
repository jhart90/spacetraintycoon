shader_type canvas_item;
// Fog-of-war: TEXTURE is the reveal MASK (alpha>0 where the player has explored,
// rendered into a SubViewport). Output = black fog whose opacity is the inverse
// of the mask — clear (alpha 0) at fully-revealed pixels, 92% black elsewhere.
// Mirrors build_game.py drawFog: rgba(0,0,0,0.92) with destination-out reveals.
void fragment() {
	float m = clamp(texture(TEXTURE, UV).a, 0.0, 1.0);
	COLOR = vec4(0.0, 0.0, 0.0, 0.92 * (1.0 - m));
}
