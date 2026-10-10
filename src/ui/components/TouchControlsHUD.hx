package ui.components;

import h2d.Object;
import h2d.Graphics;
import h2d.Bitmap;
import h2d.Tile;
import input.InputController;
import ui.components.UITheme;

/**
 * On-screen virtual touch driving controls HUD overlay.
 * Features an ergonomic virtual analog steering joystick on the lower left (thumb),
 * nitro boost button on the left below the minimap, and an ergonomic right-hand cluster:
 * upper-right brake disc, mid-right handbrake lever, and lower-right gas pedal.
 * Uses custom 512x512 vector icons loaded from `res/icons` with frosted glass plate styling.
 * Fully independent multi-touch concurrency supporting simultaneous chords
 * (Gas + Steer, Gas + Nitro, Gas + Drift, Drift + Nitro, Brake + Nitro, etc.).
 */
class TouchControlsHUD extends Object {
    /** Reference to active input controller. */
    public var inputRef:InputController;

    /** Vector graphics context for virtual button plates and indicators. */
    public var canvas:Graphics;

    // Custom Icon Bitmaps loaded from res/icons
    var nitroIconBmp:Bitmap;
    var gasIconBmp:Bitmap;
    var brakeIconBmp:Bitmap;
    var driftIconBmp:Bitmap;

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

    /** Left hand: Virtual analog joystick geometry (lower-left thumb zone). */
    public var stickBaseX:Float = 96.0;
    public var stickBaseY:Float = 590.0;
    public var stickBaseRadius:Float = 64.0;
    public var stickKnobRadius:Float = 34.0;
    public var stickMaxTravel:Float = 48.0;
    public var stickKnobX:Float = 96.0;
    public var stickKnobY:Float = 590.0;

    /** Left hand: Nitrous Boost button geometry (left edge, situated below minimap). */
    public var nitroX:Float = 78.0;
    public var nitroY:Float = 220.0;
    public var nitroRadius:Float = 46.0;

    /** Right hand: Gas / Throttle button geometry (lower-right thumb rest zone). */
    public var gasX:Float = 1140.0;
    public var gasY:Float = 640.0;
    public var gasRadius:Float = 48.0;

    /** Right hand: Brake / Reverse button geometry (upper-right quadrant). */
    public var brakeX:Float = 1050.0;
    public var brakeY:Float = 108.0;
    public var brakeRadius:Float = 46.0;

    /** Right hand: Handbrake Drift button geometry (mid-right edge). */
    public var driftX:Float = 1210.0;
    public var driftY:Float = 260.0;
    public var driftRadius:Float = 46.0;

    /** Top Right: Dedicated circular Pause button geometry. */
    public var pauseX:Float = 1234.0;
    public var pauseY:Float = 46.0;
    public var pauseRadius:Float = 22.0;
    public var pauseW:Float = 44.0;
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

        // Load custom PNG icons from res/icons (512x512 source)
        try {
            var burnTile = hxd.Res.load("icons/burn.png").toTile();
            burnTile.setCenterRatio(0.5, 0.5);
            nitroIconBmp = new Bitmap(burnTile, this);
            nitroIconBmp.smooth = true;
        } catch (e:haxe.Exception) {
            trace("[TouchControlsHUD] Failed to load icons/burn.png: " + e.message);
        }

        try {
            var gasTile = hxd.Res.load("icons/gas-pedal.png").toTile();
            gasTile.setCenterRatio(0.5, 0.5);
            gasIconBmp = new Bitmap(gasTile, this);
            gasIconBmp.smooth = true;
        } catch (e:haxe.Exception) {
            trace("[TouchControlsHUD] Failed to load icons/gas-pedal.png: " + e.message);
        }

        try {
            var brakeTile = hxd.Res.load("icons/brake.png").toTile();
            brakeTile.setCenterRatio(0.5, 0.5);
            brakeIconBmp = new Bitmap(brakeTile, this);
            brakeIconBmp.smooth = true;
        } catch (e:haxe.Exception) {
            trace("[TouchControlsHUD] Failed to load icons/brake.png: " + e.message);
        }

