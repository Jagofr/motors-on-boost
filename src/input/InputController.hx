package input;

import hxd.Key;
import hxd.Pad;

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
 */
class InputController {
    /** Steering rack position in range [-1.0 (full left), +1.0 (full right)]. */
    public var steer:Float = 0.0;

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

    /** Steering rate of turn for keyboard keys in units per second. */
    static inline var STEER_SPEED:Float = 4.2;

    /** Self-centering return-to-center speed when keys are released in units per second. */
    static inline var RETURN_SPEED:Float = 6.5;

    /** Analog stick deadzone threshold filtering jitter. */
    static inline var GAMEPAD_DEADZONE:Float = 0.12;

    /** Threshold on analog stick to trigger discrete UI navigation pulses. */
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

    /**
     * Initializes the input controller, sets up touch detection, and registers gamepad listeners.
     */
    public function new() {
        Pad.wait(onPadConnected);
        initTouchDetection();
    }

    /**
     * Inspects browser navigator capabilities and sets up listeners for touch events.
     */
    function initTouchDetection() {
        #if js
        try {
            var w = js.Browser.window;
            var nav = js.Browser.navigator;
            if (nav != null && (nav.maxTouchPoints > 0 || untyped nav.msMaxTouchPoints > 0)) {
                isTouchActive = true;
            }
            if (w != null && js.Syntax.code("('ontouchstart' in window)")) {
                isTouchActive = true;
            }
            if (w != null && w.addEventListener != null) {
                w.addEventListener("touchstart", function(_) {
                    isTouchActive = true;
                }, { passive: true });
            }
        } catch (e:haxe.Exception) {}
        #end
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
        inputCooldown = 0.22;
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
        flushInputs();
    }

    /**
     * Evaluates continuous driving steering, throttle, brakes, and discrete UI navigation pulses.
     *
     * @param dt Delta time elapsed since last frame in seconds.
     */
    public function update(dt:Float) {
        if (inputCooldown > 0.0) {
            inputCooldown -= dt;
        }

        if (isListeningForRemap) {
            handleRemappingCapture();
            return;
        }

        // 1. Navigation & Edge-Triggered Discrete Inputs
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

        // Discrete bumper / tab cycling (LB / RB or Q / E)
        var currLb = isBtnDown(BTN_LB) || Key.isDown(Key.Q);
        var currRb = isBtnDown(BTN_RB) || Key.isDown(Key.E);
        tabPrevPressed = (inputCooldown <= 0.0) && (currLb && !prevLb);
        tabNextPressed = (inputCooldown <= 0.0) && (currRb && !prevRb);
        prevLb = currLb;
        prevRb = currRb;

        anyKeyPressed = false;
        if (inputCooldown <= 0.0) {
            if (currConfirm || currCancel || Key.isDown(Key.MOUSE_LEFT) || currEscape || currPadStart
                || touchThrottle > 0 || touchBrake > 0 || Math.abs(touchSteer) > 0.05 || touchHandbrake || touchBoost) {
                anyKeyPressed = true;
            } else if (pad != null && pad.buttons != null) {
                for (b in pad.buttons) {
                    if (b) { anyKeyPressed = true; break; }
                }
            }
        }

        // 2. Continuous Driving Controls Integration
        var allowKeyboard = (exclusiveDevice == Both || exclusiveDevice == KeyboardOnly);
        var allowGamepad = (exclusiveDevice == Both || exclusiveDevice == GamepadOnly);

        var keyLeft = allowKeyboard && (Key.isDown(bindings.keyLeft) || Key.isDown(Key.LEFT));
        var keyRight = allowKeyboard && (Key.isDown(bindings.keyRight) || Key.isDown(Key.RIGHT));
        var keyGas = allowKeyboard && (Key.isDown(bindings.keyGas) || Key.isDown(Key.UP));
        var keyReverse = allowKeyboard && (Key.isDown(bindings.keyBrake) || Key.isDown(Key.DOWN));

        if (keyLeft && !keyRight) digitalSteerTarget = -1.0;
        else if (keyRight && !keyLeft) digitalSteerTarget = 1.0;
        else digitalSteerTarget = 0.0;

        // Digital steering rack simulation with turn-in rate and return-to-center centering
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

        // Analog gamepad stick steering and progressive triggers
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

        // Mobile touch controls blending
        if (Math.abs(touchSteer) > 0.01) steer = touchSteer;
        if (touchThrottle > 0.0) throttle = Math.max(throttle, touchThrottle);
        if (touchBrake > 0.0) brake = Math.max(brake, touchBrake);
        if (touchHandbrake) handbrake = true;
        if (touchBoost) boost = true;

        // Apply user-configured steering sensitivity scalar [0.0 - 1.0]
        steer = Math.max(-1.0, Math.min(1.0, steer * steerSensitivity));
    }

    /**
     * Intercepts key presses or gamepad buttons while remapping menu is active.
     */
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

        // Allow cancellation via Escape or Start button
        if (Key.isDown(Key.ESCAPE) || isBtnDown(BTN_START)) {
            isListeningForRemap = false;
            listeningAction = null;
            flushInputs();
        }
    }

    /**
     * Formats keyboard scan-code into a human-readable display string.
     *
     * @param k Key code.
     * @return Readable name string.
     */
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

    /**
     * Formats gamepad button index into a human-readable display string.
     *
     * @param btn Button index.
     * @return Readable button name string.
     */
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