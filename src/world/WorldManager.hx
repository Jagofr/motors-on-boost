package world;

import camera.ChaseCamera;
import config.GameConfig;
import config.GameConfig.GameConfigData;
import config.WorldConfig;
import entities.CarMesh;
import entities.RemoteCarActor;
import entities.TrafficSystem;
import graphics.PostProcessRenderer;
import graphics.WebGpuRenderer;
import math.Vec3;
import graphics.SceneGraph.DirLightNode;
import graphics.SceneGraph.Scene3D;
import input.InputController;
import net.NetworkProtocol.NetCarState;
import physics.CarConfig;
import physics.CarPhysics;

/**
 * Playable environment modes selectable in game or tests.
 *
 * @enum {Int} MapMode
 * @module world/WorldManager
 */
@:keep
enum MapMode {
    /** Closed highway loop featuring multi-lane traffic and continuous guardrails. */
    Circuit;
    /** Open terrain proving grounds featuring launch ramp, banked bowl, moguls, and mountain peak. */
    Sandbox;
}

/**
 * Dedicated 3D scene orchestrator encapsulating lighting rig, skybox dome, active track or sandbox
 * terrain (`IGroundProvider`), Oimo physics world, traffic simulation, chase camera, and player mesh.
 *
 * @class WorldManager
 * @module world/WorldManager
 */
class WorldManager {
    /** Active 3D scene graph root. */
    public var s3d:Scene3D;

    /** Top-level runtime configuration profile. */
    public var config:GameConfigData;

    /** Currently loaded map environment mode. */
    public var currentMapMode:MapMode = Circuit;

    /** Geodesic sky dome synchronized to active camera eye position. */
    public var skybox:Skybox;

    /** Primary warm solar directional shadow-casting light source. */
    public var dirLight:DirLightNode;

    /** Secondary sky fill light softening sharp shadow boundaries. */
    public var fillLight:DirLightNode;

    /** Post-processing forward renderer providing speed-reactive radial blur. */
    public var postRenderer:PostProcessRenderer;
    public var gpuRenderer:Null<WebGpuRenderer> = null;

    /** Highway circuit world and collider provider. */
    public var track:Track;

    /** Open sandbox proving grounds world and collider provider. */
    public var sandboxMap:SandboxMap;

    /** Highway autonomous traffic AI fleet manager. */
    public var traffic:TrafficSystem;

    /** Player Oimo-backed vehicle physics simulation. */
    public var carPhysics:CarPhysics;

    /** Player vehicle procedural composite 3D mesh. */
    public var playerMesh:CarMesh;

    /** Spring-damped third-person chase camera controller. */
    public var chaseCam:ChaseCamera;

    /** Remote player vehicle visual actors keyed by network peerId. */
    public var remoteCars:Map<String, RemoteCarActor> = new Map();

    /** Toggle allowing multiplayer rooms to suppress non-synchronized AI traffic. */
    public var trafficEnabled:Bool = true;

    /** Integrated front tire longitudinal spin angle in radians. */
    private var wheelSpinAngle:Float = 0.0;

    /** Integrated rear tire spin angle including power-oversteer slip in radians. */
    private var rearWheelSpinAngle:Float = 0.0;

    /** Continuous showcase turntable angle in radians. */
    private var showcaseAngle:Float = 0.6;

    /** Selected player car archetype ID and custom paint color hex. */
    public var selectedCarId:String = CarConfig.ID_RACE_AWD;
    public var selectedPaintHex:Int = 0xE64A19;

    /**
     * Constructs a 3D WorldManager bound to the target Heaps 3D scene.
     *
     * @param {Scene} s3d Target 3D scene graph.
     * @param {Null<GameConfigData>} [config] Optional configuration bundle overrides.
     */
    public function new(s3d:Scene3D, ?config:GameConfigData) {
        this.s3d = s3d;
        this.config = config != null ? config : GameConfig.getDefault();
        initializeWorld();
    }

    /**
     * Builds 3D lighting, camera/post-processing renderer, skybox, maps, traffic, physics, and player car.
     *
     * @returns {Void}
     */
    private function initializeWorld():Void {
        carPhysics = new CarPhysics(0.0, 0.0, 0.0, null, config.physicsWorld);
        chaseCam = new ChaseCamera(s3d.camera, 0.0, -10.0, 4.0);

        postRenderer = new PostProcessRenderer();
                s3d.camera.zFar = config.camera.farPlane;

        skybox = new Skybox(s3d, WorldConfig.getDefaultSkybox());

        initLighting();

        track = new Track(s3d, WorldConfig.getDefaultTrack());
        sandboxMap = new SandboxMap(s3d, WorldConfig.getDefaultSandbox());
        sandboxMap.visible = false;

        traffic = new TrafficSystem(track.waypoints, s3d, WorldConfig.getDefaultTraffic());
        playerMesh = new CarMesh(s3d);

        loadMap(Circuit);
        resetCarToStartLine();
    }

