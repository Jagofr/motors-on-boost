package core;

import h2d.Object;
import h2d.Graphics;
import h2d.Text;

class ControlDiagrams extends Object {
    var g:Graphics;
    var labelsContainer:Object;

    public function new(?parent:Object) {
        super(parent);
        g = new Graphics(this);
        labelsContainer = new Object(this);
    }

    public function drawGamepadLayout() {
        g.clear();
        labelsContainer.removeChildren();

        var cx = 0.0;
        var cy = 0.0;

        // 1. PXN P50L Outer Body Contour
        g.beginFill(0x21252B);
        g.lineStyle(2.5, 0x00E5FF, 0.95);

        g.moveTo(cx - 95, cy - 70);
        g.lineTo(cx + 95, cy - 70);
        g.curveTo(cx + 140, cy - 69, cx + 160, cy - 44);
        g.curveTo(cx + 172, cy - 8, cx + 162, cy + 38);
        g.curveTo(cx + 154, cy + 78, cx + 144, cy + 104);
        g.curveTo(cx + 134, cy + 124, cx + 110, cy + 120);
        g.curveTo(cx + 90, cy + 108, cx + 78, cy + 62);
        g.curveTo(cx + 44, cy + 30, cx, cy + 30);
        g.curveTo(cx - 44, cy + 30, cx - 78, cy + 62);
        g.curveTo(cx - 90, cy + 108, cx - 110, cy + 120);
        g.curveTo(cx - 134, cy + 124, cx - 144, cy + 104);
        g.curveTo(cx - 154, cy + 78, cx - 162, cy + 38);
        g.curveTo(cx - 172, cy - 8, cx - 160, cy - 44);
        g.curveTo(cx - 140, cy - 69, cx - 95, cy - 70);
        g.endFill();

        // 2. Exploded Triggers (LT/RT) & Bumpers (LB/RB)
        g.beginFill(0x2E3440);
        g.lineStyle(2.0, 0x61AFEF, 0.95);
        g.drawRoundedRect(cx - 142, cy - 112, 58, 18, 6);
        g.drawRoundedRect(cx - 138, cy - 89, 54, 14, 5);
        g.drawRoundedRect(cx + 84, cy - 112, 58, 18, 6);
        g.drawRoundedRect(cx + 84, cy - 89, 54, 14, 5);
        g.endFill();

        g.lineStyle(1.2, 0x5C6370, 0.55);
        g.moveTo(cx - 111, cy - 75); g.lineTo(cx - 111, cy - 69);
        g.moveTo(cx + 111, cy - 75); g.lineTo(cx + 111, cy - 69);

        // 3. Thumbsticks
        var lStickX = cx - 88;
        var lStickY = cy - 22;
        g.beginFill(0x181B20);
        g.lineStyle(2.0, 0xFFEE00, 0.95);
        g.drawCircle(lStickX, lStickY, 26);
        g.beginFill(0x282C34);
        g.lineStyle(1.2, 0xFFEE00, 0.85);
        g.drawCircle(lStickX, lStickY, 18);
        g.drawCircle(lStickX, lStickY, 6);
        g.endFill();

        var rStickX = cx + 54;
        var rStickY = cy + 18;
        g.beginFill(0x181B20);
        g.lineStyle(2.0, 0x7E8694, 0.95);
        g.drawCircle(rStickX, rStickY, 26);
        g.beginFill(0x282C34);
        g.lineStyle(1.2, 0x7E8694, 0.85);
        g.drawCircle(rStickX, rStickY, 18);
        g.drawCircle(rStickX, rStickY, 6);
        g.endFill();

        // 4. Directional D-Pad
        var dX = cx - 44;
        var dY = cy + 24;
        g.beginFill(0x181B20);
        g.lineStyle(1.5, 0x3E4451);
        g.drawCircle(dX, dY, 25);
        g.endFill();

        g.beginFill(0x282C34);
        g.lineStyle(1.8, 0x00E5FF, 0.95);
        g.drawRoundedRect(dX - 21, dY - 7, 42, 14, 5);
        g.drawRoundedRect(dX - 7, dY - 21, 14, 42, 5);
        g.endFill();

        // 5. Action Face Buttons (BayX Layout)
        var fX = cx + 96;
        var fY = cy - 22;
        var bRadius = 10.0;
        var dist = 20.0;

        g.beginFill(0x181B20); g.lineStyle(1.8, 0xE5C07B);
        g.drawCircle(fX, fY - dist, bRadius);
        g.lineStyle(1.8, 0x61AFEF);
        g.drawCircle(fX - dist, fY, bRadius);
        g.lineStyle(1.8, 0x98C379);
        g.drawCircle(fX + dist, fY, bRadius);
        g.lineStyle(1.8, 0xE06C75);
        g.drawCircle(fX, fY + dist, bRadius);
        g.endFill();

        var btnLabels = [
            { text: "X", x: fX - 4.5, y: fY - dist - 7, col: 0xE5C07B },
            { text: "Y", x: fX - dist - 4.5, y: fY - 7, col: 0x61AFEF },
            { text: "A", x: fX + dist - 4.5, y: fY - 7, col: 0x98C379 },
            { text: "B", x: fX - 4.5, y: fY + dist - 7, col: 0xE06C75 }
        ];
        for (bl in btnLabels) {
            var txt = new Text(FontManager.regularFont, labelsContainer);
            txt.text = bl.text;
            txt.textColor = bl.col;
            txt.setScale(0.85);
            txt.x = bl.x;
            txt.y = bl.y;
        }

        // 6. Center Console Cluster
        g.beginFill(0x282C34);
        g.lineStyle(1.5, 0xABB2BF, 0.9);
        g.drawRoundedRect(cx - 38, cy - 46, 20, 10, 5);
        g.drawRoundedRect(cx + 18, cy - 46, 20, 10, 5);
        g.drawRoundedRect(cx - 28, cy - 24, 18, 9, 4.5);
        g.drawRoundedRect(cx + 10, cy - 24, 18, 9, 4.5);

        g.beginFill(0x181B20);
        g.lineStyle(2.0, 0xDCDFE4, 0.95);
        g.drawCircle(cx, cy + 8, 14);
        g.beginFill(0x2C313C);
        g.drawCircle(cx, cy + 8, 7);
        g.endFill();

        g.lineStyle(1.5, 0xFFFFFF, 0.9);
        g.moveTo(cx - 32, cy - 41); g.lineTo(cx - 24, cy - 41);
        g.moveTo(cx + 24, cy - 41); g.lineTo(cx + 32, cy - 41);
        g.moveTo(cx + 28, cy - 45); g.lineTo(cx + 28, cy - 37);

        g.beginFill(0x00E5FF);
        g.lineStyle(0);
        for (i in 0...4) {
            g.drawCircle(cx - 12 + (i * 8), cy + 30, 1.8);
        }
        g.endFill();

        // 7. Exploded Callout Guidelines & Labels
        var callouts = [
            { x1: cx - 113, y1: cy - 112, x2: cx - 200, y2: cy - 118, text: "LT: Brake / Reverse" },
            { x1: cx - 111, y1: cy - 89,  x2: cx - 200, y2: cy - 84,  text: "LB: Nitro Boost" },
            { x1: cx + 113, y1: cy - 112, x2: cx + 200, y2: cy - 118, text: "RT: Throttle (Gas)" },
            { x1: cx + 111, y1: cy - 89,  x2: cx + 200, y2: cy - 84,  text: "RB: Handbrake" },
            { x1: lStickX,  y1: lStickY,  x2: cx - 200, y2: cy - 22,  text: "LEFT STICK\n[Steer Left / Right]" },
            { x1: dX,       y1: dY,       x2: cx - 200, y2: cy + 42,  text: "D-PAD: Alternate Steer" },
            { x1: fX + dist, y1: fY,      x2: cx + 200, y2: cy - 22,  text: "A: Menu Confirm\nB: Handbrake / Drift" },
            { x1: rStickX,  y1: rStickY,  x2: cx + 200, y2: cy + 32,  text: "RIGHT STICK: Camera" },
            { x1: cx + 28,  y1: cy - 41,  x2: cx + 200, y2: cy + 86,  text: "[+] / MENU: Pause Game" }
        ];

        g.lineStyle(1.5, 0xE5C07B, 0.85);
        for (c in callouts) {
            g.moveTo(c.x1, c.y1);
            g.lineTo(c.x2, c.y2);

            var t = new Text(FontManager.regularFont, labelsContainer);
            t.text = c.text;
            t.textColor = 0xFFFFFF;
            t.setScale(0.9);
            t.x = c.x2 > cx ? c.x2 + 8 : c.x2 - t.textWidth * 0.9 - 8;
            t.y = c.y2 - 8;
        }
    }

