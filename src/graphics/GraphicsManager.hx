package graphics;

import graphics.SceneGraph.DirLightNode;
import graphics.SceneGraph.EngineStub;
import graphics.SceneGraph.Scene3D;
import save.SaveSystem.GraphicsSettings;
import ui.nodes.UINodes.UIScene2D;
import ui.nodes.UINodes.UIScaleMode;

/**
 * Resolution scaling preset record for 2D UI layout.
 */
typedef UIResolutionPreset = {
    var isNative:Bool;
    var width:Int;
    var height:Int;
};

/**
 * Directional sun and ambient illumination preset record.
 */
typedef LightingPreset = {
    var sunColor:Int;
    var ambientColor:Int;
};

/**
 * Centralized graphics pipeline coordinator managing WebGPU resolution scaling,
 * virtual UI layout resolution, directional/ambient lighting presets, and post-processing.
 */
class GraphicsManager {
    public static var inst:GraphicsManager;

    private static var UI_RES_PRESETS:Map<String, UIResolutionPreset> = [
        "720p (HD)" => { isNative: false, width: 1280, height: 720 },
        "1080p (FHD)" => { isNative: false, width: 1920, height: 1080 },
        "1440p (2K)" => { isNative: false, width: 2560, height: 1440 },
        "2160p (4K)" => { isNative: false, width: 3840, height: 2160 },
        "Native / Match Window" => { isNative: true, width: 0, height: 0 }
    ];

    private static var LIGHTING_PRESETS:Map<String, LightingPreset> = [
        "Low" => { sunColor: 0xEADBB8, ambientColor: 0x708294 },
        "Medium" => { sunColor: 0xFFECC8, ambientColor: 0x869BB0 },
        "High" => { sunColor: 0xFFF2D6, ambientColor: 0x9EB4C8 },
        "Ultra (RTX/Path)" => { sunColor: 0xFFF9EE, ambientColor: 0xB2C8DC }
    ];

    public var settings:GraphicsSettings;
    private var s3d:Null<Scene3D>;
    private var s2d:Null<UIScene2D>;
    private var sunLight:Null<DirLightNode>;
    private var postRenderer:Null<PostProcessRenderer>;
    private var gpuRenderer:Null<WebGpuRenderer>;

    public var shadowsEnabled:Bool = true;
    public var shadowSize:Int = 1024;
    public var mipmapping:Bool = true;
    public var maxAnisotropy:Int = 4;

    public function new(
        s3d:Null<Scene3D>,
        s2d:Null<UIScene2D>,
        light:Null<DirLightNode>,
        initialSettings:GraphicsSettings,
        ?postRenderer:PostProcessRenderer,
        ?gpuRenderer:WebGpuRenderer
    ) {
        this.s3d = s3d;
        this.s2d = s2d;
        this.sunLight = light;
        this.settings = initialSettings;
        this.postRenderer = postRenderer;
        this.gpuRenderer = gpuRenderer;
        inst = this;
        applyAll();
    }

    public function setWebGpuRenderer(renderer:Null<WebGpuRenderer>):Void {
        this.gpuRenderer = renderer;
        applyAll();
    }

    public function applyAll():Void {
        applyRenderScale();
        applyUIResolution();
        applyShadows();
        applyLighting();
        applyTexturesAndFiltering();
        applyAntiAliasing();
        applyReflections();
        applyModelGeometry();
        syncRendererFxState();
    }

    public function applyRenderScale():Void {
        var scale = Math.max(0.25, Math.min(4.0, settings.renderScale));
        if (postRenderer != null) {
            postRenderer.setRenderScale(scale);
        }
        if (gpuRenderer != null) {
            gpuRenderer.setRenderScale(scale);
        }
    }

    public function applyUIResolution():Void {
        if (s2d == null) return;
        var resKey = settings.uiResolution != null ? settings.uiResolution : "720p (HD)";
        var preset = UI_RES_PRESETS.get(resKey);
        if (preset == null) {
            s2d.scaleMode = UIScaleMode.LetterBox(1280, 720, true);
        } else if (preset.isNative) {
            s2d.scaleMode = UIScaleMode.Resize;
            var eng = EngineStub.getCurrent();
            if (eng != null && eng.width > 0 && eng.height > 0) {
                s2d.width = eng.width;
                s2d.height = eng.height;
            }
        } else {
            s2d.scaleMode = UIScaleMode.LetterBox(preset.width, preset.height, true);
            s2d.width = preset.width;
            s2d.height = preset.height;
        }
        s2d.checkResize();
    }

    public function applyShadows():Void {
        if (settings.shadowLevel == "Off") {
            shadowsEnabled = false;
            shadowSize = 256;
        } else {
            shadowsEnabled = true;
            shadowSize = Std.int(Math.max(256, Math.min(4096, settings.shadowRes)));
        }
        syncRendererFxState();
    }

    public function applyLighting():Void {
        var preset = LIGHTING_PRESETS.get(settings.lightingLevel);
        if (preset == null) {
            preset = LIGHTING_PRESETS.get("Medium");
        }

        if (sunLight != null) {
            sunLight.color.setColor(preset.sunColor);
            sunLight.enableSpecular = (settings.lightingLevel != "Low");
        }
        if (s3d != null && s3d.lightSystem != null) {
            s3d.lightSystem.ambientLight.setColor(preset.ambientColor);
        }
        syncRendererFxState();
    }

    public function applyTexturesAndFiltering():Void {
        mipmapping = settings.mipmapping;
        maxAnisotropy = settings.mipmapping ? Std.int(Math.max(1, settings.anisotropic)) : 1;
        syncRendererFxState();
    }

    public function applyAntiAliasing():Void {
        syncRendererFxState();
    }

    public function applyReflections():Void {
        syncRendererFxState();
    }

    public function applyModelGeometry():Void {
        syncRendererFxState();
    }

    function syncRendererFxState():Void {
        if (gpuRenderer == null) return;
        gpuRenderer.setAntiAliasing(settings.aaType, settings.aaLevel);
        var reflScale = if (!settings.modelReflections) 0.0 else switch (settings.reflectionLevel) {
            case "Low": 0.45;
            case "High": 1.05;
            case "Ultra": 1.35;
            default: 0.78;
        };
        var shadowStr = if (!shadowsEnabled) 0.0 else switch (settings.shadowLevel) {
            case "High": 0.72;
            case "Ultra": 0.90;
            case "Dynamic": 1.0;
            default: 0.55;
        };
        var detailScale = switch (settings.textures) {
            case "Off": 0.0;
            case "Very Low": 0.25;
            case "Low": 0.50;
            case "Medium": 0.75;
            case "High": 1.0;
            case "Ultra": 1.18;
            case "Unreal": 1.32;
            default: 1.0;
        };
        if (mipmapping && maxAnisotropy > 4) detailScale *= 1.1;
        var lightScale = switch (settings.lightingLevel) {
            case "Low": 0.85;
            case "High": 1.08;
            case "Ultra (RTX/Path)": 1.18;
            default: 1.0;
        };
        if (settings.lightingRes >= 2048) lightScale *= 1.05;
        gpuRenderer.setQualityParams(reflScale, shadowStr, detailScale, lightScale);
    }
}
