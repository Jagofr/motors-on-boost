package entities;

import h3d.scene.Scene;
import net.NetworkProtocol.NetCarState;

/**
 * 3D visual representation and smoothed transform interpolator for a remote multiplayer peer's vehicle.
 */
class RemoteCarActor {
    public var peerId(default, null):String;
    public var name(default, null):String;
    public var colorHex(default, null):Int;
    public var mesh:CarMesh;

    public var currentX:Float = 0.0;
    public var currentY:Float = 0.0;
    public var currentZ:Float = 0.0;
    public var currentYaw:Float = 0.0;
    public var currentPitch:Float = 0.0;
    public var currentRoll:Float = 0.0;

    private var targetState:Null<NetCarState> = null;
    private var hasInitialized:Bool = false;

    public function new(parent:Scene, peerId:String, name:String, colorHex:Int) {
        this.peerId = peerId;
        this.name = name;
        this.colorHex = colorHex;
        this.mesh = new CarMesh(parent);
        applyPaintColor(colorHex);
    }

    public function applyPaintColor(hex:Int):Void {
        this.colorHex = hex;
        if (mesh != null) {
            if (mesh.bodyMesh != null && mesh.bodyMesh.material != null) {
                mesh.bodyMesh.material.color.setColor(hex);
            }
            if (mesh.hoodMesh != null && mesh.hoodMesh.material != null) {
                mesh.hoodMesh.material.color.setColor(hex);
            }
        }
    }

    public function applyTargetState(st:NetCarState):Void {
        if (st == null) return;
        if (st.colorHex != this.colorHex) {
            applyPaintColor(st.colorHex);
        }
        this.name = st.name;
        this.targetState = st;

        if (!hasInitialized) {
            hasInitialized = true;
            currentX = st.x;
            currentY = st.y;
            currentZ = st.z;
            currentYaw = st.yaw;
            currentPitch = st.pitch;
            currentRoll = st.roll;
            syncMesh(st);
        }
    }

    public function update(dt:Float):Void {
        if (targetState == null || mesh == null) return;

        var lerpAlpha = Math.min(1.0, Math.max(0.0, dt * 16.0));
        currentX += (targetState.x - currentX) * lerpAlpha;
        currentY += (targetState.y - currentY) * lerpAlpha;
        currentZ += (targetState.z - currentZ) * lerpAlpha;
        currentPitch += (targetState.pitch - currentPitch) * lerpAlpha;
        currentRoll += (targetState.roll - currentRoll) * lerpAlpha;

        // Shortest-angle yaw interpolation
        var dyaw = wrapAngle(targetState.yaw - currentYaw);
        currentYaw = wrapAngle(currentYaw + dyaw * lerpAlpha);

        syncMesh(targetState);
    }

    private function syncMesh(st:NetCarState):Void {
        mesh.x = currentX;
        mesh.y = currentY;
        mesh.z = currentZ;
        mesh.setRotation(currentPitch, currentRoll, 0);
        mesh.rotate(0, 0, -currentYaw);

        if (mesh.wheels.length >= 4) {
            mesh.updateWheelTransform(0, 0.0, st.wheelSpinAngle, st.steerAngle);
            mesh.updateWheelTransform(1, 0.0, st.wheelSpinAngle, st.steerAngle);
            mesh.updateWheelTransform(2, 0.0, st.wheelSpinAngle, 0.0);
            mesh.updateWheelTransform(3, 0.0, st.wheelSpinAngle, 0.0);
        }
    }

    private function wrapAngle(a:Float):Float {
        while (a > Math.PI) a -= Math.PI * 2.0;
        while (a < -Math.PI) a += Math.PI * 2.0;
        return a;
    }

    public function destroy():Void {
        if (mesh != null) {
            mesh.remove();
            mesh = null;
        }
    }
}