    /**
     * Configures solar directional light, fill hemisphere light, and scene ambient irradiance.
     *
     * @returns {Void}
     */
    private function initLighting():Void {
        var lc = config.lighting;
        var sunDir = new Vec3(lc.sunDirX, lc.sunDirY, lc.sunDirZ);
        sunDir.normalize();
        dirLight = new DirLightNode(sunDir, s3d);
        dirLight.setPosition(lc.sunX, lc.sunY, lc.sunZ);
        dirLight.color.setColor(0xFFF2D9);

        var fillDir = new Vec3(0.55, -0.78, 0.45);
        fillDir.normalize();
        fillLight = new DirLightNode(fillDir, s3d);
        fillLight.color.setColor(0x788B9E);
        fillLight.enableSpecular = false;
    }

    /**
     * Returns the currently active map surface provider (`Track` or `SandboxMap`).
     *
     * @returns {IGroundProvider} Active terrain elevation, friction, and boundary interface.
     */
    public function getActiveGround():IGroundProvider {
        return currentMapMode == Sandbox ? cast sandboxMap : cast track;
    }

    /**
     * Switches active map geometry, Oimo static physics colliders, and traffic visibility.
     *
     * @param {MapMode} mode Target environment mode.
     * @returns {Void}
     */
    public function loadMap(mode:MapMode):Void {
        // Polymorphically unregister previous map physics colliders
        var prevGround = getActiveGround();
        if (prevGround != null && carPhysics != null) {
            prevGround.unregisterPhysicsColliders(carPhysics.physicsWorld);
        }

        currentMapMode = mode;
        if (skybox != null) skybox.visible = true;

        var nextGround = getActiveGround();
        if (nextGround != null && carPhysics != null) {
            nextGround.registerPhysicsColliders(carPhysics.physicsWorld);
        }

        if (mode == Circuit) {
            if (track != null) track.visible = true;
            if (sandboxMap != null) sandboxMap.visible = false;
            if (traffic != null) traffic.visible = true;
            if (gpuRenderer != null && gpuRenderer.initialized && track != null) {
                track.syncGpuCompute(gpuRenderer);
            }
        } else {
            if (track != null) track.visible = false;
            if (sandboxMap != null) sandboxMap.visible = true;
            if (traffic != null) traffic.visible = false;
            if (gpuRenderer != null && gpuRenderer.initialized) {
                gpuRenderer.clearTrack();
            }
        }
    }

    /**
     * Reloads the currently active map back to clean starting grid / staging state.
     *
     * @returns {Void}
     */
    public function reloadCurrentMap():Void {
        if (currentMapMode == Sandbox) {
            loadMap(Sandbox);
            resetCarToSandboxCenter();
        } else {
            loadMap(Circuit);
            resetCarToStartLine();
            if (traffic != null) traffic.resetPositions();
        }
    }

    /**
     * Resets the player car onto the Highway Circuit starting grid line.
     *
     * @returns {Void}
     */
    public function resetCarToStartLine():Void {
        carPhysics.resetState(0.0, 0.0, Track.ROAD_LIFT, 0.0);
        syncBodyTransformOnly();
    }

    /**
     * Resets the player car onto the Sandbox Proving Grounds central skidpad.
     *
     * @returns {Void}
     */
    public function resetCarToSandboxCenter():Void {
        carPhysics.resetState(0.0, 0.0, 0.05, 0.0);
        syncBodyTransformOnly();
    }

    /**
     * Synchronizes skybox centering with camera position on every frame.
     *
     * @returns {Void}
     */
    public function syncSkybox():Void {
        if (skybox != null && s3d != null && s3d.camera != null) {
            skybox.syncCamera(s3d.camera.pos);
        }
    }

    /**
     * Resets post-process radial blur intensity to zero when paused or in menus.
     *
     * @returns {Void}
     */
    public function clearPostEffects():Void {
        if (postRenderer != null) {
            postRenderer.blurShader.blurIntensity = 0.0;
        }
    }

    /**
     * Orbits the 3D camera smoothly around the player vehicle for splash/menu/credits views.
     *
     * @param {Float} dt Elapsed frame duration in seconds.
     * @returns {Void}
     */
    public function updateShowcaseCamera(dt:Float):Void {
        clearPostEffects();
        showcaseAngle += 0.35 * dt;
        var camDist = 11.0;
        s3d.camera.pos.set(
            carPhysics.pos.x + Math.sin(showcaseAngle) * camDist,
            carPhysics.pos.y - Math.cos(showcaseAngle) * camDist,
            carPhysics.pos.z + 4.2
        );
        s3d.camera.target.set(carPhysics.pos.x, carPhysics.pos.y, carPhysics.pos.z + 1.2);
    }

