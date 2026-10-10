package save;

import haxe.Json;
import Version;

/**
 * Serialized snapshot representing player vehicle transform and dynamic state mid-race.
 */
typedef PlayerSaveState = {
    /** World space X coordinate position in meters. */
    var posX:Float;

    /** World space Y coordinate position in meters. */
    var posY:Float;

    /** World space Z elevation coordinate in meters. */
    var posZ:Float;

    /** Vehicle chassis yaw rotation angle in radians. */
    var yaw:Float;

    /** Longitudinal velocity in meters per second. */
    var forwardSpeed:Float;
}

/**
 * User hardware quality profile covering rendering buffers, textures, shadows, and anti-aliasing.
 */
typedef GraphicsSettings = {
    /** Texture filtering atlas fidelity tier: "Off", "Very Low", "Low", "Medium", "High", "Ultra", "Unreal". */
    var textures:String;

    /** Shadow projection pass tier: "Off", "Normal", "High", "Ultra", "Dynamic". */
    var shadowLevel:String;

    /** Directional depth buffer resolution in pixels (512, 1024, 2048, 4096). */
    var shadowRes:Int;

    /** Lighting tone mapping and bounce model: "Low", "Medium", "High", "Ultra (RTX/Path)". */
    var lightingLevel:String;

    /** Illumination map resolution in pixels (512, 1024, 2048). */
    var lightingRes:Int;

    /** Trilinear texture downsampling mipmap generation state. */
    var mipmapping:Bool;

    /** Anisotropic texture filtering level (1, 2, 4, 8, 16). */
    var anisotropic:Int;

    /** Edge smoothing shader algorithm: "None", "FXAA", "TSAA", "SMAA", "MSAA". */
    var aaType:String;

    /** Multi-sampling antialiasing multiplier (2, 4, 8). */
    var aaLevel:Int;

    /** Vertex density and mesh level-of-detail: "Very Low", "Low", "Medium", "High", "Ultra". */
    var modelGeometry:String;

    /** Dynamic vehicle shader reflection pass flag. */
    var modelReflections:Bool;

    /** Reflection update frequency tier: "Low", "Medium", "High", "Ultra". */
    var reflectionLevel:String;

    /** Internal 3D scene framebuffer resolution multiplier (0.25 to 4.0). */
    var renderScale:Float;

    /** UI Target resolution preset: "720p (HD)", "1080p (FHD)", "1440p (2K)", "2160p (4K)", "Native / Match Window". */
    var uiResolution:String;
}

/**
 * Root game data record serialized to persistent browser storage.
 */
typedef GameSaveData = {
    /** Save schema version identifier for forward migrations. */
    var ?version:Int;

    /** Application build number at the time of save persistence. */
    var ?buildNumber:Int;

    /** True if an in-progress race run is currently suspended and can be resumed. */
    var hasActiveRun:Bool;

    /** Snapshot of vehicle telemetry and coordinates. */
    var playerState:PlayerSaveState;

    /** Master audio volume level [0.0 - 1.0]. */
    var masterVol:Float;

    /** Music audio volume level [0.0 - 1.0]. */
    var musicVol:Float;

    /** Sound effects audio volume level [0.0 - 1.0]. */
    var sfxVol:Float;

    /** Active graphics hardware configuration profile. */
    var graphics:GraphicsSettings;

    /** Steering sensitivity multiplier in range [0.0, 1.0] (default 1.0). */
    var ?steerSensitivity:Float;
}

/**
 * Client-side persistence and serialization manager utilizing HTML5 `localStorage`.
 * Manages save profile serialization, version migrations, backwards-compatible key reading, and active run status.
 */
class SaveSystem {
    /** Current save schema version identifier for forward migrations. */
    public static inline var SAVE_VERSION:Int = 4;

    /** Primary localStorage storage key for Motors on Boost v4 schema. */
    static inline var STORAGE_KEY_V4:String = "mob_motors_on_boost_save_v4";

    /** Backwards-compatible storage key for v3 schema. */
    static inline var STORAGE_KEY_V3:String = "mob_motors_on_boost_save_v3";

