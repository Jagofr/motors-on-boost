package ui.views.hud;

import h2d.Object;
import h2d.Graphics;
import h2d.Text;
import h3d.Vector;
import ui.FontManager;
import ui.components.UITheme;
import physics.CarPhysics;

/**
 * High-speed in-game cyber HUD overlay reflecting modern arcade aesthetic.
 * Features:
 * - Top-Left: Angled high-contrast digital speedometer badge, gear indicator, lap & elapsed timer, and wireframe track minimap with real-time vehicle positioning.
 * - Top-Center: Symmetrical curved tachometer RPM arc gauge with dynamic radial tick markers, cyber cyan-to-redline gradient fill, and numerical RPM readout.
 * - Bottom-Center: Curved electric arc Nitrous Boost gauge with flame iconography, proportional fuel capacity meter, and live percentage display.
 * - Top-Right: Discreet performance frame rate (FPS) counter.
 * Fully optimized for zero per-frame garbage collector allocations.
 */
class InGameHUDView extends Object {
    /** Primary vector graphics canvas for drawing gauges, badges, minimap, and meter arcs. */
    public var canvas:Graphics;

    // Top-Left Speedometer & Telemetry
    var speedText:Text;
    var unitText:Text;
    var gearText:Text;
    var driftText:Text;

    // Top-Left Lap & Timer Badge
    var lapText:Text;
    var timeText:Text;

    // Top-Center Tachometer Gauge
    var rpmText:Text;

    // Bottom-Center Nitrous Boost Gauge
    var boostText:Text;

    // Top-Right Frame Rate Counter
    var fpsText:Text;

    // Cached layout coordinates
    var screenW:Float = 1280.0;
    var screenH:Float = 720.0;

    // Minimap track bounding box and normalized waypoints
    var minimapX:Float = 24.0;
    var minimapY:Float = 148.0;
    var minimapW:Float = 160.0;
    var minimapH:Float = 140.0;
    var mapMinX:Float = -30.0;
    var mapMaxX:Float = 310.0;
    var mapMinY:Float = -80.0;
    var mapMaxY:Float = 280.0;
    var minimapPoints:Array<{x:Float, y:Float}> = [];

    // Cached values to avoid unnecessary string construction per frame
    var lastKmh:Int = -999;
    var lastGear:Int = -999;
    var lastRpm:Int = -999;
    var lastBoostPct:Int = -999;
    var lastLap:Int = -999;
    var lastTotalLaps:Int = -999;
    var lastTimeSeconds:Int = -999;
    var lastDriftState:Bool = false;
    var lastFps:Int = -999;

    /**
     * Instantiates the in-game HUD view and constructs all graphical and typographical components.
     *
     * @param parent Optional parent 2D scene object.
     */
    public function new(?parent:Object) {
        super(parent);

        canvas = new Graphics(this);

        // 1. Top-Left: Digital Speed readout
        speedText = new Text(FontManager.heroFont, this);
        speedText.textColor = 0xFFFFFF;

        unitText = new Text(FontManager.regularFont, this);
        unitText.text = "KM/H";
        unitText.textColor = UITheme.COLOR_ACCENT_CYAN;

        gearText = new Text(FontManager.titleFont, this);
        gearText.textColor = UITheme.COLOR_ACCENT_GOLD;

        driftText = new Text(FontManager.regularFont, this);
        driftText.text = "DRIFT";
        driftText.textColor = UITheme.COLOR_ORANGE_WARNING;
        driftText.visible = false;

        // 2. Lap & Elapsed Timer
        lapText = new Text(FontManager.regularFont, this);
        lapText.textColor = UITheme.COLOR_TEXT_NORMAL;

        timeText = new Text(FontManager.regularFont, this);
        timeText.textColor = UITheme.COLOR_ACCENT_CYAN;

        // 3. Top-Center: Engine RPM Text
        rpmText = new Text(FontManager.regularFont, this);
        rpmText.textColor = UITheme.COLOR_ACCENT_CYAN;

        // 4. Bottom-Center: Nitrous Boost Text
        boostText = new Text(FontManager.regularFont, this);
        boostText.textColor = UITheme.COLOR_ACCENT_CYAN;

        // 5. Top-Right: FPS Display
        fpsText = new Text(FontManager.regularFont, this);
        fpsText.textColor = UITheme.COLOR_ACCENT_GOLD;
    }

