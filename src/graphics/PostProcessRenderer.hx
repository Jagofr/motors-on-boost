package graphics;

/**
 * Post-processing pipeline controller for WebGPU radial boost blur & resolution scaling.
 */
class PostProcessRenderer {
    public var blurShader:RadialBlurShader;
    public var renderScale:Float = 1.0;

    public function new() {
        blurShader = new RadialBlurShader();
    }

    public function setRenderScale(scale:Float):Void {
        renderScale = Math.max(0.25, Math.min(2.0, scale));
    }

    public function dispose():Void {
        blurShader.blurIntensity = 0.0;
    }
}