    public function drawKeyboardLayout() {
        g.clear();
        labelsContainer.removeChildren();

        var cx = 0.0;
        var cy = 0.0;

        g.beginFill(0x21252B);
        g.lineStyle(2.5, 0x98C379, 0.85);
        g.drawRoundedRect(cx - 200, cy - 85, 400, 175, 16);
        g.endFill();

        var wasd = [
            { key: "W", x: cx - 110, y: cy - 45, w: 28, h: 28 },
            { key: "A", x: cx - 142, y: cy - 12, w: 28, h: 28 },
            { key: "S", x: cx - 110, y: cy - 12, w: 28, h: 28 },
            { key: "D", x: cx - 78,  y: cy - 12, w: 28, h: 28 }
        ];

        g.beginFill(0x282C34);
        g.lineStyle(1.5, 0x00E5FF, 0.9);
        for (k in wasd) {
            g.drawRoundedRect(k.x, k.y, k.w, k.h, 6);
            var t = new Text(FontManager.regularFont, labelsContainer);
            t.text = k.key;
            t.textColor = 0x00E5FF;
            t.setScale(0.95);
            t.x = k.x + 8;
            t.y = k.y + 6;
        }

        g.drawRoundedRect(cx - 60, cy + 38, 120, 24, 6);
        var spaceTxt = new Text(FontManager.regularFont, labelsContainer);
        spaceTxt.text = "SPACE";
        spaceTxt.textColor = 0xE5C07B;
        spaceTxt.setScale(0.95);
        spaceTxt.x = cx - 24;
        spaceTxt.y = cy + 42;

        g.drawRoundedRect(cx - 180, cy + 22, 50, 24, 6);
        var shiftTxt = new Text(FontManager.regularFont, labelsContainer);
        shiftTxt.text = "SHIFT";
        shiftTxt.textColor = 0xE06C75;
        shiftTxt.setScale(0.95);
        shiftTxt.x = cx - 172;
        shiftTxt.y = cy + 26;

        var arrows = [
            { key: "▲", x: cx + 110, y: cy - 12, w: 26, h: 26 },
            { key: "◄", x: cx + 80,  y: cy + 18, w: 26, h: 26 },
            { key: "▼", x: cx + 110, y: cy + 18, w: 26, h: 26 },
            { key: "►", x: cx + 140, y: cy + 18, w: 26, h: 26 }
        ];

        for (a in arrows) {
            g.drawRoundedRect(a.x, a.y, a.w, a.h, 5);
            var t = new Text(FontManager.regularFont, labelsContainer);
            t.text = a.key;
            t.textColor = 0x98C379;
            t.setScale(0.85);
            t.x = a.x + 7;
            t.y = a.y + 5;
        }

        var callouts = [
            { x1: cx - 110, y1: cy - 45, x2: cx - 110, y2: cy - 80, text: "W / UP: Throttle (Gas)" },
            { x1: cx - 142, y1: cy - 12, x2: cx - 210, y2: cy - 35, text: "A / D: Steering Rack" },
            { x1: cx - 110, y1: cy + 16, x2: cx - 210, y2: cy + 5,  text: "S / DOWN: Brake / Reverse" },
            { x1: cx - 155, y1: cy + 46, x2: cx - 210, y2: cy + 55, text: "L-SHIFT: Nitro Boost" },
            { x1: cx,       y1: cy + 62, x2: cx,       y2: cy + 96,  text: "SPACEBAR: Handbrake" },
            { x1: cx + 110, y1: cy - 12, x2: cx + 180, y2: cy - 50, text: "ARROW KEYS: Alternate Drive" }
        ];

        g.lineStyle(1.5, 0xE5C07B, 0.8);
        for (c in callouts) {
            g.moveTo(c.x1, c.y1);
            g.lineTo(c.x2, c.y2);

            var t = new Text(FontManager.regularFont, labelsContainer);
            t.text = c.text;
            t.textColor = 0xFFFFFF;
            t.setScale(0.9);
            t.x = c.x2 > cx ? c.x2 + 8 : c.x2 - t.textWidth * 0.9 - 8;
            t.y = c.y2 - 8;
        }
    }
}