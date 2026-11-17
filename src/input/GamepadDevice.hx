package input;

import window.Gamepad;
import window.GamepadAxis;
import window.GamepadButton;
import window.GamepadEvent;

/**
 * Platform-neutral gamepad state wrapper replacing `hxd.Pad`.
 * Mirrors W3C Standard Gamepad layout indices used by `hlwindow` and saved control bindings.
 */
class GamepadDevice {
    public var connected:Bool = false;
    public var index:Int = 0;
    public var name:String = "Gamepad";

    public var rawXAxis:Float = 0.0;
    public var rawYAxis:Float = 0.0;
    public var axisDeadZone:Float = 0.08;
    public var onDisconnect:Null<Void -> Void> = null;
    public var xAxis(get, set):Float;
    public var yAxis(get, set):Float;

    inline function get_xAxis():Float return rawXAxis;
    inline function set_xAxis(v:Float):Float return rawXAxis = v;
    inline function get_yAxis():Float return rawYAxis;
    inline function set_yAxis(v:Float):Float return rawYAxis = v;

    public var values:Array<Float>;
    public var buttons:Array<Bool>;

    private static var listenersRegistered:Bool = false;
    private static var connectCallback:Null<GamepadDevice -> Void> = null;
    private static var activeDevice:Null<GamepadDevice> = null;

    public function new(index:Int = 0) {
        this.index = index;
        this.values = [for (_ in 0...24) 0.0];
        this.buttons = [for (_ in 0...24) false];
    }

    public static function createDummy():GamepadDevice {
        var dev = new GamepadDevice(0);
        dev.connected = false;
        return dev;
    }

    public static function wait(onConnect:GamepadDevice -> Void):Void {
        connectCallback = onConnect;
        listenersRegistered = true;
    }

    public static function pollAll(headless:Bool = false):Void {
        if (headless) return;
        try {
            var guard = 0;
            while (guard++ < 16 && Gamepad.poll() != GamepadEvent.None) {}
            if (!Gamepad.available() || Gamepad.count() <= 0) {
                if (activeDevice != null && activeDevice.connected && !usingExternalSnapshot) {
                    activeDevice.connected = false;
                    activeDevice.clearState();
                    if (activeDevice.onDisconnect != null) activeDevice.onDisconnect();
                }
                return;
            }
            usingExternalSnapshot = false;
            var hw = Gamepad.at(0);
            if (!hw.valid()) return;
            if (activeDevice == null) {
                activeDevice = new GamepadDevice(0);
                activeDevice.connected = true;
                activeDevice.name = hw.name();
                if (connectCallback != null) connectCallback(activeDevice);
            } else if (!activeDevice.connected) {
                activeDevice.connected = true;
                activeDevice.name = hw.name();
                if (connectCallback != null) connectCallback(activeDevice);
            }
            activeDevice.syncFromWindowGamepad(hw);
        } catch (_:Dynamic) {}
    }

    private static var usingExternalSnapshot:Bool = false;

    /**
     * Feeds controller state forwarded from the browser main thread when the Worker proxy
     * has no active controller handle (e.g., iOS Safari or virtual/Playwright gamepads).
     */
    public static function applyExternalSnapshot(connected:Bool, axes:Array<Float>, pressed:Array<Bool>, vals:Array<Float>):Void {
        if (!connected) {
            if (usingExternalSnapshot && activeDevice != null && activeDevice.connected) {
                usingExternalSnapshot = false;
                activeDevice.connected = false;
                activeDevice.clearState();
                if (activeDevice.onDisconnect != null) activeDevice.onDisconnect();
            }
            return;
        }
        usingExternalSnapshot = true;
        if (activeDevice == null) {
            activeDevice = new GamepadDevice(0);
            activeDevice.connected = true;
            activeDevice.name = "Browser Gamepad";
            if (connectCallback != null) connectCallback(activeDevice);
        } else if (!activeDevice.connected) {
            activeDevice.connected = true;
            activeDevice.name = "Browser Gamepad";
            if (connectCallback != null) connectCallback(activeDevice);
        }
        activeDevice.rawXAxis = (axes != null && axes.length > 0) ? axes[0] : 0.0;
        activeDevice.rawYAxis = (axes != null && axes.length > 1) ? axes[1] : 0.0;
        var maxBtns = activeDevice.buttons.length;
        for (i in 0...maxBtns) {
            var v = (vals != null && i < vals.length) ? vals[i] : 0.0;
            var p = (pressed != null && i < pressed.length) ? pressed[i] : (v > 0.5);
            activeDevice.values[i] = v;
            activeDevice.buttons[i] = p;
        }
    }

    public function syncFromWindowGamepad(hw:Gamepad):Void {
        if (!hw.valid()) {
            connected = false;
            clearState();
            return;
        }
        connected = true;
        rawXAxis = hw.axis(GamepadAxis.LeftX);
        rawYAxis = hw.axis(GamepadAxis.LeftY);

        var btns:Array<GamepadButton> = [
            GamepadButton.South,
            GamepadButton.East,
            GamepadButton.West,
            GamepadButton.North,
            GamepadButton.LeftShoulder,
            GamepadButton.RightShoulder,
            GamepadButton.LeftTrigger,
            GamepadButton.RightTrigger,
            GamepadButton.Select,
            GamepadButton.Start,
            GamepadButton.LeftStick,
            GamepadButton.RightStick,
            GamepadButton.DPadUp,
            GamepadButton.DPadDown,
            GamepadButton.DPadLeft,
            GamepadButton.DPadRight,
            GamepadButton.Guide
        ];
        for (i in 0...btns.length) {
            var val = hw.button(btns[i]);
            values[i] = val;
            buttons[i] = hw.pressed(btns[i]) || val > 0.5;
        }
    }

    public function clearState():Void {
        rawXAxis = 0.0;
        rawYAxis = 0.0;
        for (i in 0...values.length) values[i] = 0.0;
        for (i in 0...buttons.length) buttons[i] = false;
    }

    public inline function isDown(buttonIndex:Int):Bool {
        if (!connected || buttonIndex < 0 || buttonIndex >= buttons.length) return false;
        return buttons[buttonIndex];
    }
}