    /**
     * Initializes track waypoints for the circuit wireframe minimap.
     *
     * @param waypoints Dense spline coordinates along track centerline.
     */
    public function initWaypoints(waypoints:Array<Vector>) {
        minimapPoints = [];
        if (waypoints == null || waypoints.length == 0) return;

        // Calculate world coordinate bounding box
        var minX:Float = 999999.0;
        var maxX:Float = -999999.0;
        var minY:Float = 999999.0;
        var maxY:Float = -999999.0;

        for (w in waypoints) {
            if (w.x < minX) minX = w.x;
            if (w.x > maxX) maxX = w.x;
            if (w.y < minY) minY = w.y;
            if (w.y > maxY) maxY = w.y;
        }

        // Add padding margin to bounding box
        var padX = (maxX - minX) * 0.08;
        var padY = (maxY - minY) * 0.08;
        mapMinX = minX - padX;
        mapMaxX = maxX + padX;
        mapMinY = minY - padY;
        mapMaxY = maxY + padY;

        var rangeX = mapMaxX - mapMinX;
        var rangeY = mapMaxY - mapMinY;
        if (rangeX <= 0) rangeX = 1.0;
        if (rangeY <= 0) rangeY = 1.0;

        // Pre-normalize waypoint coordinates to [0, 1]
        for (w in waypoints) {
            minimapPoints.push({
                x: (w.x - mapMinX) / rangeX,
                y: (w.y - mapMinY) / rangeY
            });
        }
    }

    /**
     * Evaluates live telemetry values, formats typography displays, and redraws vector gauge overlays.
     *
     * @param dt Delta time in seconds.
     * @param car Current player vehicle physics simulation instance.
     * @param kmh Current ground speed in kilometers per hour.
     * @param isBoosting True if nitrous injection is actively burning.
     * @param lapTimer Cumulative elapsed race time in seconds.
     * @param currentLap Active circuit lap counter (1-indexed).
     * @param totalLaps Total circuit laps in race event.
     */
    public function updateTelemetry(dt:Float, car:CarPhysics, kmh:Int, isBoosting:Bool, lapTimer:Float, currentLap:Int, totalLaps:Int) {
        if (!visible || car == null) return;

        // 1. Speedometer Digits & Units
        if (kmh != lastKmh) {
            lastKmh = kmh;
            speedText.text = Std.string(kmh);
        }

        // 2. Active Gear Indicator
        if (car.currentGear != lastGear) {
            lastGear = car.currentGear;
            gearText.text = (lastGear == -1) ? "R" : ((lastGear == 0) ? "N" : "G" + lastGear);
        }

        // 3. Drifting Alert Badge
        if (car.isDrifting != lastDriftState) {
            lastDriftState = car.isDrifting;
            driftText.visible = lastDriftState;
        }

        // 4. Lap & Time Formatting
        var curSeconds = Math.floor(lapTimer);
        if (curSeconds != lastTimeSeconds || currentLap != lastLap || totalLaps != lastTotalLaps) {
            lastTimeSeconds = curSeconds;
            lastLap = currentLap;
            lastTotalLaps = totalLaps;

            lapText.text = "LAP " + currentLap + "/" + totalLaps;

            var m = Math.floor(curSeconds / 60);
            var s = curSeconds % 60;
            var cs = Math.floor((lapTimer - curSeconds) * 100);
            var mStr = (m < 10) ? ("0" + m) : Std.string(m);
            var sStr = (s < 10) ? ("0" + s) : Std.string(s);
            var csStr = (cs < 10) ? ("0" + cs) : Std.string(cs);
            timeText.text = mStr + ":" + sStr + "." + csStr;
        }

        // 5. Tachometer Engine RPM
        var rpm = Math.round(car.engineRPM);
        if (rpm != lastRpm) {
            lastRpm = rpm;
            rpmText.text = rpm + " RPM";
        }

        // 6. Nitrous Boost Fuel Percentage
        var boostPct = Math.round(car.boostFuel * 100.0);
        if (boostPct != lastBoostPct) {
            lastBoostPct = boostPct;
            boostText.text = boostPct + "% NITRO";
        }
        boostText.textColor = isBoosting ? UITheme.COLOR_ORANGE_WARNING : UITheme.COLOR_ACCENT_CYAN;

        // 7. Framerate Counter
        var fps = Math.round(hxd.Timer.fps());
        if (fps != lastFps) {
            lastFps = fps;
            fpsText.text = "FPS: " + fps;
        }

        // 8. Redraw Vector Gauge Graphics
        renderGauges(car, isBoosting);
    }