    /** Backwards-compatible storage key for v2 schema. */
    static inline var STORAGE_KEY_V2:String = "mob_motors_on_boost_save_v2";

    /** Backwards-compatible storage key for v1 schema. */
    static inline var STORAGE_KEY_V1:String = "mob_motors_on_boost_save_v1";

    /** Backwards-compatible legacy key for prototype builds. */
    static inline var LEGACY_STORAGE_KEY:String = "burnout_overdrive_save_v1";

    /**
     * Creates and returns the default recommended graphics settings profile.
     *
     * @return Balanced default graphics configuration preset.
     */
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
            renderScale: 1.0,
            uiResolution: "720p (HD)"
        };
    }

    /**
     * Loads saved game data from persistent localStorage with automatic forward migration.
     * If no save is found or an exception occurs, returns a clean default dataset.
     *
     * @return Parsed GameSaveData record or clean defaults.
     */
    public static function load():GameSaveData {
        #if js
        try {
            var storage = js.Browser.getLocalStorage();
            var raw = storage.getItem(STORAGE_KEY_V4);
            var isLegacy = false;

            // Step 1: Fallback reading from v3 key if v4 not found
            if (raw == null) {
                raw = storage.getItem(STORAGE_KEY_V3);
                if (raw != null) isLegacy = true;
            }

            // Step 2: Fallback reading from v2 key if v3 not found
            if (raw == null) {
                raw = storage.getItem(STORAGE_KEY_V2);
                if (raw != null) isLegacy = true;
            }

            // Step 3: Fallback reading from v1 key if v2 not found
            if (raw == null) {
                raw = storage.getItem(STORAGE_KEY_V1);
                if (raw != null) isLegacy = true;
            }

            // Step 4: Fallback reading from prototype key if still not found
            if (raw == null) {
                raw = storage.getItem(LEGACY_STORAGE_KEY);
                if (raw != null) isLegacy = true;
            }

            if (raw != null) {
                var data:GameSaveData = Json.parse(raw);

                // Step 5: Forward migration: ensure uiResolution default
                if (data.graphics != null && data.graphics.uiResolution == null) {
                    data.graphics.uiResolution = "720p (HD)";
                }

                // Step 6: Forward migration: ensure steerSensitivity default
                if (data.steerSensitivity == null || data.steerSensitivity <= 0.0) {
                    data.steerSensitivity = 1.0;
                }

                // Step 7: Schema version migration to v4
                if (data.version == null || data.version < SAVE_VERSION || isLegacy) {
                    data.version = SAVE_VERSION;
                    data.buildNumber = Version.BUILD;
                    save(data); // Commit forward-migrated save record
                }

                return data;
            }
        } catch (e:haxe.Exception) {}
        #end

        return {
            version: SAVE_VERSION,
            buildNumber: Version.BUILD,
            hasActiveRun: false,
            playerState: { posX: 0.0, posY: 0.0, posZ: 0.0, yaw: 1.5707963, forwardSpeed: 0.0 },
            masterVol: 0.8,
            musicVol: 0.7,
            sfxVol: 0.9,
            steerSensitivity: 1.0,
            graphics: getDefaultGraphics()
        };
    }

    /**
     * Serializes and writes game data to browser localStorage with active schema versioning.
     *
     * @param data Game save state to persist.
     */
    public static function save(data:GameSaveData) {
        #if js
        try {
            data.version = SAVE_VERSION;
            data.buildNumber = Version.BUILD;
            if (data.steerSensitivity == null || data.steerSensitivity <= 0.0) {
                data.steerSensitivity = 1.0;
            }

            var raw = Json.stringify(data);
            var storage = js.Browser.getLocalStorage();
            storage.setItem(STORAGE_KEY_V4, raw);
            storage.setItem(STORAGE_KEY_V3, raw); // Backwards compatibility mirror
        } catch (e:haxe.Exception) {}
        #end
    }

    /**
     * Flags the current active run as cleared and commits the change to storage.
     */
    public static function clearActiveRun() {
        var d = load();
        d.hasActiveRun = false;
        save(d);
    }
}