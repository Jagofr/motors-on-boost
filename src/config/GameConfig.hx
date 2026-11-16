package config;

/**
 * Virtual UI layout resolution settings for High-DPI AutoZoom scaling.
 *
 * @typedef {Object} VirtualResolutionConfig
 * @property {Int} baseWidth Target virtual canvas width in logical pixels.
 * @property {Int} baseHeight Target virtual canvas height in logical pixels.
 */
typedef VirtualResolutionConfig = {
    var baseWidth:Int;
    var baseHeight:Int;
}

/**
 * Boot sequence timings, branding asset paths, and legal disclaimer copy.
 *
 * @typedef {Object} IntroConfig
 * @property {Float} studioDuration Total publisher splash display duration in seconds.
 * @property {Float} studioFadeDuration Fade-in/out duration for publisher splash in seconds.
 * @property {Float} engineDuration Total engine attribution display duration in seconds.
 * @property {Float} engineFadeDuration Fade-in/out duration for engine attribution in seconds.
 * @property {Float} disclaimerMinDuration Minimum locked disclaimer duration in seconds.
 * @property {Float} disclaimerFadeOutDuration Cross-fade out duration for disclaimer in seconds.
 * @property {Float} showcaseFadeDuration Transition curtain fade duration entering 3D showcase.
 * @property {String} studioSplashPath Relative web URL to publisher logo bitmap.
 * @property {String} engineSplashPath Relative web URL to engine background artwork.
 * @property {Array<String>} engineLogoPaths Relative web URLs to engine/tech badge logos.
 * @property {Array<String>} touchIconPaths Resource paths for touch HUD icons to warm in memory.
 */
typedef IntroConfig = {
    var studioDuration:Float;
    var studioFadeDuration:Float;
    var engineDuration:Float;
    var engineFadeDuration:Float;
    var disclaimerMinDuration:Float;
    var disclaimerFadeOutDuration:Float;
    var showcaseFadeDuration:Float;
    var studioSplashPath:String;
    var engineSplashPath:String;
    var engineLogoPaths:Array<String>;
    var touchIconPaths:Array<String>;
}

/**
 * Scene illumination and directional shadow rig parameters.
 *
 * @typedef {Object} LightingConfig
 * @property {Float} sunX Solar directional light X coordinate.
 * @property {Float} sunY Solar directional light Y coordinate.
 * @property {Float} sunZ Solar directional light Z coordinate.
 * @property {Float} sunDirX Solar beam direction X component.
 * @property {Float} sunDirY Solar beam direction Y component.
 * @property {Float} sunDirZ Solar beam direction Z component.
 * @property {Array<Float>} sunColor RGB color channels for primary solar light.
 * @property {Float} fillDirX Secondary hemisphere fill direction X component.
 * @property {Float} fillDirY Secondary hemisphere fill direction Y component.
 * @property {Float} fillDirZ Secondary hemisphere fill direction Z component.
 * @property {Array<Float>} fillColor RGB color channels for secondary fill light.
 * @property {Array<Float>} ambientColor RGB global ambient irradiance.
 */
typedef LightingConfig = {
    var sunX:Float;
    var sunY:Float;
    var sunZ:Float;
    var sunDirX:Float;
    var sunDirY:Float;
    var sunDirZ:Float;
    var sunColor:Array<Float>;
    var fillDirX:Float;
    var fillDirY:Float;
    var fillDirZ:Float;
    var fillColor:Array<Float>;
    var ambientColor:Array<Float>;
}

/**
 * Camera frustum, showcase orbit, and speed-reactive post-process settings.
 *
 * @typedef {Object} CameraRenderConfig
 * @property {Float} farPlane Camera zFar clip plane distance in meters.
 * @property {Float} baseFov Base vertical field of view in degrees.
 * @property {Float} radialBlurThresholdKmh Speed threshold where radial blur activates (km/h).
 * @property {Float} radialBlurMaxKmh Speed where radial blur reaches maximum intensity (km/h).
 * @property {Float} radialBlurMaxIntensity Maximum radial blur shader intensity [0..1].
 * @property {Float} showcaseOrbitRadius Camera orbit distance around player vehicle in menus.
 * @property {Float} showcaseOrbitSpeed Angular showcase orbit speed in rad/s.
 * @property {Float} showcaseOrbitHeight Camera elevation offset during menu showcase.
 * @property {Float} showcaseTargetHeight Look-at target elevation offset during menu showcase.
 */
typedef CameraRenderConfig = {
    var farPlane:Float;
    var baseFov:Float;
    var radialBlurThresholdKmh:Float;
    var radialBlurMaxKmh:Float;
    var radialBlurMaxIntensity:Float;
    var showcaseOrbitRadius:Float;
    var showcaseOrbitSpeed:Float;
    var showcaseOrbitHeight:Float;
    var showcaseTargetHeight:Float;
}

/**
 * Simulation clock and rigid-body world parameters.
 *
 * @typedef {Object} PhysicsWorldConfig
 * @property {Float} gravityZ World vertical gravity acceleration in m/s^2 (negative = down).
 * @property {Float} fixedStep Fixed step size hint in seconds.
 * @property {Float} maxDt Maximum clamped delta time per frame to avoid tunneling.
 */
