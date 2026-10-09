package ui.components;

import h2d.Object;
import h2d.Graphics;
import h2d.Text;
import h2d.Interactive;
import input.InputController;
import ui.FontManager;
import ui.components.UITheme;

/**
 * On-screen virtual touch driving controls HUD overlay.
 * Automatically activates on touchscreen devices or when touch input is detected.
 * Provides virtual steering zones (Left/Right), throttle, brake, nitro boost, handbrake,
 * and an accessible in-game pause button with zero-allocation, robust multi-touch tracking.
 */
class TouchControlsHUD extends Object {
    /** Reference to active input controller. */
    public var inputRef:InputController;

    /** Vector graphics context for virtual button capsules and indicators. */
    public var canvas:Graphics;

    // Interactive button touch zones (used as bounding geometry containers)
    var steerLeftInter:Interactive;
    var steerRightInter:Interactive;
    var gasInter:Interactive;
    var brakeInter:Interactive;
    var boostInter:Interactive;
    var handbrakeInter:Interactive;
    var pauseInter:Interactive;

    // Text labels for buttons
    var steerLeftText:Text;
    var steerRightText:Text;
    var gasText:Text;
    var brakeText:Text;
    var boostText:Text;
    var handbrakeText:Text;
    var pauseText:Text;

    // Momentary pressed flags for dynamic visual rendering
    var isLeftPressed:Bool = false;
    var isRightPressed:Bool = false;
    var isGasPressed:Bool = false;
    var isBrakePressed:Bool = false;
    var isBoostPressed:Bool = false;
    var isHandbrakePressed:Bool = false;
    var isPausePressed:Bool = false;

    /** Callback invoked when the on-screen pause touch button is pressed. */
    public var onPauseTriggered:Void->Void;

    /** Active touch IDs mapped to button kind for multi-touch concurrency. */
    var activeTouches:Map<Int, String> = new Map();

    /** Window event listener function reference for cleanup. */
    var windowEventTarget:hxd.Event->Void;

    /** Scratch point reused across frame events to eliminate GC allocations. */
    var scratchPoint:h2d.col.Point = new h2d.col.Point();

    /** Scratch event reused for camera coordinate transformations. */
    var scratchEvent:hxd.Event = new hxd.Event(ECheck, 0, 0);

    #if js
    var touchCancelHandler:js.html.Event->Void;
    #end

    /**
     * Instantiates the touch controls virtual HUD.
     *
     * @param input Input controller reference to feed touch states into.
     * @param parent Optional parent 2D scene object.
     */
    public function new(input:InputController, ?parent:Object) {
        super(parent);
        this.inputRef = input;

        canvas = new Graphics(this);

        // 1. Steering Left
        steerLeftInter = new Interactive(UITheme.TOUCH_STEER_BTN_WIDTH, UITheme.TOUCH_STEER_BTN_HEIGHT, this);
        steerLeftText = new Text(FontManager.titleFont, this);
        steerLeftText.text = "<";
        steerLeftText.textColor = UITheme.COLOR_ACCENT_CYAN;

        // 2. Steering Right
        steerRightInter = new Interactive(UITheme.TOUCH_STEER_BTN_WIDTH, UITheme.TOUCH_STEER_BTN_HEIGHT, this);
        steerRightText = new Text(FontManager.titleFont, this);
        steerRightText.text = ">";
        steerRightText.textColor = UITheme.COLOR_ACCENT_CYAN;

        // 3. Throttle (GAS)
        gasInter = new Interactive(UITheme.TOUCH_BTN_SIZE, UITheme.TOUCH_BTN_SIZE, this);
        gasText = new Text(FontManager.regularFont, this);
        gasText.text = "GAS";
        gasText.textColor = UITheme.COLOR_GREEN_SUCCESS;

        // 4. Brake / Reverse
        brakeInter = new Interactive(UITheme.TOUCH_BTN_SIZE, UITheme.TOUCH_BTN_SIZE, this);
        brakeText = new Text(FontManager.regularFont, this);
        brakeText.text = "BRAKE";
        brakeText.textColor = UITheme.COLOR_RED_ALERT;

        // 5. Nitrous Boost (NITRO)
        boostInter = new Interactive(UITheme.TOUCH_BTN_SIZE, UITheme.TOUCH_BTN_SIZE, this);
        boostText = new Text(FontManager.regularFont, this);
        boostText.text = "NITRO";
        boostText.textColor = UITheme.COLOR_ACCENT_CYAN;

        // 6. Handbrake Drift (DRIFT)
        handbrakeInter = new Interactive(UITheme.TOUCH_BTN_SIZE, UITheme.TOUCH_BTN_SIZE, this);
        handbrakeText = new Text(FontManager.regularFont, this);
        handbrakeText.text = "DRIFT";
        handbrakeText.textColor = UITheme.COLOR_ACCENT_GOLD;

        // 7. Pause Button
        pauseInter = new Interactive(UITheme.TOUCH_PAUSE_BTN_SIZE, UITheme.TOUCH_PAUSE_BTN_SIZE, this);
        pauseText = new Text(FontManager.titleFont, this);
        pauseText.text = "||";
        pauseText.textColor = UITheme.COLOR_TEXT_NORMAL;

        // Register window event target for robust multi-touch pointer tracking
        windowEventTarget = onWindowEvent;
        hxd.Window.getInstance().addEventTarget(windowEventTarget);

        #if js
        try {
            touchCancelHandler = function(_) {
                resetTouchStates();
            };
            js.Browser.window.addEventListener("touchcancel", touchCancelHandler, { passive: true });
        } catch (e:haxe.Exception) {}
        #end
    }

