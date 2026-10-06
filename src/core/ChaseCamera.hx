package core;

import h3d.Camera;
import h3d.Vector;
import physics.CarPhysics;

class ChaseCamera {
    var cam:Camera;

    var currentPos:Vector = new Vector();
    var currentTarget:Vector = new Vector();

    static inline var BASE_DISTANCE:Float = 9.2;
    static inline var BASE_HEIGHT:Float = 3.4;
    static inline var LOOK_AHEAD_DIST:Float = 6.0;
    static inline var LOOK_AHEAD_HEIGHT:Float = 1.0;

    static inline var BASE_FOV:Float = 52.0;
    static inline var MAX_FOV_KICK:Float = 22.0;

    public var trauma:Float = 0.0;

    public function new(camera:Camera, startX:Float = 0.0, startY:Float = -10.0, startZ:Float = 4.0) {
        this.cam = camera;
        this.currentPos.set(startX, startY, startZ);
        this.currentTarget.set(startX, startY + 10.0, 1.0);

        cam.pos.load(currentPos);
        cam.target.load(currentTarget);
        cam.fovY = BASE_FOV;
    }

    public function addTrauma(amount:Float) {
        trauma = Math.min(1.0, trauma + amount);
    }

    public function update(dt:Float, carPhysics:CarPhysics, isNitroActive:Bool) {
        var speedRatio = Math.min(1.0, Math.abs(carPhysics.forwardSpeed) / 75.0);

        var targetFov = BASE_FOV + (speedRatio * MAX_FOV_KICK);
        if (isNitroActive) targetFov += 5.0;
        cam.fovY += (targetFov - cam.fovY) * Math.min(1.0, 6.0 * dt);

        var effectiveYaw = carPhysics.yaw + (carPhysics.driftAngle * 0.45);
        var fwdX = -Math.sin(effectiveYaw);
        var fwdY =  Math.cos(effectiveYaw);

        var dist = BASE_DISTANCE + (speedRatio * 1.8);
        var height = BASE_HEIGHT + (speedRatio * 0.4);

        var targetCamX = carPhysics.pos.x - (fwdX * dist);
        var targetCamY = carPhysics.pos.y - (fwdY * dist);
        var targetCamZ = carPhysics.pos.z + height;

        var targetLookX = carPhysics.pos.x + (fwdX * LOOK_AHEAD_DIST);
        var targetLookY = carPhysics.pos.y + (fwdY * LOOK_AHEAD_DIST);
        var targetLookZ = carPhysics.pos.z + LOOK_AHEAD_HEIGHT;

        var posLerp = Math.min(1.0, 8.5 * dt);
        var lookLerp = Math.min(1.0, 12.0 * dt);

        currentPos.x += (targetCamX - currentPos.x) * posLerp;
        currentPos.y += (targetCamY - currentPos.y) * posLerp;
        currentPos.z += (targetCamZ - currentPos.z) * posLerp;

        currentTarget.x += (targetLookX - currentTarget.x) * lookLerp;
        currentTarget.y += (targetLookY - currentTarget.y) * lookLerp;
        currentTarget.z += (targetLookZ - currentTarget.z) * lookLerp;

        var shakeX = 0.0;
        var shakeY = 0.0;
        var shakeZ = 0.0;

        if (trauma > 0.001) {
            var shakeStrength = trauma * trauma;
            var t = hxd.Timer.lastTimeStamp * 45.0;

            shakeX = Math.sin(t * 1.3) * 0.28 * shakeStrength;
            shakeY = Math.cos(t * 1.7) * 0.28 * shakeStrength;
            shakeZ = Math.sin(t * 2.1) * 0.22 * shakeStrength;

            trauma = Math.max(0.0, trauma - 1.8 * dt);
        }

        cam.pos.set(currentPos.x + shakeX, currentPos.y + shakeY, currentPos.z + shakeZ);
        cam.target.set(currentTarget.x, currentTarget.y, currentTarget.z);
    }
}