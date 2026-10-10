package graphics;

import h3d.scene.fwd.Renderer;
import h3d.pass.ScreenFx;

/**
 * Custom forward scene renderer providing clean post-processing passes.
 * Intercepts the forward rendering pipeline to render off-screen when high-speed
 * radial directional motion blur is active, rendering directly to backbuffer otherwise.
 */
class PostProcessRenderer extends Renderer {
    /** Custom radial directional motion blur shader. */
    public var blurShader:RadialBlurShader;

    /** ScreenFx post-processing executor. */
    var screenFx:ScreenFx<RadialBlurShader>;

    /** Independent 3D scene rendering scale ratio relative to native backbuffer. */
    public var renderScale:Float = 1.0;

    /**
     * Constructs and initializes the post-processing renderer pipeline.
     */
    public function new() {
        super();
        blurShader = new RadialBlurShader();
        screenFx = new ScreenFx(blurShader);
    }

    override function render() {
        var needsOffscreen = (Math.abs(renderScale - 1.0) > 0.001) || (blurShader != null && blurShader.blurIntensity > 0.001);
        if (needsOffscreen) {
            // Allocate offscreen render target matching current engine viewport scaled by renderScale
            var target = allocTarget("scene3dBuffer", true, renderScale);
            setTarget(target);
            clear(ctx.engine.backgroundColor, 1);

            // Execute standard forward geometry and shadow passes
            super.render();

            resetTarget();

            // Execute radial blur screen pass to output display backbuffer
            blurShader.texture = target;
            screenFx.render();
        } else {
            // Standard direct render pass to display buffer with zero offscreen overhead
            super.render();
        }
    }

    override function dispose() {
        super.dispose();
        if (screenFx != null) {
            screenFx.dispose();
            screenFx = null;
        }
    }
}