    /**
     * Advances physics, traffic AI, camera spring-arm tracking, radial motion blur, and mesh animations.
     *
     * @param {Float} dt Elapsed frame duration in seconds.
     * @param {InputController} input Active driving input controller.
     * @returns {Int} Rounded vehicle speed in km/h for telemetry display.
     */
    public function updateDriving(dt:Float, input:InputController):Int {
        var wasDrifting = carPhysics.isDrifting;

        if (currentMapMode == Circuit) {
            carPhysics.update(dt, input, track != null ? track.waypoints : null, track);
            if (traffic != null && trafficEnabled) traffic.update(dt, carPhysics, chaseCam);
        } else {
            carPhysics.update(dt, input, null, sandboxMap);
        }

        if (!wasDrifting && carPhysics.isDrifting) chaseCam.addTrauma(0.35);
        if (input.boost && carPhysics.forwardSpeed > 20.0) chaseCam.addTrauma(0.12 * dt * 60.0);

        var kmh = Math.round(Math.abs(carPhysics.forwardSpeed) * 3.6);
        updateSpeedBlur(kmh, input.boost);
        syncPlayerVisuals(dt, input);
        chaseCam.update(dt, carPhysics, carPhysics.isBoosting);

        return kmh;
    }

    /**
     * Scales speed-dependent screen-space radial motion blur intensity.
     *
     * @param {Int} kmh Current vehicle speed in km/h.
     * @param {Bool} isBoosting True while nitrous boost is active.
     * @returns {Void}
     */
    private function updateSpeedBlur(kmh:Int, isBoosting:Bool):Void {
        if (postRenderer == null) return;
        var thresh = config.camera.radialBlurThresholdKmh;
        var blurIntensity = 0.0;
        if (kmh > thresh) {
            blurIntensity = Math.min(0.065, ((kmh - thresh) / 180.0) * 0.055);
        }
        if (isBoosting && kmh > 70) {
            blurIntensity = Math.min(0.08, blurIntensity + 0.025);
        }
        postRenderer.blurShader.blurIntensity = blurIntensity;
    }

    /**
     * Applies chassis world position/Euler orientation and updates four-wheel transforms.
     *
     * @param {Float} dt Elapsed frame time in seconds.
     * @param {InputController} input Active steering rack input state.
     * @returns {Void}
     */
    private function syncPlayerVisuals(dt:Float, input:InputController):Void {
        playerMesh.x = carPhysics.pos.x;
        playerMesh.y = carPhysics.pos.y;
        playerMesh.z = carPhysics.pos.z;
        playerMesh.setRotation(carPhysics.pitch, carPhysics.roll, 0);
        playerMesh.rotate(0, 0, -(carPhysics.yaw + carPhysics.driftAngle));

        wheelSpinAngle += (carPhysics.forwardSpeed * dt) / CarMesh.TIRE_RADIUS;
        rearWheelSpinAngle += ((carPhysics.forwardSpeed / CarMesh.TIRE_RADIUS) + carPhysics.wheelSpinVelocity[2]) * dt;
        var currentSteer = -input.steer * 0.55;
        var restLen = carPhysics.config.suspension.restLength;

        if (playerMesh.wheels.length >= 4) {
            playerMesh.updateWheelTransform(0, restLen - carPhysics.suspLength[0], wheelSpinAngle, currentSteer);
            playerMesh.updateWheelTransform(1, restLen - carPhysics.suspLength[1], wheelSpinAngle, currentSteer);
            playerMesh.updateWheelTransform(2, restLen - carPhysics.suspLength[2], rearWheelSpinAngle, 0.0);
            playerMesh.updateWheelTransform(3, restLen - carPhysics.suspLength[3], rearWheelSpinAngle, 0.0);
        }
    }

    /**
     * Immediately places player car and visual mesh at a specific grid coordinate (e.g. multiplayer spawn).
     */
    public function spawnPlayerAt(x:Float, y:Float, z:Float, yaw:Float):Void {
        if (carPhysics == null) return;
        carPhysics.resetState(x, y, z, yaw);
        syncBodyTransformOnly();
    }

    /**
     * Immediately places visual mesh at current physics transform after hard state reset.
     *
     * @returns {Void}
     */
    private function syncBodyTransformOnly():Void {
        if (playerMesh == null || carPhysics == null) return;
        playerMesh.x = carPhysics.pos.x;
        playerMesh.y = carPhysics.pos.y;
        playerMesh.z = carPhysics.pos.z;
        playerMesh.setRotation(carPhysics.pitch, carPhysics.roll, 0);
        playerMesh.rotate(0, 0, -carPhysics.yaw);
    }