    /**
     * Renders vector backplates, gauges, and circuit minimap onto the graphics context.
     */
    function renderGauges(car:CarPhysics, isBoosting:Bool) {
        canvas.clear();

        var badgeX = 24.0;
        var badgeY = 20.0;
        var badgeW = 210.0;
        var badgeH = 74.0;
        var skew = 14.0;

        // =====================================================================
        // TOP-LEFT: ANGLED DIGITAL SPEEDOMETER BADGE
        // =====================================================================
        canvas.beginFill(0x060E18, 0.78);
        canvas.lineStyle(2.0, UITheme.COLOR_ACCENT_CYAN, 0.85);
        canvas.moveTo(badgeX + skew, badgeY);
        canvas.lineTo(badgeX + badgeW, badgeY);
        canvas.lineTo(badgeX + badgeW - skew, badgeY + badgeH);
        canvas.lineTo(badgeX, badgeY + badgeH);
        canvas.lineTo(badgeX + skew, badgeY);
        canvas.endFill();

        // Accent divider bar inside badge
        canvas.lineStyle(1.5, UITheme.COLOR_ACCENT_CYAN, 0.35);
        canvas.moveTo(badgeX + 130.0, badgeY + 10.0);
        canvas.lineTo(badgeX + 130.0 - (skew * 0.7), badgeY + badgeH - 10.0);

        speedText.x = badgeX + 24.0;
        speedText.y = badgeY + 12.0;

        unitText.x = badgeX + 140.0;
        unitText.y = badgeY + 16.0;

        gearText.x = badgeX + 140.0;
        gearText.y = badgeY + 36.0;

        driftText.x = badgeX + badgeW + 8.0;
        driftText.y = badgeY + 28.0;

        // =====================================================================
        // TOP-LEFT: LAP & ELAPSED TIME CARD
        // =====================================================================
        var lapY = badgeY + badgeH + 8.0;
        var lapW = badgeW - 10.0;
        var lapH = 36.0;

        canvas.beginFill(0x060E18, 0.70);
        canvas.lineStyle(1.5, 0x1E3A56, 0.75);
        canvas.drawRoundedRect(badgeX, lapY, lapW, lapH, 6.0);
        canvas.endFill();

        lapText.x = badgeX + 14.0;
        lapText.y = lapY + 9.0;

        timeText.x = badgeX + lapW - timeText.textWidth - 14.0;
        timeText.y = lapY + 9.0;

        // =====================================================================
        // TOP-LEFT: CIRCUIT WIREFRAME MINIMAP
        // =====================================================================
        minimapX = badgeX;
        minimapY = lapY + lapH + 10.0;
        minimapW = badgeW - 10.0;
        minimapH = 130.0;

        // Minimap container backplate
        canvas.beginFill(0x040910, 0.65);
        canvas.lineStyle(1.5, 0x182D42, 0.80);
        canvas.drawRoundedRect(minimapX, minimapY, minimapW, minimapH, 6.0);
        canvas.endFill();

        // Minimap circuit path
        var n = minimapPoints.length;
        if (n > 2) {
            var innerMargin = 16.0;
            var mapDrawW = minimapW - (innerMargin * 2.0);
            var mapDrawH = minimapH - (innerMargin * 2.0);

            canvas.lineStyle(2.0, UITheme.COLOR_ACCENT_CYAN, 0.45);
            var firstPt = minimapPoints[0];
            var p0X = minimapX + innerMargin + (firstPt.x * mapDrawW);
            var p0Y = minimapY + minimapH - innerMargin - (firstPt.y * mapDrawH);
            canvas.moveTo(p0X, p0Y);

            for (i in 1...n) {
                var pt = minimapPoints[i];
                var px = minimapX + innerMargin + (pt.x * mapDrawW);
                var py = minimapY + minimapH - innerMargin - (pt.y * mapDrawH);
                canvas.lineTo(px, py);
            }
            canvas.lineTo(p0X, p0Y); // Close loop

            // Player position dot
            var rangeX = mapMaxX - mapMinX;
            var rangeY = mapMaxY - mapMinY;
            if (rangeX > 0 && rangeY > 0) {
                var normPx = (car.pos.x - mapMinX) / rangeX;
                var normPy = (car.pos.y - mapMinY) / rangeY;
                var dotX = minimapX + innerMargin + (normPx * mapDrawW);
                var dotY = minimapY + minimapH - innerMargin - (normPy * mapDrawH);

                // Halo glow
                canvas.beginFill(UITheme.COLOR_ACCENT_CYAN, 0.35);
                canvas.drawCircle(dotX, dotY, 6.5);
                canvas.endFill();

                // Core beacon
                canvas.beginFill(0xFFFFFF, 1.0);
                canvas.lineStyle(1.5, UITheme.COLOR_ACCENT_CYAN, 1.0);
                canvas.drawCircle(dotX, dotY, 3.5);
                canvas.endFill();

                // Forward heading tick
                var headLen = 9.0;
                var headX = dotX - (Math.sin(car.yaw) * headLen);
                var headY = dotY - (Math.cos(car.yaw) * headLen);
                canvas.lineStyle(2.0, 0xFFE066, 1.0);
                canvas.moveTo(dotX, dotY);
                canvas.lineTo(headX, headY);
            }
        }

        // =====================================================================
        // TOP-CENTER: CURVED TACHOMETER RPM ARC GAUGE
        // =====================================================================
        var rpmCenterCenterX = screenW * 0.5;
        var rpmCenterCenterY = 120.0;
        var rpmRadius = 110.0;
        var rpmStartAngle = 2.45; // ~140 degrees
        var rpmEndAngle = 0.69;   // ~40 degrees
        // Sweep counter-clockwise upwards over top of center
        var rpmTotalSweep = 4.52; // Total arc length in radians

        var idleRpm = car.config.drivetrain.idleRPM;
        var redlineRpm = car.config.drivetrain.redlineRPM;
        var rpmRatio = (car.engineRPM - idleRpm) / (redlineRpm - idleRpm);
        rpmRatio = Math.max(0.0, Math.min(1.0, rpmRatio));

        // Background gauge track
        drawArc(rpmCenterCenterX, rpmCenterCenterY, rpmRadius, rpmStartAngle, rpmTotalSweep, 5.0, 0x112233, 0.55);

        // Active RPM fill arc
        var activeSweep = rpmTotalSweep * rpmRatio;
        var rpmColor = (rpmRatio > 0.86) ? UITheme.COLOR_RED_ALERT : ((rpmRatio > 0.68) ? UITheme.COLOR_ACCENT_GOLD : UITheme.COLOR_ACCENT_CYAN);
        drawArc(rpmCenterCenterX, rpmCenterCenterY, rpmRadius, rpmStartAngle, activeSweep, 6.0, rpmColor, 0.95);

        // Radial gauge tick markers
        var numTicks = 9;
        for (t in 0...numTicks) {
            var frac = t / (numTicks - 1);
            var angle = rpmStartAngle + (frac * rpmTotalSweep);
            var tickColor = (frac > 0.86) ? UITheme.COLOR_RED_ALERT : 0x7E99B4;
            var rInner = rpmRadius - 8.0;
            var rOuter = rpmRadius + 8.0;

            canvas.lineStyle(frac == 0 || frac == 1.0 || frac > 0.85 ? 2.5 : 1.5, tickColor, 0.80);
            canvas.moveTo(rpmCenterCenterX + Math.cos(angle) * rInner, rpmCenterCenterY + Math.sin(angle) * rInner);
            canvas.lineTo(rpmCenterCenterX + Math.cos(angle) * rOuter, rpmCenterCenterY + Math.sin(angle) * rOuter);
        }

        rpmText.x = rpmCenterCenterX - (rpmText.textWidth * 0.5);
        rpmText.y = 48.0;

        // =====================================================================
        // BOTTOM-CENTER: CURVED ELECTRIC NITROUS BOOST ARC GAUGE
        // =====================================================================
        var boostCenterX = screenW * 0.5;
        var boostCenterY = screenH - 42.0;
        var boostRadius = 100.0;
        var boostStartAngle = 3.65; // ~210 degrees
        var boostTotalSweep = 2.10; // Arc spanning over bottom center

        var boostFuelRatio = Math.max(0.0, Math.min(1.0, car.boostFuel));

        // Background boost track
        drawArc(boostCenterX, boostCenterY, boostRadius, boostStartAngle, boostTotalSweep, 5.0, 0x0E2032, 0.60);

        // Active boost fuel fill arc
        var boostActiveSweep = boostTotalSweep * boostFuelRatio;
        var boostColor = isBoosting ? UITheme.COLOR_ORANGE_WARNING : UITheme.COLOR_ACCENT_CYAN;
        drawArc(boostCenterX, boostCenterY, boostRadius, boostStartAngle, boostActiveSweep, 6.0, boostColor, 0.95);

        // Procedural Nitro flame icon in center of boost meter
        drawFlameIcon(boostCenterX, boostCenterY - 24.0, isBoosting);

        boostText.x = boostCenterX - (boostText.textWidth * 0.5);
        boostText.y = boostCenterY - 10.0;
    }

