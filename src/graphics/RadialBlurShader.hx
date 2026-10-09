package graphics;

import h3d.shader.ScreenShader;

/**
 * Screen-space radial directional motion blur post-processing shader.
 * Samples scene pixels along vectors radiating from a focal origin point
 * (such as the vehicle vanishing point or screen center) scaled dynamically by vehicle velocity.
 */
class RadialBlurShader extends ScreenShader {
    static var SRC = {
        /** Input scene color texture. */
        @param var texture : Sampler2D;

        /** Screen-space focus center origin [0.0 - 1.0]. */
        @param var blurOrigin : Vec2;

        /** Dynamic blur displacement intensity scalar. */
        @param var blurIntensity : Float;

        function fragment() {
            var uv = input.uv;
            var dir = (uv - blurOrigin) * blurIntensity;
            var col = vec4(0, 0, 0, 0);

            // 8-tap radial blur sample integration
            @unroll for (i in 0...8) {
                var sampleUv = clamp(uv - dir * (float(i) / 7.0), vec2(0.0), vec2(1.0));
                col += texture.get(sampleUv);
            }
            pixelColor = col / 8.0;
        }
    };

    /**
     * Constructs a new radial motion blur screen shader instance.
     */
    public function new() {
        super();
        blurOrigin.set(0.5, 0.5);
        blurIntensity = 0.0;
    }
}