typedef PhysicsWorldConfig = {
    var gravityZ:Float;
    var fixedStep:Float;
    var maxDt:Float;
}

/**
 * Steering rack filtering and analog deadzone parameters.
 *
 * @typedef {Object} InputConfig
 * @property {Float} steerSpeed Digital turn-in slew rate per second.
 * @property {Float} returnSpeed Digital center-return slew rate per second.
 * @property {Float} gamepadDeadzone Normalized stick drift deadzone threshold [0..1].
 * @property {Float} defaultSteerSensitivity Default steering sensitivity multiplier [0..1].
 */
typedef InputConfig = {
    var steerSpeed:Float;
    var returnSpeed:Float;
    var gamepadDeadzone:Float;
    var defaultSteerSensitivity:Float;
}

/**
 * Procedural Web Audio synthesizer configuration.
 *
 * @typedef {Object} AudioConfig
 * @property {Float} defaultMaster Default master volume [0..1].
 * @property {Float} defaultMusic Default music channel volume [0..1].
 * @property {Float} defaultSfx Default sound effects channel volume [0..1].
 * @property {Float} defaultBeepFreq Default UI cue tone frequency in Hz.
 * @property {Float} defaultBeepDuration Default UI cue tone duration in seconds.
 * @property {Float} beepGainScale Peak gain scalar applied to UI synthesis tones.
 */
typedef AudioConfig = {
    var defaultMaster:Float;
    var defaultMusic:Float;
    var defaultSfx:Float;
    var defaultBeepFreq:Float;
    var defaultBeepDuration:Float;
    var beepGainScale:Float;
}

/**
 * Root immutable-by-convention application configuration bundle.
 *
 * @typedef {Object} GameConfigData
 * @property {VirtualResolutionConfig} resolution Virtual UI sizing rule.
 * @property {IntroConfig} intro Boot splash & background preloader configuration.
 * @property {LightingConfig} lighting 3D scene light rig.
 * @property {CameraRenderConfig} camera Frustum, post-process, and showcase orbit rules.
 * @property {PhysicsWorldConfig} physicsWorld World gravity and frame step clamping.
 * @property {InputConfig} input Steering filter & deadzone settings.
 * @property {AudioConfig} audio Procedural Web Audio defaults.
 */
typedef GameConfigData = {
    var resolution:VirtualResolutionConfig;
    var intro:IntroConfig;
    var lighting:LightingConfig;
    var camera:CameraRenderConfig;
    var physicsWorld:PhysicsWorldConfig;
    var input:InputConfig;
    var audio:AudioConfig;
}

/**
 * Factory and defaults repository for core engine configuration profiles.
 *
 * @class GameConfig
 * @module config/GameConfig
 */
class GameConfig {
    /**
     * Returns the default production configuration profile for M.O.B.
     *
     * @returns {GameConfigData} Populated configuration structure with baseline defaults.
     */
    public static function getDefault():GameConfigData {
        return {
            resolution: {
                baseWidth: 1280,
                baseHeight: 720
            },
            intro: {
                studioDuration: 3.0,
                studioFadeDuration: 0.75,
                engineDuration: 3.0,
                engineFadeDuration: 0.75,
                disclaimerMinDuration: 5.5,
                disclaimerFadeOutDuration: 1.0,
                showcaseFadeDuration: 1.2,
                studioSplashPath: "intro/jagofr-rvl-splash.webp",
                engineSplashPath: "intro/heaps-haxe-splash.webp",
                engineLogoPaths: [
                    "intro/icons/logo_heaps.webp",
                    "intro/icons/logo_haxe.webp",
                    "intro/icons/logo_webgl.webp"
                ],
                touchIconPaths: [
                    "icons/burn.png",
                    "icons/gas-pedal.png",
                    "icons/brake.png",
                    "icons/hand-brake.png"
                ]
            },
            lighting: {
                sunX: 350.0,
                sunY: -250.0,
                sunZ: 140.0,
                sunDirX: -0.55,
                sunDirY: 0.78,
                sunDirZ: -0.32,
                sunColor: [1.0, 0.96, 0.90],
                fillDirX: 0.45,
                fillDirY: -0.55,
                fillDirZ: -0.45,
                fillColor: [0.42, 0.50, 0.65],
                ambientColor: [0.30, 0.35, 0.44]
            },
            camera: {
                farPlane: 1500.0,
                baseFov: 65.0,
                radialBlurThresholdKmh: 140.0,
                radialBlurMaxKmh: 310.0,
                radialBlurMaxIntensity: 0.045,
                showcaseOrbitRadius: 9.5,
                showcaseOrbitSpeed: 0.28,
                showcaseOrbitHeight: 3.2,
                showcaseTargetHeight: 0.8
            },
            physicsWorld: {
                gravityZ: -9.81,
                fixedStep: 1.0 / 60.0,
                maxDt: 0.05
            },
            input: {
                steerSpeed: 4.2,
                returnSpeed: 6.5,
                gamepadDeadzone: 0.12,
                defaultSteerSensitivity: 1.0
            },
            audio: {
                defaultMaster: 0.8,
                defaultMusic: 0.7,
                defaultSfx: 0.9,
                defaultBeepFreq: 440.0,
                defaultBeepDuration: 0.06,
                beepGainScale: 0.15
            }
        };
    }
}