    /**
     * Draws a radial arc ribbon segment using line strips.
     */
    function drawArc(cx:Float, cy:Float, radius:Float, startAngle:Float, sweep:Float, thickness:Float, color:Int, alpha:Float) {
        if (sweep <= 0.001) return;

        var steps:Int = Math.floor(Math.max(4.0, sweep * 16.0));
        canvas.lineStyle(thickness, color, alpha);

        var first = true;
        for (i in 0...steps + 1) {
            var a = startAngle + ((i / steps) * sweep);
            var px = cx + Math.cos(a) * radius;
            var py = cy + Math.sin(a) * radius;
            if (first) {
                canvas.moveTo(px, py);
                first = false;
            } else {
                canvas.lineTo(px, py);
            }
        }
    }

    /**
     * Draws a procedural flame icon with glowing inner core.
     */
    function drawFlameIcon(cx:Float, cy:Float, isBoosting:Bool) {
        var flameColor = isBoosting ? 0xFF8800 : UITheme.COLOR_ACCENT_CYAN;
        var coreColor = isBoosting ? 0xFFFF66 : 0xFFFFFF;

        // Outer flame envelope
        canvas.beginFill(flameColor, isBoosting ? 0.95 : 0.70);
        canvas.moveTo(cx, cy - 14.0);
        canvas.curveTo(cx + 8.0, cy - 4.0, cx + 8.0, cy + 4.0);
        canvas.curveTo(cx + 8.0, cy + 12.0, cx, cy + 12.0);
        canvas.curveTo(cx - 8.0, cy + 12.0, cx - 8.0, cy + 4.0);
        canvas.curveTo(cx - 8.0, cy - 4.0, cx, cy - 14.0);
        canvas.endFill();

        // Inner glowing core
        canvas.beginFill(coreColor, 0.95);
        canvas.moveTo(cx, cy - 4.0);
        canvas.curveTo(cx + 4.0, cy + 2.0, cx + 4.0, cy + 7.0);
        canvas.curveTo(cx + 4.0, cy + 10.0, cx, cy + 10.0);
        canvas.curveTo(cx - 4.0, cy + 10.0, cx - 4.0, cy + 7.0);
        canvas.curveTo(cx - 4.0, cy + 2.0, cx, cy - 4.0);
        canvas.endFill();
    }

    /**
     * Recalculates screen dimensions and repositions stationary elements.
     *
     * @param sw Screen viewport width in pixels.
     * @param sh Screen viewport height in pixels.
     */
    public function layout(sw:Float, sh:Float) {
        screenW = sw;
        screenH = sh;

        if (fpsText != null) {
            fpsText.x = sw - fpsText.textWidth - 24.0;
            fpsText.y = 16.0;
        }
    }

    /**
     * Disposes graphics canvas and decouples listeners.
     */
    public function dispose() {
        if (canvas != null) {
            canvas.clear();
            canvas.remove();
            canvas = null;
        }
        remove();
    }
}
