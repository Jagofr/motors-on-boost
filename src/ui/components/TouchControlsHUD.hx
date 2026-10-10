package ui.components;

import h2d.Object;
import h2d.Graphics;
import h2d.Text;
import input.InputController;
import ui.FontManager;
import ui.components.UITheme;

/**
 * On-screen virtual touch driving controls HUD overlay.
 * Features an ergonomic virtual analog steering joystick on the left (thumb),
 * nitro boost button on the upper left (fingers), gas thumbpad on the lower right,
 * and brake + drift buttons on the right (fingers).
 * Fully independent multi-touch concurrency supporting simultaneous chords
 * (Gas + Steer, Gas + Nitro, Gas + Drift, Drift + Nitro, Brake + Nitro).
 */
class TouchControlsHUD extends Object {
    /** Reference to active input controller. */
    public var inputRef:InputController;

    /** Vector graphics context for virtual button capsules and indicators. */
    public var canvas:Graphics;

    // Text labels for buttons
    var nitroText:Text;
    var gasText:Text;
    var brakeText:Text;
    var driftText:Text;
    var pauseText:Text;

    // Momentary pressed flags for dynamic visual rendering
    public var isGasPressed:Bool = false;
    public var isBrakePressed:Bool = false;
    public var isBoostPressed:Bool = false;
    public var isHandbrakePressed:Bool = false;
    public var isPausePressed:Bool = false;

    /** Callback invoked when the on-screen pause touch button is pressed. */
    public var onPauseTriggered:Void->Void;

    // =========================================================================
    // GEOMETRIC METRICS & BUTTON POSITIONING
    // =========================================================================

    /** Left hand: Virtual analog joystick geometry. */
    public var stickBaseX:Float = 130.0;
    public var stickBaseY:Float = 590.0;
    public var stickBaseRadius:Float = 65.0;
    public var stickKnobRadius:Float = 30.0;
    public var stickMaxTravel:Float = 50.0;
    public var stickKnobX:Float = 130.0;
    public var stickKnobY:Float = 590.0;

    /** Left hand: Nitrous Boost button geometry (positioned above analog stick). */
    public var nitroX:Float = 130.0;
    public var nitroY:Float = 465.0;
    public var nitroRadius:Float = 36.0;

    /** Right hand: Gas / Throttle button geometry (right thumb rest zone). */
    public var gasX:Float = 1320.0;
    public var gasY:Float = 610.0;
    public var gasRadius:Float = 44.0;

    /** Right hand: Brake / Reverse button geometry. */
    public var brakeX:Float = 1200.0;
    public var brakeY:Float = 610.0;
    public var brakeRadius:Float = 36.0;

    /** Right hand: Handbrake Drift button geometry (arched above Gas and Brake). */
    public var driftX:Float = 1260.0;
    public var driftY:Float = 490.0;
    public var driftRadius:Float = 38.0;

    /** Top Right: Dedicated Pause button geometry. */
    public var pauseX:Float = 1390.0;
    public var pauseY:Float = 24.0;
    public var pauseW:Float = 48.0;
    public var pauseH:Float = 44.0;

    // =========================================================================
    // MULTI-TOUCH CONCURRENCY TRACKING
    // =========================================================================

    /** Active touch IDs mapped to assigned control role ("stick", "nitro", "gas", "brake", "drift", "pause"). */
    var activeRoles:Map<Int, String> = new Map();

    /** Pointer identifier currently operating the virtual analog joystick (or null if neutral). */
    var stickPointerId:Null<Int> = null;

    /** Window event listener function reference for cleanup. */
    var windowEventTarget:hxd.Event->Void;

    /** Scratch point reused across frame events to eliminate GC allocations. */
    var scratchPoint:h2d.col.Point = new h2d.col.Point();

    /** Scratch event reused for camera coordinate transformations. */
    var scratchEvent:hxd.Event = new hxd.Event(ECheck, 0, 0);

