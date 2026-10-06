package core;

import h3d.Engine;
import h3d.scene.Scene;
import h3d.scene.fwd.DirLight;
import core.SaveSystem.GraphicsSettings;

class GraphicsManager {
    public static var inst:GraphicsManager;
    public var settings:GraphicsSettings;

    var s3d:Scene;
    var light:DirLight;

    public function new(s3d:Scene, light:DirLight, initialSettings:GraphicsSettings) {
        inst = this;
        this.s3d = s3d;
        this.light = light;
        this.settings = initialSettings;
        applyAll();
    }

    public function applyAll() {
        applyRenderScale();
        applyShadows();
        applyLighting();
    }

    public function applyRenderScale() {
        #if js
        var engine = Engine.getCurrent();
        var win = hxd.Window.getInstance();
        if (engine != null && win != null) {
            var targetW = Math.round(win.width * settings.renderScale);
            var targetH = Math.round(win.height * settings.renderScale);
            engine.resize(targetW, targetH);
        }
        #end
    }

    public function applyShadows() {
        if (light == null) return;
        if (settings.shadowLevel == "Off") {
            light.enableSpecular = false;
        } else {
            light.enableSpecular = true;
        }
    }

    public function applyLighting() {
        if (light == null) return;
        switch (settings.lightingLevel) {
            case "Low":
                light.color.setColor(0xDDD0B0);
            case "Medium":
                light.color.setColor(0xFFE8C2);
            case "High":
                light.color.setColor(0xFFF0D0);
            case "Ultra (RTX/Path)":
                light.color.setColor(0xFFF8E8);
            default:
                light.color.setColor(0xFFE8C2);
        }
    }
}