package config;

/**
 * Sky dome shader color palette and geometry configuration.
 *
 * @typedef {Object} SkyboxConfig
 * @property {Float} radius Geodesic dome sphere radius in meters.
 * @property {Int} segments Longitudinal and latitudinal mesh tessellation.
 * @property {Int} topColor Zenith RGB hex color.
 * @property {Int} horizonColor Horizon blend RGB hex color.
 */
typedef SkyboxConfig = {
    var radius:Float;
    var segments:Int;
    var topColor:Int;
    var horizonColor:Int;
}

/**
 * Highway circuit spline geometry, guardrail, and surrounding ground parameters.
 *
 * @typedef {Object} TrackConfig
 * @property {Float} roadWidth Total width of asphalt surface in meters.
 * @property {Float} halfWidth Distance from track centerline to road edge in meters.
 * @property {Float} bedExtraWidth Gravel shoulder slope width outside rails in meters.
 * @property {Float} roadLift Vertical offset separating asphalt from underlying foundation in meters.
 * @property {Float} railHeight Vertical height of Armco barriers in meters.
 * @property {Float} railThickness Horizontal thickness of Armco barriers in meters.
 * @property {Float} wallStickiness Momentum preservation factor during rail contact [0..1].
 * @property {Int} subdivisions Spline interpolation segments between major nodes.
 * @property {Int} lightSpacing Waypoint step interval between overhead streetlights.
 * @property {Array<Array<Float>>} controlNodes Closed-loop spline control nodes [[x, y, z], ...].
 * @property {Float} foundationHalfSpan Half-width/height of static roadbed foundation collider in meters.
 * @property {Float} terrainWidth Visual ambient grass plane width in meters.
 * @property {Float} terrainHeight Visual ambient grass plane length in meters.
 * @property {Float} terrainZ Visual ambient grass elevation offset in meters.
 * @property {Int} terrainColor Diffuse hex color for surrounding circuit ground.
 * @property {Float} asphaltFriction Tire traction scalar on paved asphalt.
 * @property {Float} offroadFriction Tire traction scalar on off-road shoulders.
 */
typedef TrackConfig = {
    var roadWidth:Float;
    var halfWidth:Float;
    var bedExtraWidth:Float;
    var roadLift:Float;
    var railHeight:Float;
    var railThickness:Float;
    var wallStickiness:Float;
    var subdivisions:Int;
    var lightSpacing:Int;
    var controlNodes:Array<Array<Float>>;
    var foundationHalfSpan:Float;
    var terrainWidth:Float;
    var terrainHeight:Float;
    var terrainZ:Float;
    var terrainColor:Int;
    var asphaltFriction:Float;
    var offroadFriction:Float;
}

/**
 * Open proving grounds terrain features, surface friction, and arena boundary configuration.
 *
 * @typedef {Object} SandboxConfig
 * @property {Float} halfSpan Arena half-width/length in meters.
 * @property {Float} wallLimit Hard boundary wall clamp limit inside terrain edges in meters.
 * @property {Float} skidpadRadius Flat central concrete skidpad radius in meters.
 * @property {Float} hillApexZ Peak height of the apex mountain feature in meters.
 * @property {Float} rampCrestZ Peak elevation of the smooth launch ramp in meters.
 * @property {Int} gridDivs Terrain mesh grid tessellation count per axis.
 * @property {Float} skidpadFriction Tire friction multiplier on concrete skidpad.
 * @property {Float} concreteFeatureFriction Tire friction multiplier on ramps and banked bowls.
 * @property {Float} turfFriction Tire friction multiplier on grassy/off-road terrain.
 */
typedef SandboxConfig = {
    var halfSpan:Float;
    var wallLimit:Float;
    var skidpadRadius:Float;
    var hillApexZ:Float;
    var rampCrestZ:Float;
    var gridDivs:Int;
    var skidpadFriction:Float;
    var concreteFeatureFriction:Float;
    var turfFriction:Float;
}