    #if js
    var nativeCanvas:js.html.CanvasElement;
    var nativeTouchStartHandler:js.html.TouchEvent->Void;
    var nativeTouchMoveHandler:js.html.TouchEvent->Void;
    var nativeTouchEndHandler:js.html.TouchEvent->Void;
    var nativeTouchCancelHandler:js.html.TouchEvent->Void;
    var nativeTouchesActive:Map<Int, Bool> = new Map();
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

        // 1. Nitrous Boost Label (NITRO)
        nitroText = new Text(FontManager.regularFont, this);
        nitroText.text = "NITRO";
        nitroText.textColor = UITheme.COLOR_ACCENT_CYAN;

        // 2. Throttle Label (GAS)
        gasText = new Text(FontManager.regularFont, this);
        gasText.text = "GAS";
        gasText.textColor = UITheme.COLOR_GREEN_SUCCESS;

        // 3. Brake Label (BRAKE)
        brakeText = new Text(FontManager.regularFont, this);
        brakeText.text = "BRAKE";
        brakeText.textColor = UITheme.COLOR_RED_ALERT;

        // 4. Handbrake Drift Label (DRIFT)
        driftText = new Text(FontManager.regularFont, this);
        driftText.text = "DRIFT";
        driftText.textColor = UITheme.COLOR_ACCENT_GOLD;

        // 5. Pause Button Label
        pauseText = new Text(FontManager.titleFont, this);
        pauseText.text = "||";
        pauseText.textColor = UITheme.COLOR_TEXT_NORMAL;

        // Register window event target for Heaps / desktop / test dispatching
        windowEventTarget = onWindowEvent;
        hxd.Window.getInstance().addEventTarget(windowEventTarget);