    /**
     * Converts raw canvas buffer / window screen pixel coordinates into this object's
     * local scene coordinate system using the 2D scene interactive camera.
     *
     * @param screenX Raw X coordinate from hxd.Event.
     * @param screenY Raw Y coordinate from hxd.Event.
     * @param out Point object populated with the calculated local coordinates.
     */
    function getLocalCoords(screenX:Float, screenY:Float, out:h2d.col.Point):Void {
        var s2d = getScene();
        if (s2d == null) {
            out.x = screenX;
            out.y = screenY;
            return;
        }

        scratchEvent.relX = screenX;
        scratchEvent.relY = screenY;

        var cam = s2d.interactiveCamera != null ? s2d.interactiveCamera : s2d.camera;
        if (cam != null) {
            cam.eventToCamera(scratchEvent);
            out.x = scratchEvent.relX;
            out.y = scratchEvent.relY;
        } else {
            @:privateAccess {
                out.x = (screenX - s2d.offsetX) / s2d.viewportScaleX;
                out.y = (screenY - s2d.offsetY) / s2d.viewportScaleY;
            }
        }

        globalToLocal(out);
    }

    /**
     * Computes the squared Euclidean distance between two 2D points.
     */
    static inline function distSq(x1:Float, y1:Float, x2:Float, y2:Float):Float {
        var dx = x1 - x2;
        var dy = y1 - y2;
        return dx * dx + dy * dy;
    }

    /**
     * Resolves which virtual HUD button contains the local touch point (px, py).
     * Uses distance-to-center evaluation for circular action buttons to prevent overlap bias,
     * and generous rectangular bounds for steering and pause.
     *
     * @param px Local X coordinate.
     * @param py Local Y coordinate.
     * @return Button identifier string or null if untouched.
     */
    function hitTestAll(px:Float, py:Float):Null<String> {
        // 1. Pause Button (Top-Right)
        var pPad = 18.0;
        if (px >= pauseInter.x - pPad && px <= pauseInter.x + pauseInter.width + pPad &&
            py >= pauseInter.y - pPad && py <= pauseInter.y + pauseInter.height + pPad) {
            return "pause";
        }

        // 2. Steering Left & Right (Bottom-Left)
        var steerTop = steerLeftInter.y - 24.0;
        var steerBottom = steerLeftInter.y + steerLeftInter.height + 24.0;
        if (py >= steerTop && py <= steerBottom) {
            var steerMidX = (steerLeftInter.x + steerLeftInter.width + steerRightInter.x) * 0.5;
            var steerLeftMin = steerLeftInter.x - 24.0;
            var steerRightMax = steerRightInter.x + steerRightInter.width + 24.0;

            if (px >= steerLeftMin && px < steerMidX) {
                return "left";
            } else if (px >= steerMidX && px <= steerRightMax) {
                return "right";
            }
        }

        // 3. Driving Action Buttons (Bottom-Right: Gas, Brake, Nitro, Drift)
        // Action buttons have diameter 72px (radius 36px). Touch radius is generous 54px.
        var maxRadiusSq = 54.0 * 54.0; // 2916.0
        var bestBtn:Null<String> = null;
        var bestDistSq = maxRadiusSq;

        // Gas (Top-Right of action block)
        var gasCx = gasInter.x + gasInter.width * 0.5;
        var gasCy = gasInter.y + gasInter.height * 0.5;
        var dGas = distSq(px, py, gasCx, gasCy);
        if (dGas <= bestDistSq) {
            bestDistSq = dGas;
            bestBtn = "gas";
        }

        // Brake (Bottom-Right of action block)
        var brakeCx = brakeInter.x + brakeInter.width * 0.5;
        var brakeCy = brakeInter.y + brakeInter.height * 0.5;
        var dBrake = distSq(px, py, brakeCx, brakeCy);
        if (dBrake <= bestDistSq) {
            bestDistSq = dBrake;
            bestBtn = "brake";
        }

        // Boost / Nitro (Top-Left of action block)
        var boostCx = boostInter.x + boostInter.width * 0.5;
        var boostCy = boostInter.y + boostInter.height * 0.5;
        var dBoost = distSq(px, py, boostCx, boostCy);
        if (dBoost <= bestDistSq) {
            bestDistSq = dBoost;
            bestBtn = "boost";
        }

        // Handbrake / Drift (Bottom-Left of action block)
        var driftCx = handbrakeInter.x + handbrakeInter.width * 0.5;
        var driftCy = handbrakeInter.y + handbrakeInter.height * 0.5;
        var dDrift = distSq(px, py, driftCx, driftCy);
        if (dDrift <= bestDistSq) {
            bestDistSq = dDrift;
            bestBtn = "drift";
        }

        return bestBtn;
    }