        try {
            var handbrakeTile = hxd.Res.load("icons/hand-brake.png").toTile();
            handbrakeTile.setCenterRatio(0.5, 0.5);
            driftIconBmp = new Bitmap(handbrakeTile, this);
            driftIconBmp.smooth = true;
        } catch (e:haxe.Exception) {
            trace("[TouchControlsHUD] Failed to load icons/hand-brake.png: " + e.message);
        }

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
        var dPause = distSq(px, py, pauseX, pauseY);
        var hitPauseRadiusSq = (pauseRadius + 18.0) * (pauseRadius + 18.0);
        if (dPause <= hitPauseRadiusSq) {
            activeRoles.set(tid, "pause");
            recomputeStates();
            return;
        }

        // 2. Nitro Boost (Left hand, below minimap)
        var dNitro = distSq(px, py, nitroX, nitroY);
        var hitNitroRadiusSq = (nitroRadius + 24.0) * (nitroRadius + 24.0);
        if (dNitro <= hitNitroRadiusSq) {
            activeRoles.set(tid, "nitro");
            recomputeStates();
            return;
        }

        // 3. Brake / Reverse (Right hand, upper-right quadrant)
        var dBrake = distSq(px, py, brakeX, brakeY);
        var hitBrakeRadiusSq = (brakeRadius + 24.0) * (brakeRadius + 24.0);
        if (dBrake <= hitBrakeRadiusSq) {
            activeRoles.set(tid, "brake");
            recomputeStates();
            return;
        }

        // 4. Drift / Handbrake (Right hand, mid-right edge)
        var dDrift = distSq(px, py, driftX, driftY);
        var hitDriftRadiusSq = (driftRadius + 24.0) * (driftRadius + 24.0);
        if (dDrift <= hitDriftRadiusSq) {
            activeRoles.set(tid, "drift");
            recomputeStates();
            return;
        }

        // 5. Gas / Throttle (Right hand, lower-right corner)
        var dGas = distSq(px, py, gasX, gasY);
        var hitGasRadiusSq = (gasRadius + 28.0) * (gasRadius + 28.0);
        if (dGas <= hitGasRadiusSq) {
            activeRoles.set(tid, "gas");
            recomputeStates();
            return;
        }

        // 6. Virtual Analog Steering Joystick (Left thumb, lower-left zone)
        var dStick = distSq(px, py, stickBaseX, stickBaseY);
        var hitStickRadiusSq = (stickBaseRadius + 45.0) * (stickBaseRadius + 45.0);
        var isLeftLowerQuadrant = (px < sw * 0.38 && py > sh * 0.48);