        // Register native DOM touch listeners on the canvas for mobile Web browsers
        #if js
        try {
            nativeCanvas = cast js.Browser.document.getElementById("webgl");
            if (nativeCanvas != null) {
                nativeTouchStartHandler = function(e:js.html.TouchEvent) {
                    if (!visible || !inputRef.isTouchActive) {
                        inputRef.isTouchActive = true;
                        visible = true;
                    }
                    e.preventDefault();
                    for (t in e.changedTouches) {
                        nativeTouchesActive.set(t.identifier, true);
                        var p = clientToHUD(t.clientX, t.clientY);
                        handlePointerDown(t.identifier, p.x, p.y);
                    }
                };
                nativeTouchMoveHandler = function(e:js.html.TouchEvent) {
                    e.preventDefault();
                    for (t in e.changedTouches) {
                        var p = clientToHUD(t.clientX, t.clientY);
                        handlePointerMove(t.identifier, p.x, p.y);
                    }
                };
                nativeTouchEndHandler = function(e:js.html.TouchEvent) {
                    e.preventDefault();
                    for (t in e.changedTouches) {
                        nativeTouchesActive.remove(t.identifier);
                        handlePointerUp(t.identifier);
                    }
                };
                nativeTouchCancelHandler = function(e:js.html.TouchEvent) {
                    e.preventDefault();
                    for (t in e.changedTouches) {
                        nativeTouchesActive.remove(t.identifier);
                        handlePointerCancel(t.identifier);
                    }
                };

                nativeCanvas.addEventListener("touchstart", nativeTouchStartHandler, { passive: false });
                nativeCanvas.addEventListener("touchmove", nativeTouchMoveHandler, { passive: false });
                nativeCanvas.addEventListener("touchend", nativeTouchEndHandler, { passive: false });
                nativeCanvas.addEventListener("touchcancel", nativeTouchCancelHandler, { passive: false });
            }
        } catch (e:haxe.Exception) {}
        #end
    }

    #if js
    /**
     * Maps browser client coordinates to local HUD scene coordinates.
     */
    function clientToHUD(clientX:Float, clientY:Float):h2d.col.Point {
        if (nativeCanvas != null) {
            var rect = nativeCanvas.getBoundingClientRect();
            var s2d = getScene();
            if (s2d != null && rect.width > 0 && rect.height > 0) {
                var normX = (clientX - rect.left) / rect.width;
                var normY = (clientY - rect.top) / rect.height;
                scratchPoint.x = normX * s2d.width;
                scratchPoint.y = normY * s2d.height;
                globalToLocal(scratchPoint);
                return scratchPoint;
            }
        }
        scratchPoint.x = clientX;
        scratchPoint.y = clientY;
        return scratchPoint;
    }
    #end

    /**
     * Converts raw canvas buffer / window screen pixel coordinates into this object's
     * local scene coordinate system using the 2D scene interactive camera.
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
     * Updates virtual analog steering stick deflection and sets inputRef.touchSteer.
     */
    function updateStickDeflection(px:Float, py:Float) {
        var dx = px - stickBaseX;
        var dy = py - stickBaseY;
        var d = Math.sqrt(dx * dx + dy * dy);

        if (d > stickMaxTravel) {
            var scale = stickMaxTravel / d;
            dx *= scale;
            dy *= scale;
        }

        stickKnobX = stickBaseX + dx;
        stickKnobY = stickBaseY + dy;

        // Proportional analog steering [-1.0 .. 1.0]
        inputRef.touchSteer = Math.max(-1.0, Math.min(1.0, dx / stickMaxTravel));
    }

    /**
     * Handles pointer/finger contact beginning at local coordinate (px, py).
     */
    public function handlePointerDown(tid:Int, px:Float, py:Float) {
        var s2d = getScene();
        var sw = s2d != null ? s2d.width : 1280.0;
        var sh = s2d != null ? s2d.height : 720.0;

        // 1. Pause Button (Top-Right)
        if (px >= pauseX - 14.0 && px <= pauseX + pauseW + 14.0 &&
            py >= pauseY - 14.0 && py <= pauseY + pauseH + 14.0) {
            activeRoles.set(tid, "pause");
            recomputeStates();
            return;
        }

        // 2. Nitro Boost (Left hand, upper-left above stick)
        var dNitro = distSq(px, py, nitroX, nitroY);
        var hitNitroRadiusSq = (nitroRadius + 22.0) * (nitroRadius + 22.0);
        if (dNitro <= hitNitroRadiusSq) {
            activeRoles.set(tid, "nitro");
            recomputeStates();
            return;
        }

        // 3. Drift / Handbrake (Right hand, upper-right above gas/brake)
        var dDrift = distSq(px, py, driftX, driftY);
        var hitDriftRadiusSq = (driftRadius + 24.0) * (driftRadius + 24.0);
        if (dDrift <= hitDriftRadiusSq) {
            activeRoles.set(tid, "drift");
            recomputeStates();
            return;
        }

        // 4. Gas / Throttle (Right hand, bottom-right corner)
        var dGas = distSq(px, py, gasX, gasY);
        var hitGasRadiusSq = (gasRadius + 28.0) * (gasRadius + 28.0);
        if (dGas <= hitGasRadiusSq) {
            activeRoles.set(tid, "gas");
            recomputeStates();
            return;
        }

        // 5. Brake / Reverse (Right hand, bottom-right inner)
        var dBrake = distSq(px, py, brakeX, brakeY);
        var hitBrakeRadiusSq = (brakeRadius + 24.0) * (brakeRadius + 24.0);
        if (dBrake <= hitBrakeRadiusSq) {
            activeRoles.set(tid, "brake");
            recomputeStates();
            return;
        }

        // 6. Virtual Analog Steering Joystick (Left thumb, bottom-left zone)
        var dStick = distSq(px, py, stickBaseX, stickBaseY);
        var hitStickRadiusSq = (stickBaseRadius + 45.0) * (stickBaseRadius + 45.0);
        var isLeftQuadrant = (px < sw * 0.44 && py > (nitroY - 40.0));

        if (dStick <= hitStickRadiusSq || isLeftQuadrant) {
            stickPointerId = tid;
            activeRoles.set(tid, "stick");
            updateStickDeflection(px, py);
            recomputeStates();
            return;
        }
    }

    /**
     * Handles pointer/finger movement at local coordinate (px, py).
     */
    public function handlePointerMove(tid:Int, px:Float, py:Float) {
        if (tid == stickPointerId) {
            updateStickDeflection(px, py);
            renderHUD();
            return;
        }

        if (activeRoles.exists(tid)) {
            var currentRole = activeRoles.get(tid);

            // Button tracking with hysteresis to prevent accidental cancellation from micro-jitters
            if (currentRole == "gas") {
                if (distSq(px, py, gasX, gasY) > (gasRadius + 50.0) * (gasRadius + 50.0)) {
                    if (distSq(px, py, brakeX, brakeY) <= (brakeRadius + 24.0) * (brakeRadius + 24.0)) {
                        activeRoles.set(tid, "brake");
                        recomputeStates();
                    } else if (distSq(px, py, driftX, driftY) <= (driftRadius + 24.0) * (driftRadius + 24.0)) {
                        activeRoles.set(tid, "drift");
                        recomputeStates();
                    }
                }
            } else if (currentRole == "brake") {
                if (distSq(px, py, brakeX, brakeY) > (brakeRadius + 50.0) * (brakeRadius + 50.0)) {
                    if (distSq(px, py, gasX, gasY) <= (gasRadius + 28.0) * (gasRadius + 28.0)) {
                        activeRoles.set(tid, "gas");
                        recomputeStates();
                    } else if (distSq(px, py, driftX, driftY) <= (driftRadius + 24.0) * (driftRadius + 24.0)) {
                        activeRoles.set(tid, "drift");
                        recomputeStates();
                    }
                }
            } else if (currentRole == "drift") {
                if (distSq(px, py, driftX, driftY) > (driftRadius + 50.0) * (driftRadius + 50.0)) {
                    if (distSq(px, py, gasX, gasY) <= (gasRadius + 28.0) * (gasRadius + 28.0)) {
                        activeRoles.set(tid, "gas");
                        recomputeStates();
                    } else if (distSq(px, py, brakeX, brakeY) <= (brakeRadius + 24.0) * (brakeRadius + 24.0)) {
                        activeRoles.set(tid, "brake");
                        recomputeStates();
                    }
                }
            }
        }
    }

    /**
     * Handles pointer/finger release for a specific pointer ID.
     */
    public function handlePointerUp(tid:Int) {
        if (tid == stickPointerId) {
            stickPointerId = null;
            stickKnobX = stickBaseX;
            stickKnobY = stickBaseY;
            inputRef.touchSteer = 0.0;
        }

        if (activeRoles.exists(tid)) {
            var role = activeRoles.get(tid);
            activeRoles.remove(tid);
            recomputeStates();
            if (role == "pause" && onPauseTriggered != null) {
                onPauseTriggered();
            }
        }
    }

    /**
     * Handles pointer/finger cancellation.
     */
    public function handlePointerCancel(tid:Int) {
        handlePointerUp(tid);
    }

    /**
     * Recomputes all active driving inputs atomically from all concurrent touches.
     */
    function recomputeStates() {
        var newGas = false;
        var newBrake = false;
        var newBoost = false;
        var newDrift = false;
        var newPause = false;

        for (role in activeRoles) {
            switch (role) {
                case "gas": newGas = true;
                case "brake": newBrake = true;
                case "nitro": newBoost = true;
                case "drift": newDrift = true;
                case "pause": newPause = true;
            }
        }

        isGasPressed = newGas;
        isBrakePressed = newBrake;
        isBoostPressed = newBoost;
        isHandbrakePressed = newDrift;
        isPausePressed = newPause;

        inputRef.touchThrottle = isGasPressed ? 1.0 : 0.0;
        inputRef.touchBrake = isBrakePressed ? 1.0 : 0.0;
        inputRef.touchBoost = isBoostPressed;
        inputRef.touchHandbrake = isHandbrakePressed;

        if (stickPointerId == null) {
            inputRef.touchSteer = 0.0;
        }

        renderHUD();
    }

    /**
     * Low-level window event handler tracking independent touch pointers concurrently.
     */
    function onWindowEvent(e:hxd.Event) {
        if (parent == null) return;

        var isTouchKind = (e.touchId != null && e.touchId >= 0);
        if (isTouchKind && !inputRef.isTouchActive) {
            inputRef.isTouchActive = true;
        }

        #if js
        // If native DOM touch is actively managing this touch ID, let native handler lead
        if (isTouchKind && nativeTouchesActive.exists(e.touchId)) return;
        #end

        if (!visible) {
            if (inputRef.isTouchActive && parent.visible) {
                visible = true;
                var s2d = getScene();
                if (s2d != null) layout(s2d.width, s2d.height);
            } else {
                return;
            }
        }

        getLocalCoords(e.relX, e.relY, scratchPoint);
        var px = scratchPoint.x;
        var py = scratchPoint.y;

        var tid:Int = isTouchKind ? e.touchId : -1;

        switch (e.kind) {
            case EPush:
                if (tid == -1 && e.button != 0) return;
                handlePointerDown(tid, px, py);

            case EMove:
                handlePointerMove(tid, px, py);

            case ERelease, EReleaseOutside:
                handlePointerUp(tid);

            default:
        }
    }

    override function onRemove() {
        super.onRemove();
        dispose();
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
        try {
            if (nativeCanvas != null) {
                if (nativeTouchStartHandler != null) nativeCanvas.removeEventListener("touchstart", nativeTouchStartHandler);
                if (nativeTouchMoveHandler != null) nativeCanvas.removeEventListener("touchmove", nativeTouchMoveHandler);
                if (nativeTouchEndHandler != null) nativeCanvas.removeEventListener("touchend", nativeTouchEndHandler);
                if (nativeTouchCancelHandler != null) nativeCanvas.removeEventListener("touchcancel", nativeTouchCancelHandler);
                nativeTouchStartHandler = null;
                nativeTouchMoveHandler = null;
                nativeTouchEndHandler = null;
                nativeTouchCancelHandler = null;
                nativeCanvas = null;
            }
        } catch (e:haxe.Exception) {}
        #end
        if (canvas != null) {
            canvas.clear();
        }
    }

    /**
     * Resets all momentary touch button states and controller input registers.
     */
    public function resetTouchStates() {
        activeRoles.clear();
        stickPointerId = null;
        stickKnobX = stickBaseX;
        stickKnobY = stickBaseY;

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
     * Renders virtual touch control button capsules, analog joystick, and border highlights.
     */
    public function renderHUD() {
        canvas.clear();
        if (!visible) return;

        // 1. Virtual Analog Steering Joystick (Left Hand)
        drawAnalogStick();

        // 2. Nitro Boost Button (Left Hand, above joystick)
        drawCircularButton(nitroX, nitroY, nitroRadius, UITheme.COLOR_ACCENT_CYAN, isBoostPressed);
        drawFlameGraphic(nitroX, nitroY - 6.0, nitroRadius * 0.42, isBoostPressed);

        // 3. Gas / Throttle Pad (Right Hand, bottom-right)
        drawCircularButton(gasX, gasY, gasRadius, UITheme.COLOR_GREEN_SUCCESS, isGasPressed);
        drawPedalGraphic(gasX, gasY - 6.0, gasRadius * 0.55, gasRadius * 0.68, isGasPressed);

        // 4. Brake / Reverse Pad (Right Hand, bottom-right inner)
        drawCircularButton(brakeX, brakeY, brakeRadius, UITheme.COLOR_RED_ALERT, isBrakePressed);
        drawBrakeDiscGraphic(brakeX, brakeY - 5.0, brakeRadius, isBrakePressed);

        // 5. Drift / Handbrake Pad (Right Hand, arched above Gas & Brake)
        drawCircularButton(driftX, driftY, driftRadius, UITheme.COLOR_ACCENT_GOLD, isHandbrakePressed);
        drawHandbrakeGraphic(driftX, driftY - 5.0, driftRadius * 0.65, isHandbrakePressed);

        // 6. Pause Button (Top-Right)
        drawPauseButton();
    }

    /**
     * Draws the virtual analog steering joystick base, center ticks, and movable thumb knob.
     */
    function drawAnalogStick() {
        var isGrabbed = (stickPointerId != null);
        var baseAlpha = isGrabbed ? 0.45 : 0.28;
        var borderAlpha = isGrabbed ? 0.90 : 0.50;

        // Base circular zone
        canvas.beginFill(0x060E18, baseAlpha);
        canvas.lineStyle(2.0, UITheme.COLOR_ACCENT_CYAN, borderAlpha);
        canvas.drawCircle(stickBaseX, stickBaseY, stickBaseRadius);
        canvas.endFill();

        // Outer cyber tick ring
        canvas.lineStyle(1.0, UITheme.COLOR_ACCENT_CYAN, borderAlpha * 0.4);
        canvas.drawCircle(stickBaseX, stickBaseY, stickBaseRadius - 6.0);

        // Directional crosshair ticks
        canvas.lineStyle(1.5, UITheme.COLOR_ACCENT_CYAN, borderAlpha * 0.7);
        canvas.moveTo(stickBaseX - stickBaseRadius + 6.0, stickBaseY);
        canvas.lineTo(stickBaseX - stickBaseRadius + 16.0, stickBaseY);
        canvas.moveTo(stickBaseX + stickBaseRadius - 16.0, stickBaseY);
        canvas.lineTo(stickBaseX + stickBaseRadius - 6.0, stickBaseY);

        // Center neutral reference dot
        canvas.beginFill(UITheme.COLOR_ACCENT_CYAN, 0.45);
        canvas.drawCircle(stickBaseX, stickBaseY, 4.0);
        canvas.endFill();

        // Movable thumb knob
        var knobAlpha = isGrabbed ? UITheme.ALPHA_TOUCH_PRESSED : UITheme.ALPHA_TOUCH_IDLE;
        var knobBorderAlpha = isGrabbed ? 0.98 : UITheme.ALPHA_TOUCH_BORDER;
        canvas.beginFill(UITheme.COLOR_ACCENT_CYAN, knobAlpha);
        canvas.lineStyle(2.5, UITheme.COLOR_ACCENT_CYAN, knobBorderAlpha);
        canvas.drawCircle(stickKnobX, stickKnobY, stickKnobRadius);
        canvas.endFill();

        // Inner knob accent dot
        canvas.beginFill(0xFFFFFF, isGrabbed ? 0.95 : 0.60);
        canvas.drawCircle(stickKnobX, stickKnobY, 5.0);
        canvas.endFill();
    }

    /**
     * Draws an individual circular action button with radial fill and glowing perimeter.
     */
    inline function drawCircularButton(cx:Float, cy:Float, radius:Float, color:Int, isPressed:Bool) {
        var fillAlpha = isPressed ? 0.88 : 0.55;
        var borderAlpha = isPressed ? 1.0 : 0.70;

        // Frosted dark glass circular plate
        canvas.beginFill(0x060E18, fillAlpha);
        canvas.lineStyle(2.5, color, borderAlpha);
        canvas.drawCircle(cx, cy, radius);
        canvas.endFill();

        // Inner specular ring highlight
        canvas.lineStyle(1.0, 0xFFFFFF, isPressed ? 0.35 : 0.12);
        canvas.drawCircle(cx, cy, radius - 4.0);
    }

    /**
     * Draws procedural flame icon inside Nitro boost button.
     */
    function drawFlameGraphic(cx:Float, cy:Float, size:Float, isPressed:Bool) {
        var flameColor = isPressed ? 0xFF8800 : UITheme.COLOR_ACCENT_CYAN;
        var coreColor = isPressed ? 0xFFFF66 : 0xFFFFFF;

        canvas.beginFill(flameColor, 0.90);
        canvas.moveTo(cx, cy - size);
        canvas.curveTo(cx + size * 0.6, cy - size * 0.2, cx + size * 0.6, cy + size * 0.4);
        canvas.curveTo(cx + size * 0.6, cy + size, cx, cy + size);
        canvas.curveTo(cx - size * 0.6, cy + size, cx - size * 0.6, cy + size * 0.4);
        canvas.curveTo(cx - size * 0.6, cy - size * 0.2, cx, cy - size);
        canvas.endFill();

        canvas.beginFill(coreColor, 0.95);
        canvas.moveTo(cx, cy - size * 0.2);
        canvas.curveTo(cx + size * 0.3, cy + size * 0.2, cx + size * 0.3, cy + size * 0.6);
        canvas.curveTo(cx + size * 0.3, cy + size * 0.8, cx, cy + size * 0.8);
        canvas.curveTo(cx - size * 0.3, cy + size * 0.8, cx - size * 0.3, cy + size * 0.6);
        canvas.curveTo(cx - size * 0.3, cy + size * 0.2, cx, cy - size * 0.2);
        canvas.endFill();
    }

    /**
     * Draws accelerator throttle pedal icon inside Gas button.
     */
    function drawPedalGraphic(cx:Float, cy:Float, w:Float, h:Float, isPressed:Bool) {
        var pedalColor = isPressed ? 0x00FF88 : UITheme.COLOR_GREEN_SUCCESS;

        canvas.beginFill(0x182430, 0.90);
        canvas.lineStyle(1.5, pedalColor, 0.90);
        canvas.drawRoundedRect(cx - (w * 0.5), cy - (h * 0.5), w, h, 4.0);
        canvas.endFill();

        // Rubber grip ridges
        canvas.lineStyle(1.5, pedalColor, 0.70);
        canvas.moveTo(cx - (w * 0.32), cy - (h * 0.24));
        canvas.lineTo(cx + (w * 0.32), cy - (h * 0.24));
        canvas.moveTo(cx - (w * 0.32), cy);
        canvas.lineTo(cx + (w * 0.32), cy);
        canvas.moveTo(cx - (w * 0.32), cy + (h * 0.24));
        canvas.lineTo(cx + (w * 0.32), cy + (h * 0.24));
    }

    /**
     * Draws disc brake rotor with red caliper inside Brake button.
     */
    function drawBrakeDiscGraphic(cx:Float, cy:Float, radius:Float, isPressed:Bool) {
        // Metallic brake rotor disc
        canvas.lineStyle(2.0, 0x8898A8, 0.75);
        canvas.drawCircle(cx, cy, radius * 0.60);
        canvas.drawCircle(cx, cy, radius * 0.28);

        // Perforated cross-drilled cooling vent holes
        canvas.beginFill(0x060E18, 0.95);
        for (i in 0...6) {
            var ang = i * (Math.PI / 3.0);
            var hx = cx + Math.cos(ang) * (radius * 0.44);
            var hy = cy + Math.sin(ang) * (radius * 0.44);
            canvas.drawCircle(hx, hy, 1.8);
        }
        canvas.endFill();

        // Red brake caliper on side
        canvas.beginFill(isPressed ? 0xFF0033 : UITheme.COLOR_RED_ALERT, 0.95);
        canvas.lineStyle(1.5, 0xFF6677, 0.95);
        canvas.drawRoundedRect(cx + (radius * 0.20), cy - (radius * 0.55), radius * 0.44, radius * 0.55, 3.0);
        canvas.endFill();
    }

    /**
     * Draws handbrake drift icon inside Drift button.
     */
    function drawHandbrakeGraphic(cx:Float, cy:Float, size:Float, isPressed:Bool) {
        var driftColor = isPressed ? 0xFFEE00 : UITheme.COLOR_ACCENT_GOLD;

        // Twin skid mark drift arcs
        canvas.lineStyle(2.0, driftColor, 0.85);
        canvas.moveTo(cx - (size * 0.55), cy + (size * 0.35));
        canvas.curveTo(cx - (size * 0.15), cy - (size * 0.25), cx + (size * 0.35), cy - (size * 0.35));

        canvas.moveTo(cx - (size * 0.35), cy + (size * 0.55));
        canvas.curveTo(cx, cy - (size * 0.05), cx + (size * 0.55), cy - (size * 0.15));

        // Center lever accent
        canvas.beginFill(driftColor, 0.95);
        canvas.drawCircle(cx - (size * 0.10), cy + (size * 0.10), 2.5);
        canvas.endFill();
    }

    /**
     * Draws the dedicated top-right pause button capsule.
     */
    inline function drawPauseButton() {
        var fillAlpha = isPausePressed ? UITheme.ALPHA_TOUCH_PRESSED : UITheme.ALPHA_TOUCH_IDLE;
        var borderAlpha = isPausePressed ? 0.95 : UITheme.ALPHA_TOUCH_BORDER;

        canvas.beginFill(UITheme.COLOR_TEXT_NORMAL, fillAlpha);
        canvas.lineStyle(2.0, UITheme.COLOR_TEXT_NORMAL, borderAlpha);
        canvas.drawRoundedRect(pauseX, pauseY, pauseW, pauseH, 8.0);
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

        // 1. Left Hand: Virtual Analog Joystick (Left thumb)
        stickBaseRadius = UITheme.TOUCH_STICK_BASE_RADIUS;
        stickKnobRadius = UITheme.TOUCH_STICK_KNOB_RADIUS;
        stickMaxTravel = UITheme.TOUCH_STICK_MAX_TRAVEL;

        stickBaseX = margin + stickBaseRadius + 16.0;
        stickBaseY = sh - margin - stickBaseRadius - 16.0;

        if (stickPointerId == null) {
            stickKnobX = stickBaseX;
            stickKnobY = stickBaseY;
        }

        // 2. Left Hand: Nitro Boost (Left fingers, above joystick)
        nitroRadius = 36.0;
        nitroX = stickBaseX;
        nitroY = stickBaseY - stickBaseRadius - nitroRadius - 28.0;
        nitroText.x = nitroX - (nitroText.textWidth * 0.5);
        nitroText.y = nitroY + 6.0;

        // 3. Right Hand: Gas / Throttle Pad (Right thumb)
        gasRadius = 44.0;
        gasX = sw - margin - gasRadius - 16.0;
        gasY = sh - margin - gasRadius - 16.0;
        gasText.x = gasX - (gasText.textWidth * 0.5);
        gasText.y = gasY + 9.0;

        // 4. Right Hand: Brake / Reverse Pad (Right thumb / fingers)
        brakeRadius = 36.0;
        brakeX = gasX - gasRadius - brakeRadius - 32.0;
        brakeY = gasY;
        brakeText.x = brakeX - (brakeText.textWidth * 0.5);
        brakeText.y = brakeY + 7.0;

        // 5. Right Hand: Handbrake Drift Pad (Right index finger, arched above Gas & Brake)
        driftRadius = 38.0;
        driftX = (gasX + brakeX) * 0.5;
        driftY = gasY - gasRadius - driftRadius - 24.0;
        driftText.x = driftX - (driftText.textWidth * 0.5);
        driftText.y = driftY + 8.0;

        // 6. Top Right: Pause Button
        pauseW = 48.0;
        pauseH = 44.0;
        pauseX = sw - pauseW - margin;
        pauseY = margin;
        pauseText.x = pauseX + (pauseW - pauseText.textWidth) * 0.5;
        pauseText.y = pauseY + (pauseH - pauseText.textHeight) * 0.5;

        renderHUD();
    }
}
