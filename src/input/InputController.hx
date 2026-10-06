package input;

import hxd.Key;
import hxd.Pad;

enum ControllerLayout {
    StandardXbox;
    NintendoBayX;
}

enum ExclusiveDevice {
    Both;
    KeyboardOnly;
    GamepadOnly;
}

enum InputAction {
    SteerLeft;
    SteerRight;
    Throttle;
    Brake;
    Handbrake;
    Boost;
}

class InputBindings {
    public var keyLeft:Int = Key.A;
    public var keyRight:Int = Key.D;
    public var keyGas:Int = Key.W;
    public var keyBrake:Int = Key.S;
    public var keyHandbrake:Int = Key.SPACE;
    public var keyBoost:Int = Key.SHIFT;

    public var padGas:Int = 7;
    public var padBrake:Int = 6;
    public var padHandbrake:Int = 1;
    public var padBoost:Int = 4;

    public function new() {}

    public function resetKeyboardDefaults() {
        keyLeft = Key.A;
        keyRight = Key.D;
        keyGas = Key.W;
        keyBrake = Key.S;
        keyHandbrake = Key.SPACE;
        keyBoost = Key.SHIFT;
    }

    public function resetGamepadDefaults() {
        padGas = 7;
        padBrake = 6;
        padHandbrake = 1;
        padBoost = 4;
    }
}

class InputController {
    public var steer:Float = 0.0;
    public var throttle:Float = 0.0;
    public var brake:Float = 0.0;
    public var handbrake:Bool = false;
    public var boost:Bool = false;

    // Edge-triggered UI actions
    public var pausePressed:Bool = false;
    public var uiUpPressed:Bool = false;
    public var uiDownPressed:Bool = false;
    public var uiLeftPressed:Bool = false;
    public var uiRightPressed:Bool = false;
    public var uiConfirmPressed:Bool = false;
    public var uiCancelPressed:Bool = false;
    public var anyKeyPressed:Bool = false;

    // Edge-triggered bumper tab cycling
    public var tabPrevPressed:Bool = false;
    public var tabNextPressed:Bool = false;

    public var exclusiveDevice:ExclusiveDevice = Both;
    public var bindings:InputBindings = new InputBindings();
    public var layout:ControllerLayout = NintendoBayX;

    public var isListeningForRemap:Bool = false;
    public var listeningAction:Null<InputAction> = null;
    public var listeningForGamepad:Bool = false;

    var pad:Pad;
    var digitalSteerTarget:Float = 0.0;

    var prevEscape:Bool = false;
    var prevPadStart:Bool = false;
    var prevUp:Bool = false;
    var prevDown:Bool = false;
    var prevLeft:Bool = false;
    var prevRight:Bool = false;
    var prevConfirm:Bool = false;
    var prevCancel:Bool = false;
    var prevLb:Bool = false;
    var prevRb:Bool = false;

    public var inputCooldown:Float = 0.0;

    static inline var STEER_SPEED:Float = 4.2;
    static inline var RETURN_SPEED:Float = 6.5;
    static inline var GAMEPAD_DEADZONE:Float = 0.12;
    static inline var UI_STICK_THRESHOLD:Float = 0.55;

    public static inline var BTN_SOUTH:Int = 0;
    public static inline var BTN_EAST:Int = 1;
    public static inline var BTN_WEST:Int = 2;
    public static inline var BTN_NORTH:Int = 3;
    public static inline var BTN_LB:Int = 4;
    public static inline var BTN_RB:Int = 5;
    public static inline var TRIG_LT:Int = 6;
    public static inline var TRIG_RT:Int = 7;
    public static inline var BTN_START:Int = 9;
    public static inline var DPAD_UP:Int = 12;
    public static inline var DPAD_DOWN:Int = 13;
    public static inline var DPAD_LEFT:Int = 14;
    public static inline var DPAD_RIGHT:Int = 15;

    public function new() {
        Pad.wait(onPadConnected);
    }

    function onPadConnected(p:Pad) {
        pad = p;
        pad.axisDeadZone = GAMEPAD_DEADZONE;
        pad.onDisconnect = function() {
            pad = null;
        };
    }

    public inline function isBtnDown(btnIdx:Int):Bool {
        if (pad == null || pad.buttons == null || btnIdx < 0 || btnIdx >= pad.buttons.length) return false;
        return pad.buttons[btnIdx];
    }

    public inline function getAnalogValue(idx:Int):Float {
        if (pad == null || pad.values == null || idx < 0 || idx >= pad.values.length) return 0.0;
        return pad.values[idx];
    }

