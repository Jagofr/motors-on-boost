package input;

import config.GameConfig;
import core.WebBridge;
import input.InputKey as Key;
import input.GamepadDevice as Pad;

/**
 * Controller physical button naming and layout convention.
 */
enum ControllerLayout {
    /** Microsoft Xbox controller layout (ABXY). */
    StandardXbox;

    /** Nintendo Switch / BayX controller layout (BAYX). */
    NintendoBayX;
}

/**
 * Hardware device isolation filter preventing conflicting concurrent inputs.
 */
enum ExclusiveDevice {
    /** Both keyboard and gamepad contribute to movement and navigation. */
    Both;

    /** Only keyboard keystrokes are registered; gamepad polling is muted. */
    KeyboardOnly;

    /** Only gamepad buttons and sticks are registered; keyboard driving is muted. */
    GamepadOnly;
}

/**
 * Enumeration of rebindable vehicle driving actions.
 */
enum InputAction {
    /** Steer rack turn-in towards the left. */
    SteerLeft;

    /** Steer rack turn-in towards the right. */
    SteerRight;

    /** Forward engine throttle acceleration. */
    Throttle;

    /** Service foot-braking and reverse gear deceleration. */
    Brake;

    /** Rear axle handbrake locking for initiating drift slides. */
    Handbrake;

    /** Nitrous oxide injection forward surge. */
    Boost;
}

/**
 * Serialized keyboard scan-codes and gamepad button indices for player actions.
 */
class InputBindings {
    /** Keyboard scan-code for steering left. */
    public var keyLeft:Int = Key.A;

    /** Keyboard scan-code for steering right. */
    public var keyRight:Int = Key.D;

    /** Keyboard scan-code for throttle acceleration. */
    public var keyGas:Int = Key.W;

    /** Keyboard scan-code for braking and reversing. */
    public var keyBrake:Int = Key.S;

    /** Keyboard scan-code for handbrake drift. */
    public var keyHandbrake:Int = Key.SPACE;

    /** Keyboard scan-code for nitrous boost. */
    public var keyBoost:Int = Key.SHIFT;

    /** Gamepad button index or analog axis trigger for throttle. */
    public var padGas:Int = 7;

    /** Gamepad button index or analog axis trigger for braking. */
    public var padBrake:Int = 6;

    /** Gamepad button index for handbrake drift. */
    public var padHandbrake:Int = 1;

    /** Gamepad button index for nitrous boost. */
    public var padBoost:Int = 4;

    /**
     * Initializes default input mappings.
     */
    public function new() {}

    /**
     * Resets keyboard bindings to default WASD and spacebar layout.
     */
    public function resetKeyboardDefaults() {
        keyLeft = Key.A;
        keyRight = Key.D;
        keyGas = Key.W;
        keyBrake = Key.S;
        keyHandbrake = Key.SPACE;
        keyBoost = Key.SHIFT;
    }

    /**
     * Resets gamepad bindings to default triggers and shoulder bumper layout.
     */
    public function resetGamepadDefaults() {
        padGas = 7;
        padBrake = 6;
        padHandbrake = 1;
        padBoost = 4;
    }
}

/**
 * Cross-platform input manager and hardware listener.
 * Captures keyboard keystrokes, gamepad axes, analog triggers, and mobile touch events.
 * Performs digital steering rack rate-of-turn smoothing and self-centering.
 *
 * @class InputController
 * @module input/InputController
 */
class InputController {
    /** Steering rack position in range [-1.0 (full left), +1.0 (full right)]. */
    public var steer:Float = 0.0;

    /** Internal persistent digital steering rack state [-1.0, 1.0] decoupled from analog inputs and sensitivity scaling. */
    private var rawDigitalSteer:Float = 0.0;

    /** Longitudinal throttle percentage in range [0.0, 1.0]. */
    public var throttle:Float = 0.0;