/**
 * Highway traffic AI spawning, spacing, and collision parameters.
 *
 * @typedef {Object} TrafficConfig
 * @property {Float} activeHalfWidth Usable paved track half-width inside Armco rails in meters.
 * @property {Float} playerRadius Player collision bounding cylinder radius in meters.
 * @property {Float} trafficRadius Civilian vehicle collision radius in meters.
 * @property {Float} collisionSpeedRetention Player speed retention factor after traffic impact [0..1].
 * @property {Float} collisionTrauma Base camera trauma added on vehicle collision.
 * @property {Float} defaultSpacingMultiplier Longitudinal spacing safety factor between cars.
 * @property {Array<Int>} paintPalette Array of RGB body paint colors cycled across spawned vehicles.
 */
typedef TrafficConfig = {
    var activeHalfWidth:Float;
    var playerRadius:Float;
    var trafficRadius:Float;
    var collisionSpeedRetention:Float;
    var collisionTrauma:Float;
    var defaultSpacingMultiplier:Float;
    var paintPalette:Array<Int>;
}

/**
 * Factory supplying default environment, track, sandbox, and traffic configurations.
 *
 * @class WorldConfig
 * @module config/WorldConfig
 */
class WorldConfig {
    /**
     * Returns default geodesic sky dome parameters.
     *
     * @returns {SkyboxConfig}
     */
    public static function getDefaultSkybox():SkyboxConfig {
        return {
            radius: 1400.0,
            segments: 28,
            topColor: 0x1052B8,
            horizonColor: 0x7AC2F2
        };
    }

    /**
     * Returns default closed highway circuit track configuration.
     *
     * @returns {TrackConfig}
     */
    public static function getDefaultTrack():TrackConfig {
        return {
            roadWidth: 20.0,
            halfWidth: 10.0,
            bedExtraWidth: 4.0,
            roadLift: 0.06,
            railHeight: 0.65,
            railThickness: 0.25,
            wallStickiness: 0.94,
            subdivisions: 24,
            lightSpacing: 6,
            controlNodes: [
                [0.0,    0.0,   0.0],
                [0.0,    85.0,  0.0],
                [30.0,   170.0, 1.5],
                [90.0,   240.0, 3.0],
                [170.0,  260.0, 3.0],
                [250.0,  215.0, 1.5],
                [280.0,  135.0, 0.0],
                [255.0,  45.0, -1.0],
                [175.0, -25.0, -1.0],
                [110.0,  10.0,  0.0],
                [60.0,  -40.0,  0.0],
                [10.0,  -60.0,  0.0]
            ],
            foundationHalfSpan: 500.0,
            terrainWidth: 800.0,
            terrainHeight: 800.0,
            terrainZ: -2.5,
            terrainColor: 0x111418,
            asphaltFriction: 1.0,
            offroadFriction: 0.50
        };
    }

    /**
     * Returns default open sandbox proving grounds configuration.
     *
     * @returns {SandboxConfig}
     */
    public static function getDefaultSandbox():SandboxConfig {
        return {
            halfSpan: 200.0,
            wallLimit: 195.0,
            skidpadRadius: 35.0,
            hillApexZ: 12.5,
            rampCrestZ: 3.8,
            gridDivs: 120,
            skidpadFriction: 1.05,
            concreteFeatureFriction: 1.02,
            turfFriction: 0.78
        };
    }

    /**
     * Returns default autonomous highway traffic simulation settings.
     *
     * @returns {TrafficConfig}
     */
    public static function getDefaultTraffic():TrafficConfig {
        return {
            activeHalfWidth: 9.7,
            playerRadius: 1.6,
            trafficRadius: 1.5,
            collisionSpeedRetention: 0.75,
            collisionTrauma: 0.35,
            defaultSpacingMultiplier: 1.0,
            paintPalette: [0xdddddd, 0x2244aa, 0xccaa22, 0x33aa55, 0x666677, 0xaa3333]
        };
    }
}