    /**
     * Recomputes all button states and controller input registers atomically
     * by evaluating all active touches currently held down.
     * Prevents any race condition where one finger's movement or release affects another finger's input.
     */
    function recomputeActiveStates() {
        var newLeft = false;
        var newRight = false;
        var newGas = false;
        var newBrake = false;
        var newBoost = false;
        var newDrift = false;
        var newPause = false;

        for (btn in activeTouches) {
            switch (btn) {
                case "left": newLeft = true;
                case "right": newRight = true;
                case "gas": newGas = true;
                case "brake": newBrake = true;
                case "boost": newBoost = true;
                case "drift": newDrift = true;
                case "pause": newPause = true;
            }
        }

        isLeftPressed = newLeft;
        isRightPressed = newRight;
        isGasPressed = newGas;
        isBrakePressed = newBrake;
        isBoostPressed = newBoost;
        isHandbrakePressed = newDrift;
        isPausePressed = newPause;

        // Apply to input controller registers
        inputRef.touchThrottle = isGasPressed ? 1.0 : 0.0;
        inputRef.touchBrake = isBrakePressed ? 1.0 : 0.0;
        inputRef.touchBoost = isBoostPressed;
        inputRef.touchHandbrake = isHandbrakePressed;

        if (isLeftPressed && !isRightPressed) {
            inputRef.touchSteer = -1.0;
        } else if (isRightPressed && !isLeftPressed) {
            inputRef.touchSteer = 1.0;
        } else {
            inputRef.touchSteer = 0.0;
        }

        renderHUD();
    }