    /** Service brake / reverse percentage in range [0.0, 1.0]. */
    public var brake:Float = 0.0;

    /** State of the mechanical rear handbrake. */
    public var handbrake:Bool = false;

    /** State of active nitrous oxide injection. */
    public var boost:Bool = false;

    // Edge-triggered UI actions
    /** Edge-triggered toggle for pause menu activation. */
    public var pausePressed:Bool = false;

    /** Edge-triggered UI directional up navigation. */
    public var uiUpPressed:Bool = false;

    /** Edge-triggered UI directional down navigation. */
    public var uiDownPressed:Bool = false;

    /** Edge-triggered UI directional left adjustment. */
    public var uiLeftPressed:Bool = false;

    /** Edge-triggered UI directional right adjustment. */
    public var uiRightPressed:Bool = false;

    /** Edge-triggered UI confirmation selection. */
    public var uiConfirmPressed:Bool = false;

    /** Edge-triggered UI cancellation or back return. */
    public var uiCancelPressed:Bool = false;

    /** True if any button, key, or mouse click occurred this frame. */
    public var anyKeyPressed:Bool = false;

    // Edge-triggered bumper tab cycling
    /** Edge-triggered previous tab bumper cycle (LB / Q). */
    public var tabPrevPressed:Bool = false;

    /** Edge-triggered next tab bumper cycle (RB / E). */
    public var tabNextPressed:Bool = false;

    /** Active device filter mode. */
    public var exclusiveDevice:ExclusiveDevice = Both;

    /** User configurable input action bindings. */
    public var bindings:InputBindings = new InputBindings();

    /** Preferred button naming layout. */
    public var layout:ControllerLayout = NintendoBayX;

    /** True if currently in key capture mode awaiting a remapping press. */
    public var isListeningForRemap:Bool = false;

    /** Action currently being remapped. */
    public var listeningAction:Null<InputAction> = null;

    /** True if awaiting gamepad button input for remapping; false if awaiting keyboard. */
    public var listeningForGamepad:Bool = false;

    /** Callback notified when key/gamepad capture completes (`true` = bound, `false` = cancelled). */
    public var onRemapComplete:Null<Bool -> Void>;

    /** Active Heaps gamepad instance, or null if no controller is paired. */
    var pad:Pad;

    /** Target steer angle for digital keyboard keys. */
    var digitalSteerTarget:Float = 0.0;

    // Previous frame edge detection states
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

    /** Cooldown timer preventing double-activation upon menu switching. */
    public var inputCooldown:Float = 0.0;

    // Mobile Virtual Touch Controls States
    /** Mobile virtual touch steering offset in range [-1.0, 1.0]. */
    public var touchSteer:Float = 0.0;

    /** Mobile virtual touch throttle acceleration intensity in range [0.0, 1.0]. */
    public var touchThrottle:Float = 0.0;

    /** Mobile virtual touch brake intensity in range [0.0, 1.0]. */
    public var touchBrake:Float = 0.0;

    /** Mobile virtual touch handbrake state. */
    public var touchHandbrake:Bool = false;

    /** Mobile virtual touch nitrous boost state. */
    public var touchBoost:Bool = false;

    /** True if touch inputs have been detected on the device. */
    public var isTouchActive:Bool = false;

    /** User configured steering sensitivity scalar in range [0.0, 1.0] (default 1.0). */
    public var steerSensitivity:Float = 1.0;

    /** Active input rack slew and deadzone configuration profile. */
    public var config:config.GameConfig.InputConfig;

    /** Steering rate of turn for keyboard keys in units per second. @default 4.2 */
    static inline var STEER_SPEED:Float = 4.2;

    /** Self-centering return-to-center speed when keys are released in units per second. @default 6.5 */
    static inline var RETURN_SPEED:Float = 6.5;

    /** Analog stick deadzone threshold filtering jitter. @default 0.12 */
    static inline var GAMEPAD_DEADZONE:Float = 0.12;

