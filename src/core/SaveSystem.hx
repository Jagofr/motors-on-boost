package core;

import haxe.Json;

typedef PlayerSaveState = {
    var posX:Float;
    var posY:Float;
    var posZ:Float;
    var yaw:Float;
    var forwardSpeed:Float;
}

typedef GraphicsSettings = {
    var textures:String;         // "Off", "Very Low", "Low", "Medium", "High", "Ultra", "Unreal"
    var shadowLevel:String;      // "Off", "Normal", "High", "Ultra", "Dynamic"
    var shadowRes:Int;           // 512, 1024, 2048, 4096
    var lightingLevel:String;    // "Low", "Medium", "High", "Ultra (RTX/Path)"
    var lightingRes:Int;         // 512, 1024, 2048
    var mipmapping:Bool;
    var anisotropic:Int;         // 1, 2, 4, 8, 16
    var aaType:String;           // "None", "FXAA", "TSAA", "SMAA", "MSAA"
    var aaLevel:Int;             // 2, 4, 8
    var modelGeometry:String;    // "Very Low", "Low", "Medium", "High", "Ultra"
    var modelReflections:Bool;
    var reflectionLevel:String;  // "Low", "Medium", "High", "Ultra"
    var renderScale:Float;       // 0.25, 0.334, 0.5, 0.75, 1.0, 2.0, 3.0, 4.0
}

typedef GameSaveData = {
    var hasActiveRun:Bool;
    var playerState:PlayerSaveState;
    var masterVol:Float;
    var musicVol:Float;
    var sfxVol:Float;
    var graphics:GraphicsSettings;
}

class SaveSystem {
    static inline var STORAGE_KEY:String = "mob_motors_on_boost_save_v1";
    static inline var LEGACY_STORAGE_KEY:String = "burnout_overdrive_save_v1";

    public static function getDefaultGraphics():GraphicsSettings {
        return {
            textures: "High",
            shadowLevel: "Normal",
            shadowRes: 1024,
            lightingLevel: "Medium",
            lightingRes: 1024,
            mipmapping: true,
            anisotropic: 4,
            aaType: "FXAA",
            aaLevel: 2,
            modelGeometry: "Medium",
            modelReflections: true,
            reflectionLevel: "Medium",
            renderScale: 1.0
        };
    }

    public static function load():GameSaveData {
        #if js
         try {
            var storage = js.Browser.getLocalStorage();
            var raw = storage.getItem(STORAGE_KEY);
            if (raw == null) {
                raw = storage.getItem(LEGACY_STORAGE_KEY);
            }
            if (raw != null) {
                var data:GameSaveData = Json.parse(raw);
                return data;
            }
        } catch (e:Dynamic) {}
        #end

        return {
            hasActiveRun: false,
            playerState: { posX: 0.0, posY: 0.0, posZ: 0.0, yaw: 1.5707963, forwardSpeed: 0.0 },
            masterVol: 0.8,
            musicVol: 0.7,
            sfxVol: 0.9,
            graphics: getDefaultGraphics()
        };
    }

    public static function save(data:GameSaveData) {
        #if js
        try {
            var raw = Json.stringify(data);
            js.Browser.getLocalStorage().setItem(STORAGE_KEY, raw);
        } catch (e:Dynamic) {}
        #end
    }

    public static function clearActiveRun() {
        var d = load();
        d.hasActiveRun = false;
        save(d);
    }
}