    public function flushInputs() {
        pausePressed = false;
        uiUpPressed = false;
        uiDownPressed = false;
        uiLeftPressed = false;
        uiRightPressed = false;
        uiConfirmPressed = false;
        uiCancelPressed = false;
        tabPrevPressed = false;
        tabNextPressed = false;
        anyKeyPressed = false;
        inputCooldown = 0.22;
    }

    public function startListening(action:InputAction, isGamepad:Bool) {
        isListeningForRemap = true;
        listeningAction = action;
        listeningForGamepad = isGamepad;
        flushInputs();
    }

    public function update(dt:Float) {
        if (inputCooldown > 0.0) {
            inputCooldown -= dt;
        }

        if (isListeningForRemap) {
            handleRemappingCapture();
            return;
        }

        // 1. Navigation & Edge Inputs
        var currEscape = Key.isDown(Key.ESCAPE);
        var currPadStart = isBtnDown(BTN_START);

        pausePressed = (inputCooldown <= 0.0) && ((currEscape && !prevEscape) || (currPadStart && !prevPadStart));
        prevEscape = currEscape;
        prevPadStart = currPadStart;

        var stickY = (pad != null) ? pad.yAxis : 0.0;
        var stickX = (pad != null) ? pad.xAxis : 0.0;

        var currUp = Key.isDown(Key.UP) || Key.isDown(Key.W) || isBtnDown(DPAD_UP) || (stickY < -UI_STICK_THRESHOLD);
        var currDown = Key.isDown(Key.DOWN) || Key.isDown(Key.S) || isBtnDown(DPAD_DOWN) || (stickY > UI_STICK_THRESHOLD);
        var currLeft = Key.isDown(Key.LEFT) || Key.isDown(Key.A) || isBtnDown(DPAD_LEFT) || (stickX < -UI_STICK_THRESHOLD);
        var currRight = Key.isDown(Key.RIGHT) || Key.isDown(Key.D) || isBtnDown(DPAD_RIGHT) || (stickX > UI_STICK_THRESHOLD);

        uiUpPressed = (inputCooldown <= 0.0) && (currUp && !prevUp);
        uiDownPressed = (inputCooldown <= 0.0) && (currDown && !prevDown);
        uiLeftPressed = (inputCooldown <= 0.0) && (currLeft && !prevLeft);
        uiRightPressed = (inputCooldown <= 0.0) && (currRight && !prevRight);

        prevUp = currUp;
        prevDown = currDown;
        prevLeft = currLeft;
        prevRight = currRight;

        var currConfirm = Key.isDown(Key.ENTER) || Key.isDown(Key.SPACE) || isBtnDown(BTN_SOUTH);
        var currCancel = Key.isDown(Key.BACKSPACE) || isBtnDown(BTN_EAST);

        uiConfirmPressed = (inputCooldown <= 0.0) && (currConfirm && !prevConfirm);
        uiCancelPressed = (inputCooldown <= 0.0) && (currCancel && !prevCancel);
        prevConfirm = currConfirm;
        prevCancel = currCancel;

        // Discrete bumper / tab cycling (LB/RB or Q/E)
        var currLb = isBtnDown(BTN_LB) || Key.isDown(Key.Q);
        var currRb = isBtnDown(BTN_RB) || Key.isDown(Key.E);
        tabPrevPressed = (inputCooldown <= 0.0) && (currLb && !prevLb);
        tabNextPressed = (inputCooldown <= 0.0) && (currRb && !prevRb);
        prevLb = currLb;
        prevRb = currRb;

        anyKeyPressed = false;
        if (inputCooldown <= 0.0) {
            if (currConfirm || currCancel || Key.isDown(Key.MOUSE_LEFT) || currEscape || currPadStart) {
                anyKeyPressed = true;
            } else if (pad != null && pad.buttons != null) {
                for (b in pad.buttons) {
                    if (b) { anyKeyPressed = true; break; }
                }
            }
        }

        // 2. Continuous Driving Controls
        var allowKeyboard = (exclusiveDevice == Both || exclusiveDevice == KeyboardOnly);
        var allowGamepad = (exclusiveDevice == Both || exclusiveDevice == GamepadOnly);

        var keyLeft = allowKeyboard && (Key.isDown(bindings.keyLeft) || Key.isDown(Key.LEFT));
        var keyRight = allowKeyboard && (Key.isDown(bindings.keyRight) || Key.isDown(Key.RIGHT));
        var keyGas = allowKeyboard && (Key.isDown(bindings.keyGas) || Key.isDown(Key.UP));
        var keyReverse = allowKeyboard && (Key.isDown(bindings.keyBrake) || Key.isDown(Key.DOWN));

        if (keyLeft && !keyRight) digitalSteerTarget = -1.0;
        else if (keyRight && !keyLeft) digitalSteerTarget = 1.0;
        else digitalSteerTarget = 0.0;

        if (digitalSteerTarget != 0.0) {
            if (steer < digitalSteerTarget) steer = Math.min(digitalSteerTarget, steer + STEER_SPEED * dt);
            else if (steer > digitalSteerTarget) steer = Math.max(digitalSteerTarget, steer - STEER_SPEED * dt);
        } else {
            if (steer > 0.0) steer = Math.max(0.0, steer - RETURN_SPEED * dt);
            else if (steer < 0.0) steer = Math.min(0.0, steer + RETURN_SPEED * dt);
        }

        throttle = keyGas ? 1.0 : 0.0;
        brake = keyReverse ? 1.0 : 0.0;
        handbrake = allowKeyboard && Key.isDown(bindings.keyHandbrake);
        boost = allowKeyboard && Key.isDown(bindings.keyBoost);

        if (allowGamepad && pad != null) {
            if (Math.abs(stickX) > GAMEPAD_DEADZONE) {
                var sign = stickX < 0 ? -1.0 : 1.0;
                steer = sign * Math.pow(Math.abs(stickX), 1.4);
            }

            var padThrottle = getAnalogValue(bindings.padGas);
            var padBrakeVal = getAnalogValue(bindings.padBrake);

            if (isBtnDown(bindings.padGas)) padThrottle = 1.0;
            if (isBtnDown(bindings.padBrake)) padBrakeVal = 1.0;

            if (padThrottle > 0.05) throttle = padThrottle;
            if (padBrakeVal > 0.05) brake = padBrakeVal;

            if (isBtnDown(bindings.padHandbrake)) handbrake = true;
            if (isBtnDown(bindings.padBoost)) boost = true;
        }
    }