    /** Threshold on analog stick to trigger discrete UI navigation pulses. @default 0.55 */
    static inline var UI_STICK_THRESHOLD:Float = 0.55;

    /** Lookup map from Heaps key scan-codes to readable display strings. */
    private static var KEY_NAMES:Map<Int, String> = [
        Key.SPACE => "SPACE",
        Key.SHIFT => "L-SHIFT",
        Key.CTRL => "CTRL",
        Key.ALT => "ALT",
        Key.BACKSPACE => "BACKSPACE",
        Key.TAB => "TAB",
        Key.UP => "UP ARROW",
        Key.DOWN => "DOWN ARROW",
        Key.LEFT => "LEFT ARROW",
        Key.RIGHT => "RIGHT ARROW",
        Key.ENTER => "ENTER"
    ];

    /** Lookup map from controller button indices to readable display labels. */
    private static var PAD_BTN_NAMES:Map<Int, String> = [
        0 => "A (Bottom)",
        1 => "B (Right)",
        2 => "X (Left)",
        3 => "Y (Top)",
        4 => "LB",
        5 => "RB",
        6 => "LT",
        7 => "RT",
        8 => "Select",
        9 => "Start",
        12 => "D-Pad Up",
        13 => "D-Pad Down",
        14 => "D-Pad Left",
        15 => "D-Pad Right"
    ];

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

    /**
     * Initializes the input controller with optional configuration overrides, sets up
     * touch detection, and pairs connected gamepads.
     *
     * @param {Null<config.GameConfig.InputConfig>} [config] Optional input slew & deadzone config.
     */
    public function new(?config:config.GameConfig.InputConfig) {
        this.config = config != null ? config : GameConfig.getDefault().input;
        this.steerSensitivity = this.config.defaultSteerSensitivity;
        Pad.wait(onPadConnected);
        initTouchDetection();
    }

    /**
     * Hydrates custom key/gamepad bindings, steering sensitivity, and device mode from save data.
     *
     * @param {save.SaveSystem.GameSaveData} data Loaded save payload.
     * @returns {Void}
     */
    public function loadFromSave(data:save.SaveSystem.GameSaveData):Void {
        if (data == null) return;
        if (data.steerSensitivity != null) {
            steerSensitivity = data.steerSensitivity;
        }
        if (data.bindings != null) {
            bindings.keyLeft = data.bindings.keyLeft;
            bindings.keyRight = data.bindings.keyRight;
            bindings.keyGas = data.bindings.keyGas;
            bindings.keyBrake = data.bindings.keyBrake;
            bindings.keyHandbrake = data.bindings.keyHandbrake;
            bindings.keyBoost = data.bindings.keyBoost;
            bindings.padGas = data.bindings.padGas;
            bindings.padBrake = data.bindings.padBrake;
            bindings.padHandbrake = data.bindings.padHandbrake;
            bindings.padBoost = data.bindings.padBoost;
        }
        if (data.exclusiveDevice != null) {
            exclusiveDevice = switch (data.exclusiveDevice) {
                case "KeyboardOnly": KeyboardOnly;
                case "GamepadOnly": GamepadOnly;
                default: Both;
            };
        }
    }

    /**
     * Writes active custom bindings and exclusive device filter into a save record.
     *
     * @param {save.SaveSystem.GameSaveData} data Target save record to populate.
     * @returns {Void}
     */
    public function exportToSave(data:save.SaveSystem.GameSaveData):Void {
        if (data == null) return;
        data.steerSensitivity = steerSensitivity;
        data.bindings = {
            keyLeft: bindings.keyLeft,
            keyRight: bindings.keyRight,
            keyGas: bindings.keyGas,
            keyBrake: bindings.keyBrake,
            keyHandbrake: bindings.keyHandbrake,
            keyBoost: bindings.keyBoost,
            padGas: bindings.padGas,
            padBrake: bindings.padBrake,
            padHandbrake: bindings.padHandbrake,
            padBoost: bindings.padBoost
        };
        data.exclusiveDevice = switch (exclusiveDevice) {
            case KeyboardOnly: "KeyboardOnly";
            case GamepadOnly: "GamepadOnly";
            case Both: "Both";
        };
    }