    /**
     * Sets the local player vehicle's primary body paint color (used for multiplayer slot differentiation).
     */
    public function setPlayerPaintColor(colorHex:Int):Void {
        if (playerMesh == null) return;
        playerMesh.setPaintColor(colorHex);
    }

    /**
     * Applies the chosen vehicle archetype (`race_awd`, `hatch_fwd`, `coupe_rwd`) and paint color
     * to both physics solver config and 3D procedural CarMesh.
     */
    public function applyPlayerVehicle(carId:String, ?paintHex:Null<Int>):Void {
        var meta = CarConfig.getPresetMeta(carId);
        selectedCarId = meta.id;
        selectedPaintHex = paintHex != null ? paintHex : meta.defaultColorHex;
        if (carPhysics != null) {
            carPhysics.setConfig(CarConfig.getPresetConfig(selectedCarId));
        }
        if (playerMesh != null) {
            playerMesh.applyVisualPreset(selectedCarId, selectedPaintHex);
        }
    }

    /**
     * Enables or hides ambient AI traffic vehicles (disabled during peer-to-peer multiplayer matches).
     */
    public function setTrafficEnabled(enabled:Bool):Void {
        trafficEnabled = enabled;
        if (traffic != null && traffic.trafficList != null) {
            for (c in traffic.trafficList) {
                if (c.carMesh != null) c.carMesh.visible = (enabled && currentMapMode == Circuit);
            }
        }
    }

    /**
     * Synchronizes 3D remote player vehicles from Host-validated state snapshots and applies
     * gentle bumper separation when vehicles make physical contact.
     */
    public function syncRemoteCars(dt:Float, states:Map<String, NetCarState>):Void {
        if (states == null) return;

        // Remove stale peers
        var toRemove:Array<String> = [];
        for (pid in remoteCars.keys()) {
            if (!states.exists(pid)) toRemove.push(pid);
        }
        for (pid in toRemove) {
            var old = remoteCars.get(pid);
            if (old != null) old.destroy();
            remoteCars.remove(pid);
        }

        // Create/update active peers
        for (pid in states.keys()) {
            var st = states.get(pid);
            var actor = remoteCars.get(pid);
            if (actor == null) {
                actor = new RemoteCarActor(s3d, st.peerId, st.name, st.colorHex);
                remoteCars.set(pid, actor);
            }
            actor.applyTargetState(st);
            actor.update(dt);

            // Soft lateral/longitudinal separation on vehicle contact
            if (carPhysics != null) {
                var dx = carPhysics.pos.x - actor.currentX;
                var dy = carPhysics.pos.y - actor.currentY;
                var dz = Math.abs(carPhysics.pos.z - actor.currentZ);
                var distSq = dx * dx + dy * dy;
                var minSep = 2.65;
                if (dz < 1.8 && distSq > 0.0001 && distSq < minSep * minSep) {
                    var dist = Math.sqrt(distSq);
                    var overlap = minSep - dist;
                    carPhysics.pos.x += (dx / dist) * overlap * 0.55;
                    carPhysics.pos.y += (dy / dist) * overlap * 0.55;
                    carPhysics.forwardSpeed *= 0.94;
                    carPhysics.syncToOimoBody();
                    chaseCam.addTrauma(0.18);
                }
            }
        }
    }

    /**
     * Removes all remote player 3D meshes and restores default local sports-orange paint.
     */
    public function clearRemoteCars():Void {
        for (pid in remoteCars.keys()) {
            var actor = remoteCars.get(pid);
            if (actor != null) actor.destroy();
        }
        remoteCars.clear();
        setPlayerPaintColor(selectedPaintHex);
    }

    /** Binds the active WebGPU renderer and compiles/dispatches initial track geometry. */
    public function attachGpuRenderer(renderer:WebGpuRenderer):Void {
        gpuRenderer = renderer;
        if (renderer == null || !renderer.initialized) return;
        if (currentMapMode == Circuit && track != null) {
            track.syncGpuCompute(renderer);
        } else {
            renderer.clearTrack();
        }
    }

    /** Encodes and presents the active 3D frame via WebGPU. */
    public function renderGpuFrame():Void {
        if (gpuRenderer == null || !gpuRenderer.initialized || s3d == null) return;
        var topHex = skybox != null ? skybox.skyShader.topHex : 0x1052B8;
        var horHex = skybox != null ? skybox.skyShader.horizonHex : 0x7AC2F2;
        var gndHex = skybox != null ? skybox.skyShader.groundHex : 0x141A24;
        var trackOn = (currentMapMode == Circuit && track != null);
        gpuRenderer.renderFrame(s3d, topHex, horHex, gndHex, trackOn, postRenderer);
    }
}