    function handleRemappingCapture() {
        if (!listeningForGamepad) {
            for (k in 1...255) {
                if (Key.isDown(k) && k != Key.ESCAPE) {
                    switch (listeningAction) {
                        case SteerLeft: bindings.keyLeft = k;
                        case SteerRight: bindings.keyRight = k;
                        case Throttle: bindings.keyGas = k;
                        case Brake: bindings.keyBrake = k;
                        case Handbrake: bindings.keyHandbrake = k;
                        case Boost: bindings.keyBoost = k;
                    }
                    isListeningForRemap = false;
                    listeningAction = null;
                    flushInputs();
                    return;
                }
            }
        } else if (pad != null && pad.buttons != null) {
            for (i in 0...pad.buttons.length) {
                if (pad.buttons[i] && i != BTN_START) {
                    switch (listeningAction) {
                        case Throttle: bindings.padGas = i;
                        case Brake: bindings.padBrake = i;
                        case Handbrake: bindings.padHandbrake = i;
                        case Boost: bindings.padBoost = i;
                        default:
                    }
                    isListeningForRemap = false;
                    listeningAction = null;
                    flushInputs();
                    return;
                }
            }
        }

        if (Key.isDown(Key.ESCAPE) || isBtnDown(BTN_START)) {
            isListeningForRemap = false;
            listeningAction = null;
            flushInputs();
        }
    }

    public static function getKeyName(k:Int):String {
        return switch (k) {
            case Key.SPACE: "SPACE";
            case Key.SHIFT: "L-SHIFT";
            case Key.CTRL: "CTRL";
            case Key.ALT: "ALT";
            case Key.UP: "UP ARROW";
            case Key.DOWN: "DOWN ARROW";
            case Key.LEFT: "LEFT ARROW";
            case Key.RIGHT: "RIGHT ARROW";
            case Key.ENTER: "ENTER";
            default: String.fromCharCode(k);
        };
    }

    public static function getGamepadBtnName(btn:Int):String {
        return switch (btn) {
            case 0: "A (Bottom)";
            case 1: "B (Right)";
            case 2: "X (Left)";
            case 3: "Y (Top)";
            case 4: "LB";
            case 5: "RB";
            case 6: "LT";
            case 7: "RT";
            case 8: "Select";
            case 9: "Start";
            case 12: "D-Pad Up";
            case 13: "D-Pad Down";
            case 14: "D-Pad Left";
            case 15: "D-Pad Right";
            default: "Btn " + btn;
        };
    }
}