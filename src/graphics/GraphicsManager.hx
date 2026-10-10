package graphics;

import h3d.Engine;
import h3d.scene.Scene;
import h3d.scene.fwd.DirLight;
import save.SaveSystem.GraphicsSettings;

/**
 * Graphics pipeline controller and hardware configuration manager.
 * Applies render scaling, shadow mapping profiles, and directional sunlight color
 * temperatures dynamically based on user graphics quality preferences.
 */
class GraphicsManager {
    /** Global singleton instance for access across settings and engine loops. */
    public static var inst:GraphicsManager;

    /** Currently active user graphics configuration settings profile. */
    public var settings:GraphicsSettings;

    /** Reference to the Heaps 3D scene instance. */
    var s3d:Scene;

    /** Reference to the Heaps 2D scene instance for UI scaling. */
    var s2d:h2d.Scene;

    /** Reference to the primary directional sunlight in the scene. */
    var light:DirLight;

    /** Reference to the post-processing 3D renderer. */
    var postRenderer:PostProcessRenderer;

    /**
     * Initializes the graphics manager singleton and immediately applies active settings.
     *
     * @param s3d Target 3D scene instance.
     * @param s2d Target 2D UI scene instance.
     * @param light Primary directional sunlight instance.
     * @param initialSettings Initial graphics profile loaded from storage or defaults.
     * @param post Optional post-processing renderer instance.
     */
    public function new(s3d:Scene, s2d:h2d.Scene, light:DirLight, initialSettings:GraphicsSettings, ?post:PostProcessRenderer) {
        inst = this;
        this.s3d = s3d;
        this.s2d = s2d;
        this.light = light;
        this.settings = initialSettings;
        this.postRenderer = (post != null) ? post : (Std.isOfType(s3d.renderer, PostProcessRenderer) ? cast s3d.renderer : null);
        applyAll();
    }

    /**
     * Re-applies all graphics sub-pipelines (render scale, UI resolution, shadows, and lighting).
     */
    public function applyAll() {
        applyRenderScale();
        applyUIResolution();
        applyShadows();
        applyLighting();
        applyTexturesAndFiltering();
    }

    /**
     * Re-scales the 3D scene offscreen rendering target to the desired resolution multiplier
     * independently from the 2D UI without degrading font or 2D HUD crispness.
     */
    public function applyRenderScale() {
        if (postRenderer != null) {
            postRenderer.renderScale = settings.renderScale;
        }
        #if js
        var engine = Engine.getCurrent();
        var win = hxd.Window.getInstance();
        if (engine != null && win != null) {
            // Guarantee backbuffer matches native window resolution so 2D UI stays crisp
            engine.resize(win.width, win.height);
        }
        #end
    }

    /**
     * Scales the 2D UI independently to the user's selected UI Resolution target.
     * Configures the 2D Scene scaleMode to AutoZoom to the chosen virtual baseline resolution,
     * or Resize (1:1 native pixel mapping).
     */
    public function applyUIResolution() {
        if (s2d == null) return;
        switch (settings.uiResolution) {
            case "720p (HD)":
                s2d.scaleMode = AutoZoom(1280, 720, false);
            case "1080p (FHD)":
                s2d.scaleMode = AutoZoom(1920, 1080, false);
            case "1440p (2K)":
                s2d.scaleMode = AutoZoom(2560, 1440, false);
            case "2160p (4K)":
                s2d.scaleMode = AutoZoom(3840, 2160, false);
            case "Native / Match Window":
                s2d.scaleMode = Resize;
            default:
                s2d.scaleMode = AutoZoom(1280, 720, false);
        }
        s2d.checkResize();
    }

    /**
     * Configures shadow map rendering passes and specular highlights on the directional light.
     */
    public function applyShadows() {
        if (light == null) return;
        if (settings.shadowLevel == "Off") {
            light.enableSpecular = false;
        } else {
            light.enableSpecular = true;
        }
    }

    /**
     * Adjusts primary directional sunlight color temperature and ambient illumination intensity.
     */
    public function applyLighting() {
        if (light == null) return;
        var fwd = (s3d != null && s3d.lightSystem != null) ? Std.downcast(s3d.lightSystem, h3d.scene.fwd.LightSystem) : null;
        switch (settings.lightingLevel) {
            case "Low":
                light.color.setColor(0xDDD0B0);
                if (fwd != null) fwd.ambientLight.setColor(0x242D38);
            case "Medium":
                light.color.setColor(0xFFE8C2);
                if (fwd != null) fwd.ambientLight.setColor(0x384756);
            case "High":
                light.color.setColor(0xFFF0D0);
                if (fwd != null) fwd.ambientLight.setColor(0x4C5E72);
            case "Ultra (RTX/Path)":
                light.color.setColor(0xFFF8E8);
                if (fwd != null) fwd.ambientLight.setColor(0x5F768E);
            default:
                light.color.setColor(0xFFE8C2);
                if (fwd != null) fwd.ambientLight.setColor(0x384756);
        }
    }

    /**
     * Configures hardware multi-sampling antialiasing.
     */
    public function applyTexturesAndFiltering() {
        Engine.ANTIALIASING = (settings.aaType != "None") ? settings.aaLevel : 0;
    }
}