    /**
     * Low-level window event handler tracking independent touch pointers concurrently.
     * Accurately transforms screen coordinates through the active 2D scene camera.
     *
     * @param e Engine window event dispatched by Heaps.
     */
    function onWindowEvent(e:hxd.Event) {
        if (parent == null) return;

        // Detect touch activation dynamically
        var isTouchKind = (e.touchId != null && e.touchId >= 0);
        if (isTouchKind && !inputRef.isTouchActive) {
            inputRef.isTouchActive = true;
        }

        if (!visible) {
            // If touch detected during gameplay, awaken HUD
            if (inputRef.isTouchActive && parent.visible) {
                visible = true;
                var s2d = getScene();
                if (s2d != null) layout(s2d.width, s2d.height);
            } else {
                return;
            }
        }

        // Map event canvas coordinates to local HUD coordinates
        getLocalCoords(e.relX, e.relY, scratchPoint);
        var px = scratchPoint.x;
        var py = scratchPoint.y;

        // Normalize pointer identifier: >= 0 for multi-touch finger IDs, -1 for primary mouse pointer
        var tid:Int = isTouchKind ? e.touchId : -1;

        switch (e.kind) {
            case EPush:
                // For mouse clicks, only respond to primary left button (button 0)
                if (tid == -1 && e.button != 0) return;

                var btn = hitTestAll(px, py);
                if (btn != null) {
                    activeTouches.set(tid, btn);
                    recomputeActiveStates();
                }

            case EMove:
                if (activeTouches.exists(tid)) {
                    var prevBtn = activeTouches.get(tid);
                    var newBtn = hitTestAll(px, py);
                    if (newBtn != prevBtn) {
                        if (newBtn != null) {
                            activeTouches.set(tid, newBtn);
                        } else {
                            activeTouches.remove(tid);
                        }
                        recomputeActiveStates();
                    }
                } else if (isTouchKind) {
                    // Finger dragged from outside onto a virtual control capsule
                    var newBtn = hitTestAll(px, py);
                    if (newBtn != null) {
                        activeTouches.set(tid, newBtn);
                        recomputeActiveStates();
                    }
                }

            case ERelease, EReleaseOutside:
                if (activeTouches.exists(tid)) {
                    var btn = activeTouches.get(tid);
                    activeTouches.remove(tid);
                    recomputeActiveStates();
                    if (btn == "pause" && onPauseTriggered != null) {
                        onPauseTriggered();
                    }
                }

            default:
        }
    }

    override function onRemove() {
        super.onRemove();
        if (windowEventTarget != null) {
            hxd.Window.getInstance().removeEventTarget(windowEventTarget);
            windowEventTarget = null;
        }
        #if js
        if (touchCancelHandler != null) {
            try {
                js.Browser.window.removeEventListener("touchcancel", touchCancelHandler);
                touchCancelHandler = null;
            } catch (e:haxe.Exception) {}
        }
        #end
    }

    /**
     * Explicit disposal method removing all window event bindings and graphics memory.
     */
    public function dispose():Void {
        resetTouchStates();
        if (windowEventTarget != null) {
            hxd.Window.getInstance().removeEventTarget(windowEventTarget);
            windowEventTarget = null;
        }
        #if js
        if (touchCancelHandler != null) {
            try {
                js.Browser.window.removeEventListener("touchcancel", touchCancelHandler);
                touchCancelHandler = null;
            } catch (e:haxe.Exception) {}
        }
        #end
        if (canvas != null) {
            canvas.clear();
        }
    }

    /**
     * Resets all momentary touch button states and controller input registers.
     */
    public function resetTouchStates() {
        activeTouches.clear();
        isLeftPressed = false;
        isRightPressed = false;
        isGasPressed = false;
        isBrakePressed = false;
        isBoostPressed = false;
        isHandbrakePressed = false;
        isPausePressed = false;

        inputRef.touchSteer = 0.0;
        inputRef.touchThrottle = 0.0;
        inputRef.touchBrake = 0.0;
        inputRef.touchBoost = false;
        inputRef.touchHandbrake = false;

        renderHUD();
    }

    /**
     * Renders virtual touch control button capsules and border highlights.
     */
    public function renderHUD() {
        canvas.clear();
        if (!visible) return;

        // 1. Steering Left
        drawButton(steerLeftInter.x, steerLeftInter.y, steerLeftInter.width, steerLeftInter.height,
            UITheme.COLOR_ACCENT_CYAN, isLeftPressed, 12.0);

        // 2. Steering Right
        drawButton(steerRightInter.x, steerRightInter.y, steerRightInter.width, steerRightInter.height,
            UITheme.COLOR_ACCENT_CYAN, isRightPressed, 12.0);

        // 3. Throttle
        drawButton(gasInter.x, gasInter.y, gasInter.width, gasInter.height,
            UITheme.COLOR_GREEN_SUCCESS, isGasPressed, gasInter.width * 0.5);

        // 4. Brake
        drawButton(brakeInter.x, brakeInter.y, brakeInter.width, brakeInter.height,
            UITheme.COLOR_RED_ALERT, isBrakePressed, brakeInter.width * 0.5);

        // 5. Nitro Boost
        drawButton(boostInter.x, boostInter.y, boostInter.width, boostInter.height,
            UITheme.COLOR_ACCENT_CYAN, isBoostPressed, boostInter.width * 0.5);

        // 6. Handbrake Drift
        drawButton(handbrakeInter.x, handbrakeInter.y, handbrakeInter.width, handbrakeInter.height,
            UITheme.COLOR_ACCENT_GOLD, isHandbrakePressed, handbrakeInter.width * 0.5);

        // 7. Pause Button
        drawButton(pauseInter.x, pauseInter.y, pauseInter.width, pauseInter.height,
            UITheme.COLOR_TEXT_NORMAL, isPausePressed, 8.0);
    }

