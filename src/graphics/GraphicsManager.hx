package graphics;

import h3d.Engine;
import h3d.scene.Scene;
import h3d.scene.fwd.DirLight;
import save.SaveSystem.GraphicsSettings;

/**
 * Virtual 2D UI scale resolution descriptor.
 *
 * @typedef {Object} UIResolutionPreset
 * @property {Bool} isNative True for 1:1 native pixel Resize scaling.
 * @property {Int} width Virtual baseline width when `isNative` is false.
 * @property {Int} height Virtual baseline height when `isNative` is false.
 */
typedef UIResolutionPreset = {
    var isNative:Bool;
    var width:Int;
    var height:Int;
}

/**
 * Scene illumination preset pairing solar tint with softened ambient sky fill.
 *
 * @typedef {Object} LightingPreset
 * @property {Int} sunColor Primary directional solar color hex.
 * @property {Int} ambientColor Global ambient scene fill color hex.
 */
typedef LightingPreset = {
    var sunColor:Int;
    var ambientColor:Int;
}

/**
 * Graphics pipeline controller and hardware quality manager.
 * Applies render scaling, virtual UI scale modes, shadows, lighting temperatures,
 * and MSAA hardware sampling declaratively.
 *
 * @class GraphicsManager
 * @module graphics/GraphicsManager
 */
class GraphicsManager {
    /** Global singleton instance for settings panels and resize listeners. */
    public static var inst:GraphicsManager;

    /** Declarative lookup table mapping UI resolution labels to Heaps ScaleMode settings. */
    private static var UI_RES_PRESETS:Map<String, UIResolutionPreset> = [
        "720p (HD)" => { isNative: false, width: 1280, height: 720 },
        "1080p (FHD)" => { isNative: false, width: 1920, height: 1080 },
        "1440p (2K)" => { isNative: false, width: 2560, height: 1440 },
        "2160p (4K)" => { isNative: false, width: 3840, height: 2160 },
        "Native / Match Window" => { isNative: true, width: 0, height: 0 }
    ];

    /** Declarative lookup table mapping lighting quality labels to solar & ambient hex colors. */
    private static var LIGHTING_PRESETS:Map<String, LightingPreset> = [
        "Low" => { sunColor: 0xEADBB8, ambientColor: 0x708294 },
        "Medium" => { sunColor: 0xFFECC8, ambientColor: 0x869BB0 },
        "High" => { sunColor: 0xFFF2D6, ambientColor: 0x9EB4C8 },
        "Ultra (RTX/Path)" => { sunColor: 0xFFF9EE, ambientColor: 0xB2C8DC }
    ];

    /** Active user graphics quality configuration record. */
    public var settings:GraphicsSettings;

    /** Target 3D scene instance. */
    var s3d:Scene;

    /** Target 2D UI scene instance. */
    var s2d:h2d.Scene;

    /** Primary solar directional light source. */
    var light:DirLight;

    /** Post-processing offscreen forward renderer. */
    var postRenderer:PostProcessRenderer;

    /**
     * Initializes the GraphicsManager singleton and commits initial hardware preferences.
     *
     * @param {Scene} s3d Active 3D scene graph.
     * @param {h2d.Scene} s2d Active 2D UI scene graph.
     * @param {DirLight} light Primary solar directional light.
     * @param {GraphicsSettings} initialSettings Loaded or default graphics configuration.
     * @param {Null<PostProcessRenderer>} [post] Optional post-process renderer override.
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
     * Commits all graphics sub-pipelines simultaneously.
     *
     * @returns {Void}
     */
    public function applyAll():Void {
        applyRenderScale();
        applyUIResolution();
        applyShadows();
        applyLighting();
        applyTexturesAndFiltering();
    }

    /**
     * Updates 3D offscreen render buffer resolution scaling independently of native UI clarity.
     *
     * @returns {Void}
     */
    public function applyRenderScale():Void {
        if (postRenderer != null) {
            postRenderer.renderScale = settings.renderScale;
        }
        #if js
        var engine = Engine.getCurrent();
        var win = hxd.Window.getInstance();
        if (engine != null && win != null) {
            engine.resize(win.width, win.height);
        }
        #end
    }

    /**
     * Applies UI resolution preset to the 2D Scene `scaleMode`.
     *
     * @returns {Void}
     */
    public function applyUIResolution():Void {
        if (s2d == null) return;
        var preset = UI_RES_PRESETS.get(settings.uiResolution);
        if (preset == null) preset = UI_RES_PRESETS.get("720p (HD)");
        s2d.scaleMode = preset.isNative ? Resize : AutoZoom(preset.width, preset.height, false);
        @:privateAccess {
            s2d.offsetX = 0;
            s2d.offsetY = 0;
        }
        s2d.checkResize();
    }

    /**
     * Enables or disables specular highlights and shadow map behavior based on shadow tier.
     *
     * @returns {Void}
     */
    public function applyShadows():Void {
        if (light == null) return;
        light.enableSpecular = (settings.shadowLevel != "Off");
    }

    /**
     * Applies solar beam temperature and ambient fill intensity from lighting tier presets.
     *
     * @returns {Void}
     */
    public function applyLighting():Void {
        if (light == null) return;
        var fwd = (s3d != null && s3d.lightSystem != null) ? Std.downcast(s3d.lightSystem, h3d.scene.fwd.LightSystem) : null;
        var preset = LIGHTING_PRESETS.get(settings.lightingLevel);
        if (preset == null) preset = LIGHTING_PRESETS.get("Medium");

        light.color.setColor(preset.sunColor);
        if (fwd != null) {
            fwd.ambientLight.setColor(preset.ambientColor);
        }
    }

    /**
     * Configures MSAA multi-sampling anti-aliasing buffer samples.
     *
     * @returns {Void}
     */
    public function applyTexturesAndFiltering():Void {
        Engine.ANTIALIASING = (settings.aaType != "None") ? settings.aaLevel : 0;
    }
}