    /**
     * Inspects browser navigator capabilities and sets up listeners for touch events.
     */
    function initTouchDetection() {
        var wbTouch = WebBridge.inst.readTouchState();
        if (wbTouch.active) {
            isTouchActive = true;
        }
    }

    /**
     * Gamepad connection callback attaching disconnect handlers and deadzones.
     */
    function onPadConnected(p:Pad) {
        pad = p;
        pad.axisDeadZone = GAMEPAD_DEADZONE;
        pad.onDisconnect = function() {
            pad = null;
        };
    }

    /** Returns true if a physical or browser-bridged gamepad is currently connected. */
    public inline function isPadConnected():Bool {
        return pad != null && pad.connected;
    }

    /**
     * Checks if a specified gamepad button is currently depressed.
     *
     * @param btnIdx Gamepad button index to test.
     * @return True if button is pressed.
     */
    public inline function isBtnDown(btnIdx:Int):Bool {
        if (pad == null || pad.buttons == null || btnIdx < 0 || btnIdx >= pad.buttons.length) return false;
        return pad.buttons[btnIdx];
    }

    /**
     * Reads analog axis value from the connected controller.
     *
     * @param idx Analog axis index.
     * @return Float reading in range [0.0, 1.0].
     */
    public inline function getAnalogValue(idx:Int):Float {
        if (pad == null || pad.values == null || idx < 0 || idx >= pad.values.length) return 0.0;
        return pad.values[idx];
    }

    /**
     * Clears all momentary edge-triggered flags and starts a brief debouncing cooldown.
     */
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
        rawDigitalSteer = 0.0;
        Key.clearLatches();