        if (dStick <= hitStickRadiusSq || isLeftLowerQuadrant) {
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
            } else if (currentRole == "nitro") {
                if (distSq(px, py, nitroX, nitroY) > (nitroRadius + 50.0) * (nitroRadius + 50.0)) {
                    activeRoles.remove(tid);
                    recomputeStates();
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

        renderHUD();
    }

    /**
     * Dispatches window pointer events for desktop / simulator debugging.
     */
    function onWindowEvent(e:hxd.Event) {
        var isTouchKind = switch (e.kind) {
            case EPush, ERelease, EMove, EReleaseOutside:
                (e.touchId != null && e.touchId >= 0);
            default:
                false;
        };

        if (isTouchKind && !inputRef.isTouchActive) {
            inputRef.isTouchActive = true;
            visible = true;
            var s2d = getScene();
            if (s2d != null) layout(s2d.width, s2d.height);
        }

        #if js
        // If native DOM touch is actively managing this touch ID, let native handler lead
        if (isTouchKind && nativeTouchesActive.exists(e.touchId)) return;
        #end

        if (!visible) {
            if (inputRef.isTouchActive && parent != null && parent.visible) {
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
     * Explicit disposal method removing all window event bindings, bitmaps, and graphics memory.
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
        if (nitroIconBmp != null) { nitroIconBmp.remove(); nitroIconBmp = null; }
        if (gasIconBmp != null) { gasIconBmp.remove(); gasIconBmp = null; }
        if (brakeIconBmp != null) { brakeIconBmp.remove(); brakeIconBmp = null; }
        if (driftIconBmp != null) { driftIconBmp.remove(); driftIconBmp = null; }
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
     * Renders virtual touch control button plates, analog joystick, and border highlights.
     */
    public function renderHUD() {
        canvas.clear();
        if (!visible) {
            if (nitroIconBmp != null) nitroIconBmp.visible = false;
            if (gasIconBmp != null) gasIconBmp.visible = false;
            if (brakeIconBmp != null) brakeIconBmp.visible = false;
            if (driftIconBmp != null) driftIconBmp.visible = false;
            return;
        }

        if (nitroIconBmp != null) nitroIconBmp.visible = true;
        if (gasIconBmp != null) gasIconBmp.visible = true;
        if (brakeIconBmp != null) brakeIconBmp.visible = true;
        if (driftIconBmp != null) driftIconBmp.visible = true;

        // 1. Virtual Analog Steering Joystick (Left Hand)
        drawAnalogStick();

        // 2. Nitro Boost Button (Left Hand, situated below minimap)
        drawFrostedButton(nitroX, nitroY, nitroRadius, isBoostPressed);
        updateIconAppearance(nitroIconBmp, isBoostPressed, 0.0, 0.85, 1.0);

        // 3. Gas / Throttle Pad (Right Hand, lower-right)
        drawFrostedButton(gasX, gasY, gasRadius, isGasPressed);
        updateIconAppearance(gasIconBmp, isGasPressed, 0.20, 0.90, 0.35);

        // 4. Brake / Reverse Pad (Right Hand, upper-right quadrant)
        drawFrostedButton(brakeX, brakeY, brakeRadius, isBrakePressed);
        updateIconAppearance(brakeIconBmp, isBrakePressed, 0.95, 0.20, 0.20);

        // 5. Drift / Handbrake Pad (Right Hand, mid-right edge)
        drawFrostedButton(driftX, driftY, driftRadius, isHandbrakePressed);
        updateIconAppearance(driftIconBmp, isHandbrakePressed, 0.95, 0.65, 0.10);

        // 6. Circular Pause Button (Top-Right)
        drawPauseButton();
    }

    /**
     * Draws the virtual analog steering joystick base, center ticks, and movable thumb knob.
     */
    function drawAnalogStick() {
        var isGrabbed = (stickPointerId != null);
        var baseAlpha = isGrabbed ? 0.48 : 0.32;
        var borderAlpha = isGrabbed ? 0.85 : 0.45;

        // Base circular zone
        canvas.beginFill(0x0A0F16, baseAlpha);
        canvas.lineStyle(2.0, 0xFFFFFF, borderAlpha);
        canvas.drawCircle(stickBaseX, stickBaseY, stickBaseRadius);
        canvas.endFill();

        // Outer subtle tick ring
        canvas.lineStyle(1.0, 0xFFFFFF, borderAlpha * 0.35);
        canvas.drawCircle(stickBaseX, stickBaseY, stickBaseRadius - 5.0);

        // Movable thumb knob puck
        var knobAlpha = isGrabbed ? 0.80 : 0.52;
        var knobBorderAlpha = isGrabbed ? 0.98 : 0.60;
        canvas.beginFill(0x18202C, knobAlpha);
        canvas.lineStyle(2.0, 0xFFFFFF, knobBorderAlpha);
        canvas.drawCircle(stickKnobX, stickKnobY, stickKnobRadius);
        canvas.endFill();

        // Inner knob accent ring
        canvas.lineStyle(1.0, 0xFFFFFF, isGrabbed ? 0.40 : 0.18);
        canvas.drawCircle(stickKnobX, stickKnobY, stickKnobRadius - 3.5);
    }

    /**
     * Draws an individual circular action button with frosted glass fill and glowing perimeter.
     */
    inline function drawFrostedButton(cx:Float, cy:Float, radius:Float, isPressed:Bool) {
        var fillAlpha = isPressed ? 0.70 : 0.40;
        var borderAlpha = isPressed ? 0.95 : 0.45;

        // Frosted dark glass circular plate
        canvas.beginFill(0x0A0F16, fillAlpha);
        canvas.lineStyle(2.0, 0xFFFFFF, borderAlpha);
        canvas.drawCircle(cx, cy, radius);
        canvas.endFill();

        // Inner specular ring highlight
        canvas.lineStyle(1.0, 0xFFFFFF, isPressed ? 0.35 : 0.12);
        canvas.drawCircle(cx, cy, radius - 3.5);
    }

    /**
     * Updates icon bitmap tint, alpha, and glow based on momentary press state.
     */
    inline function updateIconAppearance(bmp:Bitmap, isPressed:Bool, r:Float, g:Float, b:Float) {
        if (bmp == null) return;
        bmp.alpha = isPressed ? 0.95 : 0.60;
        bmp.colorAdd = isPressed ? new h3d.Vector(r, g, b) : new h3d.Vector(0.18, 0.18, 0.20);
    }

    /**
     * Draws the circular top-right pause button matching reference aesthetic.
     */
    inline function drawPauseButton() {
        var fillAlpha = isPausePressed ? 0.70 : 0.40;
        var borderAlpha = isPausePressed ? 0.95 : 0.45;

        canvas.beginFill(0x0A0F16, fillAlpha);
        canvas.lineStyle(1.8, 0xFFFFFF, borderAlpha);
        canvas.drawCircle(pauseX, pauseY, pauseRadius);
        canvas.endFill();

        // Two vertical pause bars centered in button
        canvas.beginFill(0xFFFFFF, isPausePressed ? 0.95 : 0.65);
        canvas.drawRect(pauseX - 5.0, pauseY - 7.0, 3.5, 14.0);
        canvas.drawRect(pauseX + 1.5, pauseY - 7.0, 3.5, 14.0);
        canvas.endFill();
    }

    /**
     * Positions virtual touch buttons and icons relative to viewport boundaries.
     * Preserves exact ergonomically separated positions across all display aspect ratios.
     *
     * @param sw Screen width in pixels.
     * @param sh Screen height in pixels.
     */
    public function layout(sw:Float, sh:Float) {
        // 1. Left Hand: Virtual Analog Steering Joystick (Lower-Left Corner)
        stickBaseRadius = 64.0;
        stickKnobRadius = 34.0;
        stickMaxTravel = 48.0;

        stickBaseX = Math.max(85.0, Math.min(130.0, sw * 0.088));
        stickBaseY = sh - Math.max(90.0, Math.min(130.0, sh * 0.165));

        if (stickPointerId == null) {
            stickKnobX = stickBaseX;
            stickKnobY = stickBaseY;
        }

        // 2. Left Hand: Nitro Boost Button (burn.png, situated below minimap on left edge)
        nitroRadius = 46.0;
        nitroX = Math.max(74.0, Math.min(110.0, sw * 0.076));
        nitroY = Math.max(190.0, Math.min(240.0, sh * 0.31));

        if (nitroIconBmp != null) {
            nitroIconBmp.setScale(56.0 / 512.0);
            nitroIconBmp.x = nitroX;
            nitroIconBmp.y = nitroY;
        }

        // 3. Right Hand: Gas Pedal (gas-pedal.png, lower-right thumb rest zone)
        gasRadius = 48.0;
        gasX = sw - Math.max(120.0, Math.min(160.0, sw * 0.125));
        gasY = sh - Math.max(85.0, Math.min(125.0, sh * 0.165));

        if (gasIconBmp != null) {
            gasIconBmp.setScale(58.0 / 512.0);
            gasIconBmp.x = gasX;
            gasIconBmp.y = gasY;
        }

        // 4. Right Hand: Handbrake Lever (hand-brake.png, mid-right edge)
        driftRadius = 46.0;
        driftX = sw - Math.max(68.0, Math.min(95.0, sw * 0.075));
        driftY = Math.max(210.0, Math.min(270.0, sh * 0.35));

        if (driftIconBmp != null) {
            driftIconBmp.setScale(56.0 / 512.0);
            driftIconBmp.x = driftX;
            driftIconBmp.y = driftY;
        }

        // 5. Right Hand: Brake Disc (brake.png, upper-right quadrant)
        brakeRadius = 46.0;
        brakeX = sw - Math.max(180.0, Math.min(240.0, sw * 0.185));
        brakeY = Math.max(68.0, Math.min(115.0, sh * 0.15));

        if (brakeIconBmp != null) {
            brakeIconBmp.setScale(56.0 / 512.0);
            brakeIconBmp.x = brakeX;
            brakeIconBmp.y = brakeY;
        }

        // 6. Top-Right: Dedicated Circular Pause Button
        pauseRadius = 22.0;
        pauseW = 44.0;
        pauseH = 44.0;
        pauseX = sw - Math.max(38.0, Math.min(50.0, sw * 0.038));
        pauseY = Math.max(34.0, Math.min(50.0, sh * 0.065));

        renderHUD();
    }
}