    /**
     * Draws an individual button capsule with fill and boundary line.
     *
     * @param bx Position X in pixels.
     * @param by Position Y in pixels.
     * @param bw Width in pixels.
     * @param bh Height in pixels.
     * @param color Base accent color.
     * @param isPressed True if pressed.
     * @param radius Corner radius.
     */
    inline function drawButton(bx:Float, by:Float, bw:Float, bh:Float, color:Int, isPressed:Bool, radius:Float) {
        var fillAlpha = isPressed ? UITheme.ALPHA_TOUCH_PRESSED : UITheme.ALPHA_TOUCH_IDLE;
        var borderAlpha = isPressed ? 0.95 : UITheme.ALPHA_TOUCH_BORDER;

        canvas.beginFill(color, fillAlpha);
        canvas.lineStyle(2.0, color, borderAlpha);
        canvas.drawRoundedRect(bx, by, bw, bh, radius);
        canvas.endFill();
    }

    /**
     * Positions virtual touch buttons and text relative to viewport boundaries.
     *
     * @param sw Screen width in pixels.
     * @param sh Screen height in pixels.
     */
    public function layout(sw:Float, sh:Float) {
        var margin = 28.0;

        // Bottom Left: Steering Controls
        var steerW = UITheme.TOUCH_STEER_BTN_WIDTH;
        var steerH = UITheme.TOUCH_STEER_BTN_HEIGHT;
        var steerY = sh - steerH - margin;

        steerLeftInter.x = margin;
        steerLeftInter.y = steerY;
        steerLeftText.x = steerLeftInter.x + (steerW - steerLeftText.textWidth) * 0.5;
        steerLeftText.y = steerLeftInter.y + (steerH - steerLeftText.textHeight) * 0.5;

        steerRightInter.x = margin + steerW + 16.0;
        steerRightInter.y = steerY;
        steerRightText.x = steerRightInter.x + (steerW - steerRightText.textWidth) * 0.5;
        steerRightText.y = steerRightInter.y + (steerH - steerRightText.textHeight) * 0.5;

        // Bottom Right: Driving Action Controls (Throttle, Brake, Nitro, Drift)
        var btnSize = UITheme.TOUCH_BTN_SIZE;

        // Gas & Brake arranged in a column on the far right
        var farRightX = sw - btnSize - margin;
        gasInter.x = farRightX;
        gasInter.y = sh - (btnSize * 2.0) - margin - 16.0;
        gasText.x = gasInter.x + (btnSize - gasText.textWidth) * 0.5;
        gasText.y = gasInter.y + (btnSize - gasText.textHeight) * 0.5;

        brakeInter.x = farRightX;
        brakeInter.y = sh - btnSize - margin;
        brakeText.x = brakeInter.x + (btnSize - brakeText.textWidth) * 0.5;
        brakeText.y = brakeInter.y + (btnSize - brakeText.textHeight) * 0.5;

        // Boost & Drift arranged immediately to the left of Gas/Brake
        var innerActionX = farRightX - btnSize - 16.0;
        boostInter.x = innerActionX;
        boostInter.y = gasInter.y;
        boostText.x = boostInter.x + (btnSize - boostText.textWidth) * 0.5;
        boostText.y = boostInter.y + (btnSize - boostText.textHeight) * 0.5;

        handbrakeInter.x = innerActionX;
        handbrakeInter.y = brakeInter.y;
        handbrakeText.x = handbrakeInter.x + (btnSize - handbrakeText.textWidth) * 0.5;
        handbrakeText.y = handbrakeInter.y + (btnSize - handbrakeText.textHeight) * 0.5;

        // Top Right: Dedicated Pause Button
        var pauseSize = UITheme.TOUCH_PAUSE_BTN_SIZE;
        pauseInter.x = sw - pauseSize - margin;
        pauseInter.y = margin;
        pauseText.x = pauseInter.x + (pauseSize - pauseText.textWidth) * 0.5;
        pauseText.y = pauseInter.y + (pauseSize - pauseText.textHeight) * 0.5;

        renderHUD();
    }
}