        var stickY = (pad != null) ? pad.yAxis : 0.0;
        var stickX = (pad != null) ? pad.xAxis : 0.0;
        prevEscape = Key.isDown(Key.ESCAPE);
        prevPadStart = isBtnDown(BTN_START);
        prevUp = Key.isDown(Key.UP) || Key.isDown(Key.W) || isBtnDown(DPAD_UP) || (stickY < -UI_STICK_THRESHOLD);
        prevDown = Key.isDown(Key.DOWN) || Key.isDown(Key.S) || isBtnDown(DPAD_DOWN) || (stickY > UI_STICK_THRESHOLD);
        prevLeft = Key.isDown(Key.LEFT) || Key.isDown(Key.A) || isBtnDown(DPAD_LEFT) || (stickX < -UI_STICK_THRESHOLD);
        prevRight = Key.isDown(Key.RIGHT) || Key.isDown(Key.D) || isBtnDown(DPAD_RIGHT) || (stickX > UI_STICK_THRESHOLD);
        prevConfirm = Key.isDown(Key.ENTER) || Key.isDown(Key.SPACE) || isBtnDown(BTN_SOUTH);
        prevCancel = Key.isDown(Key.BACKSPACE) || isBtnDown(BTN_EAST);
        prevLb = isBtnDown(BTN_LB) || Key.isDown(Key.Q);
        prevRb = isBtnDown(BTN_RB) || Key.isDown(Key.E);
        inputCooldown = 0.04;
    }

    /**
     * Puts controller into remapping capture mode for a given driving action.
     *
     * @param action Target InputAction to bind.
     * @param isGamepad True to listen for controller buttons; false for keyboard scan-codes.
     */
    public function startListening(action:InputAction, isGamepad:Bool) {
        isListeningForRemap = true;
        listeningAction = action;
        listeningForGamepad = isGamepad;
        inputCooldown = 0.14;
        flushInputs();
    }

    /**
     * Evaluates continuous driving steering, throttle, brakes, and discrete UI navigation pulses.
     *
     * @param dt Delta time elapsed since last frame in seconds.
     */
    public function update(dt:Float) {
        var wbTouch = WebBridge.inst.readTouchState();
        if (wbTouch.active) {
            isTouchActive = true;
            touchSteer = wbTouch.steer;
            touchThrottle = wbTouch.throttle;
            touchBrake = wbTouch.brake;
            touchHandbrake = wbTouch.handbrake;
            touchBoost = wbTouch.boost;
            if (wbTouch.pause) pausePressed = true;
        }
        if (inputCooldown > 0.0) {
            inputCooldown -= dt;
        }

        if (isListeningForRemap) {
            handleRemappingCapture();
            return;
        }

        // 1. Navigation & Edge-Triggered Discrete Inputs (uses isDownOrTapped so sub-frame key taps are never dropped)
        var currEscape = Key.isDownOrTapped(Key.ESCAPE);
        var currPadStart = isBtnDown(BTN_START);

        pausePressed = (inputCooldown <= 0.0) && ((currEscape && !prevEscape) || (currPadStart && !prevPadStart));
        prevEscape = currEscape;
        prevPadStart = currPadStart;

        var stickY = (pad != null) ? pad.yAxis : 0.0;
        var stickX = (pad != null) ? pad.xAxis : 0.0;

        var currUp = Key.isDownOrTapped(Key.UP) || Key.isDownOrTapped(Key.W) || isBtnDown(DPAD_UP) || (stickY < -UI_STICK_THRESHOLD);
        var currDown = Key.isDownOrTapped(Key.DOWN) || Key.isDownOrTapped(Key.S) || isBtnDown(DPAD_DOWN) || (stickY > UI_STICK_THRESHOLD);
        var currLeft = Key.isDownOrTapped(Key.LEFT) || Key.isDownOrTapped(Key.A) || isBtnDown(DPAD_LEFT) || (stickX < -UI_STICK_THRESHOLD);
        var currRight = Key.isDownOrTapped(Key.RIGHT) || Key.isDownOrTapped(Key.D) || isBtnDown(DPAD_RIGHT) || (stickX > UI_STICK_THRESHOLD);

        uiUpPressed = (inputCooldown <= 0.0) && (currUp && !prevUp);
        uiDownPressed = (inputCooldown <= 0.0) && (currDown && !prevDown);
        uiLeftPressed = (inputCooldown <= 0.0) && (currLeft && !prevLeft);
        uiRightPressed = (inputCooldown <= 0.0) && (currRight && !prevRight);

        prevUp = currUp;
        prevDown = currDown;
        prevLeft = currLeft;
        prevRight = currRight;

        var currConfirm = Key.isDownOrTapped(Key.ENTER) || Key.isDownOrTapped(Key.SPACE) || isBtnDown(BTN_SOUTH);
        var currCancel = Key.isDownOrTapped(Key.BACKSPACE) || isBtnDown(BTN_EAST);

        uiConfirmPressed = (inputCooldown <= 0.0) && (currConfirm && !prevConfirm);
        uiCancelPressed = (inputCooldown <= 0.0) && (currCancel && !prevCancel);
        prevConfirm = currConfirm;
        prevCancel = currCancel;

        // Discrete bumper / tab cycling (LB / RB or Q / E)
        var currLb = isBtnDown(BTN_LB) || Key.isDownOrTapped(Key.Q);
        var currRb = isBtnDown(BTN_RB) || Key.isDownOrTapped(Key.E);
        tabPrevPressed = (inputCooldown <= 0.0) && (currLb && !prevLb);
        tabNextPressed = (inputCooldown <= 0.0) && (currRb && !prevRb);
        prevLb = currLb;
        prevRb = currRb;

        anyKeyPressed = false;
        if (inputCooldown <= 0.0) {
            if (currConfirm || currCancel || Key.isDownOrTapped(Key.MOUSE_LEFT) || currEscape || currPadStart
                || touchThrottle > 0 || touchBrake > 0 || Math.abs(touchSteer) > 0.05 || touchHandbrake || touchBoost) {
                anyKeyPressed = true;
            } else if (pad != null && pad.buttons != null) {
                for (b in pad.buttons) {
                    if (b) { anyKeyPressed = true; break; }
                }
            }
            Key.clearLatches();
        }

        // 2. Continuous Driving Controls Integration (strictly - = Left, + = Right across all devices)
        var allowKeyboard = (exclusiveDevice == Both || exclusiveDevice == KeyboardOnly);
        var allowGamepad = (exclusiveDevice == Both || exclusiveDevice == GamepadOnly);

        var keyLeft = allowKeyboard && (Key.isDown(bindings.keyLeft) || Key.isDown(Key.LEFT));
        var keyRight = allowKeyboard && (Key.isDown(bindings.keyRight) || Key.isDown(Key.RIGHT));
        var dpadLeft = allowGamepad && pad != null && isBtnDown(DPAD_LEFT);
        var dpadRight = allowGamepad && pad != null && isBtnDown(DPAD_RIGHT);
        var keyGas = allowKeyboard && (Key.isDown(bindings.keyGas) || Key.isDown(Key.UP));
        var keyReverse = allowKeyboard && (Key.isDown(bindings.keyBrake) || Key.isDown(Key.DOWN));

        var steerLeft = keyLeft || dpadLeft;
        var steerRight = keyRight || dpadRight;

        if (steerLeft && !steerRight) digitalSteerTarget = -1.0;
        else if (steerRight && !steerLeft) digitalSteerTarget = 1.0;
        else digitalSteerTarget = 0.0;

        var steerRate = config.steerSpeed;
        var returnRate = config.returnSpeed;
        var padDeadzone = config.gamepadDeadzone;

        // Digital steering rack simulation kept independent from analog sticks and sensitivity scaling
        if (digitalSteerTarget != 0.0) {
            if (rawDigitalSteer < digitalSteerTarget) rawDigitalSteer = Math.min(digitalSteerTarget, rawDigitalSteer + steerRate * dt);
            else if (rawDigitalSteer > digitalSteerTarget) rawDigitalSteer = Math.max(digitalSteerTarget, rawDigitalSteer - steerRate * dt);
        } else {
            if (rawDigitalSteer > 0.0) rawDigitalSteer = Math.max(0.0, rawDigitalSteer - returnRate * dt);
            else if (rawDigitalSteer < 0.0) rawDigitalSteer = Math.min(0.0, rawDigitalSteer + returnRate * dt);
        }

        var combinedSteer = rawDigitalSteer;

        throttle = keyGas ? 1.0 : 0.0;
        brake = keyReverse ? 1.0 : 0.0;
        handbrake = allowKeyboard && Key.isDown(bindings.keyHandbrake);
        boost = allowKeyboard && Key.isDown(bindings.keyBoost);

        // Analog gamepad thumbstick steering (deadzone-rescaled, canonical - = Left, + = Right) and progressive triggers
        if (allowGamepad && pad != null) {
            var absStick = Math.abs(stickX);
            if (absStick > padDeadzone && padDeadzone < 0.99) {
                var sign = stickX < 0.0 ? -1.0 : 1.0;
                var norm = Math.max(0.0, Math.min(1.0, (absStick - padDeadzone) / (1.0 - padDeadzone)));
                var padSteer = sign * Math.pow(norm, 1.35);
                if (digitalSteerTarget == 0.0 || Math.abs(padSteer) >= Math.abs(combinedSteer)) {
                    combinedSteer = padSteer;
                }
            }

            var padThrottle = Math.max(0.0, Math.min(1.0, getAnalogValue(bindings.padGas)));
            var padBrakeVal = Math.max(0.0, Math.min(1.0, getAnalogValue(bindings.padBrake)));

            if (isBtnDown(bindings.padGas)) padThrottle = 1.0;
            if (isBtnDown(bindings.padBrake)) padBrakeVal = 1.0;

            if (padThrottle > 0.05) throttle = Math.max(throttle, padThrottle);
            if (padBrakeVal > 0.05) brake = Math.max(brake, padBrakeVal);

            if (isBtnDown(bindings.padHandbrake)) handbrake = true;
            if (isBtnDown(bindings.padBoost)) boost = true;
        }

        // Virtual multi-touch analog stick & pedal blending (small inner deadzone prevents resting jitter)
        var absTouchSteer = Math.abs(touchSteer);
        if (absTouchSteer > 0.03) {
            var tSign = touchSteer < 0.0 ? -1.0 : 1.0;
            var tNorm = Math.max(0.0, Math.min(1.0, (absTouchSteer - 0.03) / 0.97));
            var touchCurved = tSign * Math.pow(tNorm, 1.15);
            if (digitalSteerTarget == 0.0 || Math.abs(touchCurved) >= Math.abs(combinedSteer)) {
                combinedSteer = touchCurved;
            }
        }
        if (touchThrottle > 0.0) throttle = Math.max(throttle, Math.min(1.0, touchThrottle));
        if (touchBrake > 0.0) brake = Math.max(brake, Math.min(1.0, touchBrake));
        if (touchHandbrake) handbrake = true;
        if (touchBoost) boost = true;

        throttle = Math.max(0.0, Math.min(1.0, throttle));
        brake = Math.max(0.0, Math.min(1.0, brake));

        // Apply user-configured steering sensitivity scalar [0.1 - 1.0] against slightly boosted base sensitivity (1.20x)
        var clampedSens = Math.max(0.1, Math.min(1.0, steerSensitivity));
        steer = Math.max(-1.0, Math.min(1.0, combinedSteer * 1.20 * clampedSens));
    }

    function finishRemapping(bound:Bool) {
        isListeningForRemap = false;
        listeningAction = null;
        flushInputs();
        if (onRemapComplete != null) onRemapComplete(bound);
    }

    /**
     * Intercepts key presses or gamepad buttons while remapping menu is active.
     */
    function handleRemappingCapture() {
        if (inputCooldown > 0.0) return;

        // Allow cancellation via Escape or Start button
        if (Key.isDownOrTapped(Key.ESCAPE) || isBtnDown(BTN_START)) {
            Key.clearLatches();
            finishRemapping(false);
            return;
        }

        if (!listeningForGamepad) {
            for (k in 4...255) {
                if (Key.isDownOrTapped(k) && k != Key.ESCAPE) {
                    switch (listeningAction) {
                        case SteerLeft: bindings.keyLeft = k;
                        case SteerRight: bindings.keyRight = k;
                        case Throttle: bindings.keyGas = k;
                        case Brake: bindings.keyBrake = k;
                        case Handbrake: bindings.keyHandbrake = k;
                        case Boost: bindings.keyBoost = k;
                    }
                    Key.clearLatches();
                    finishRemapping(true);
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
                    finishRemapping(true);
                    return;
                }
            }
        }
    }

    /**
     * Formats keyboard scan-code into a human-readable display string.
     *
     * @param {Int} k Heaps key scan-code.
     * @returns {String} Readable key label.
     */
    public static function getKeyName(k:Int):String {
        var named = KEY_NAMES.get(k);
        return named != null ? named : String.fromCharCode(k);
    }

    /**
     * Formats gamepad button index into a human-readable display string.
     *
     * @param {Int} btn Zero-based gamepad button index.
     * @returns {String} Readable button label.
     */
    public static function getGamepadBtnName(btn:Int):String {
        var named = PAD_BTN_NAMES.get(btn);
        return named != null ? named : "Btn " + btn;
    }
}