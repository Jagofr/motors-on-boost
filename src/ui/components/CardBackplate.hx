package ui.components;

import h2d.Graphics;

/**
 * Modal background frame and active item backdrop card renderer.
 * Draws chamfered translucent cyber panels with crisp continuous borders, corner brackets,
 * header accent stripes, and active highlight slots driven by `UITheme`.
 */
class CardBackplate {
    /**
     * Draws a chamfered polygon path (fill and/or stroke) with continuous straight edges
     * to avoid Heaps 2.1.0 `drawRoundedRect` stroke discontinuities.
     */
    public static function drawChamferedBox(g:Graphics, x:Float, y:Float, w:Float, h:Float, cut:Float, fillColor:Int, fillAlpha:Float, borderColor:Int, borderAlpha:Float, lineWidth:Float = 1.5) {
        var c = Math.min(cut, Math.min(w * 0.25, h * 0.25));
        if (fillAlpha > 0.0) {
            g.beginFill(fillColor, fillAlpha);
            g.lineStyle(0);
            g.moveTo(x + c, y);
            g.lineTo(x + w - c, y);
            g.lineTo(x + w, y + c);
            g.lineTo(x + w, y + h - c);
            g.lineTo(x + w - c, y + h);
            g.lineTo(x + c, y + h);
            g.lineTo(x, y + h - c);
            g.lineTo(x, y + c);
            g.lineTo(x + c, y);
            g.endFill();
        }
        if (lineWidth > 0.0 && borderAlpha > 0.0) {
            g.lineStyle(lineWidth, borderColor, borderAlpha);
            g.moveTo(x + c, y);
            g.lineTo(x + w - c, y);
            g.lineTo(x + w, y + c);
            g.lineTo(x + w, y + h - c);
            g.lineTo(x + w - c, y + h);
            g.lineTo(x + c, y + h);
            g.lineTo(x, y + h - c);
            g.lineTo(x, y + c);
            g.lineTo(x + c, y);
            g.lineStyle(0);
        }
    }

    /**
     * Draws decorative cyber corner brackets on a rectangular modal frame.
     */
    public static function drawCornerBrackets(g:Graphics, x:Float, y:Float, w:Float, h:Float, color:Int, len:Float = 18.0) {
        g.lineStyle(2.5, color, 0.95);
        // Top-Left
        g.moveTo(x, y + len);
        g.lineTo(x, y);
        g.lineTo(x + len, y);
        // Top-Right
        g.moveTo(x + w - len, y);
        g.lineTo(x + w, y);
        g.lineTo(x + w, y + len);
        // Bottom-Left
        g.moveTo(x, y + h - len);
        g.lineTo(x, y + h);
        g.lineTo(x + len, y + h);
        // Bottom-Right
        g.moveTo(x + w - len, y + h);
        g.lineTo(x + w, y + h);
        g.lineTo(x + w, y + h - len);
        g.lineStyle(0);
    }

    /**
     * Draws a styled modal base frame with inner border, top accent bar, and corner brackets.
     */
    static function drawStyledCardBase(g:Graphics, cardX:Float, cardY:Float, cardW:Float, cardH:Float, radius:Float, accentColor:Int) {
        var cut = Math.min(10.0, radius);
        // Outer drop shadow glow
        drawChamferedBox(g, cardX + 5, cardY + 7, cardW, cardH, cut, 0x000000, 0.50, 0x000000, 0.0, 0.0);

        // Main card fill & continuous outer border
        drawChamferedBox(g, cardX, cardY, cardW, cardH, cut, UITheme.COLOR_CARD_BG, UITheme.ALPHA_CARD_SURFACE, accentColor, UITheme.ALPHA_CARD_BORDER, 2.0);

        // Subtle inner inset border
        drawChamferedBox(g, cardX + 6, cardY + 6, cardW - 12, cardH - 12, Math.max(4.0, cut - 3.0), 0x000000, 0.0, UITheme.COLOR_DIVIDER, 0.60, 1.0);

        // Top glowing header accent bar
        g.beginFill(accentColor, 0.90);
        g.lineStyle(0);
        g.drawRect(cardX + 44, cardY, cardW - 88, 3);
        g.endFill();

        drawCornerBrackets(g, cardX - 3, cardY - 3, cardW + 6, cardH + 6, accentColor, 16.0);
    }

    /**
     * Draws the main menu backdrop and active row highlight slot.
     *
     * @param g Target graphics context.
     * @param sw Screen width in pixels.
     * @param sh Screen height in pixels.
     * @param selectedIdx Currently focused item index.
     */
    public static function drawMainMenu(g:Graphics, sw:Float, sh:Float, selectedIdx:Int) {
        var cardW = Math.min(UITheme.MAIN_CARD_WIDTH, sw - 32.0);
        var cardH = Math.min(UITheme.MAIN_CARD_HEIGHT, sh * 0.64);
        var cardX = (sw - cardW) * 0.5;
        var cardY = Math.max(76.0, (sh - cardH) * 0.5 + 14.0);

        drawStyledCardBase(g, cardX, cardY, cardW, cardH, UITheme.MAIN_CARD_RADIUS, UITheme.COLOR_ACCENT_CYAN);

        // Row slots
        var rowCount = 5;
        var totalRowsH = rowCount * UITheme.MAIN_ROW_STRIDE;
        var startY = cardY + (cardH - totalRowsH) * 0.5 + 6.0;

        for (i in 0...rowCount) {
            var ry = startY + (i * UITheme.MAIN_ROW_STRIDE);
            if (i == selectedIdx) {
                drawChamferedBox(g, cardX + 24, ry - 6, cardW - 48, 44, 6.0, UITheme.COLOR_ACCENT_CYAN, UITheme.ALPHA_SLOT_FILL, UITheme.COLOR_ACCENT_CYAN, UITheme.ALPHA_SLOT_BORDER, 1.8);

                // Left accent indicator bar
                g.beginFill(UITheme.COLOR_ACCENT_CYAN, 1.0);
                g.lineStyle(0);
                g.drawRect(cardX + 24, ry - 1, 5, 34);
                g.endFill();
            } else {
                drawChamferedBox(g, cardX + 28, ry - 6, cardW - 56, 44, 5.0, 0x161E2C, 0.42, UITheme.COLOR_DIVIDER, 0.40, 1.0);
            }
        }
    }

    /**
     * Draws the singleplayer map selection screen backdrop and interactive map cards.
     *
     * @param g Target graphics context.
     * @param sw Screen width in pixels.
     * @param sh Screen height in pixels.
     * @param selectedIdx Currently focused map card index (0: Highway, 1: Sandbox).
     */
    public static function drawMapSelect(g:Graphics, sw:Float, sh:Float, selectedIdx:Int) {
        var cardW = Math.min(UITheme.MAP_SELECT_CARD_WIDTH, sw - 32.0);
        var cardH = Math.min(UITheme.MAP_SELECT_CARD_HEIGHT, sh - 110.0);
        var cardX = (sw - cardW) * 0.5;
        var cardY = Math.max(68.0, (sh - cardH) * 0.5 + 8.0);

        drawStyledCardBase(g, cardX, cardY, cardW, cardH, UITheme.MAP_SELECT_CARD_RADIUS, UITheme.COLOR_ACCENT_CYAN);

        // Header divider line inside modal
        g.lineStyle(1.2, UITheme.COLOR_DIVIDER, 0.75);
        g.moveTo(cardX + 24, cardY + 58);
        g.lineTo(cardX + cardW - 24, cardY + 58);
        g.lineStyle(0);

        // Two side-by-side Map Cards
        var padX = 28.0;
        var gap = 24.0;
        var mapCardW = (cardW - (padX * 2.0) - gap) * 0.5;
        var mapCardH = cardH - 134.0;
        var mapCardY = cardY + 74.0;

        for (i in 0...2) {
            var mx = cardX + padX + i * (mapCardW + gap);
            var isSel = (i == selectedIdx);
            var accent = isSel ? UITheme.COLOR_ACCENT_CYAN : UITheme.COLOR_DIVIDER;

            drawChamferedBox(
                g, mx, mapCardY, mapCardW, mapCardH, 10.0,
                isSel ? 0x132235 : 0x101622, isSel ? 0.94 : 0.78,
                accent, isSel ? 0.95 : 0.55,
                isSel ? 2.2 : 1.2
            );

            // Preview illustration box inside map card
            var prevX = mx + 16.0;
            var prevY = mapCardY + 16.0;
            var prevW = mapCardW - 32.0;
            var prevH = Math.max(84.0, mapCardH * 0.40);

            drawChamferedBox(
                g, prevX, prevY, prevW, prevH, 6.0,
                0x080D14, 0.92,
                isSel ? UITheme.COLOR_ACCENT_CYAN : 0x253549, isSel ? 0.65 : 0.45,
                1.2
            );

            if (i == 0) {
                // Highway Circuit Procedural Vector Schematic Preview (complete continuous chamfered track loop)
                var cx = prevX + prevW * 0.5;
                var cy = prevY + prevH * 0.5;
                var rx = prevW * 0.34;
                var ry = prevH * 0.30;
                drawChamferedBox(g, cx - rx, cy - ry, rx * 2.0, ry * 2.0, 18.0, 0x000000, 0.0, 0x1E2E42, 0.95, 7.0);
                drawChamferedBox(g, cx - rx, cy - ry, rx * 2.0, ry * 2.0, 18.0, 0x000000, 0.0, isSel ? UITheme.COLOR_ACCENT_CYAN : 0x5A738E, 0.95, 2.0);
                // Start/finish line marker
                g.beginFill(UITheme.COLOR_ACCENT_GOLD, 0.95);
                g.lineStyle(0);
                g.drawCircle(cx - rx, cy, 4.5);
                g.endFill();
            } else {
                // Sandbox Proving Grounds Procedural Grid & Ramp Preview
                var gx0 = prevX + 18.0;
                var gx1 = prevX + prevW - 18.0;
                var gy0 = prevY + 14.0;
                var gy1 = prevY + prevH - 14.0;
                g.lineStyle(1.0, isSel ? 0x1E4959 : 0x1B2836, 0.65);
                for (step in 0...5) {
                    var lx = gx0 + (gx1 - gx0) * (step / 4.0);
                    g.moveTo(lx, gy0); g.lineTo(lx, gy1);
                    var ly = gy0 + (gy1 - gy0) * (step / 4.0);
                    g.moveTo(gx0, ly); g.lineTo(gx1, ly);
                }
                // Mountain contour silhouette
                g.lineStyle(2.2, isSel ? UITheme.COLOR_ACCENT_GOLD : 0x7A8C9E, 0.9);
                g.moveTo(gx0 + 10, gy1 - 6);
                g.lineTo(gx0 + (gx1 - gx0) * 0.35, gy0 + 12);
                g.lineTo(gx0 + (gx1 - gx0) * 0.62, gy1 - 18);
                g.lineTo(gx0 + (gx1 - gx0) * 0.82, gy0 + 22);
                g.lineTo(gx1 - 10, gy1 - 6);
                g.lineStyle(0);
            }

            // Action Launch Pill at bottom of map card
            var pillW = mapCardW - 36.0;
            var pillH = 38.0;
            var pillX = mx + 18.0;
            var pillY = mapCardY + mapCardH - pillH - 14.0;
            drawChamferedBox(
                g, pillX, pillY, pillW, pillH, 6.0,
                isSel ? UITheme.COLOR_ACCENT_CYAN : 0x1B2638, isSel ? 0.24 : 0.55,
                isSel ? UITheme.COLOR_ACCENT_CYAN : UITheme.COLOR_DIVIDER, isSel ? 0.95 : 0.50,
                1.5
            );
        }
    }

    /**
     * Draws the pause menu backdrop and active row highlight slot.
     *
     * @param g Target graphics context.
     * @param sw Screen width in pixels.
     * @param sh Screen height in pixels.
     * @param selectedIdx Currently focused item index.
     */
    public static function drawPauseMenu(g:Graphics, sw:Float, sh:Float, selectedIdx:Int) {
        var cardW = Math.min(UITheme.PAUSE_CARD_WIDTH, sw - 32.0);
        var cardH = Math.min(UITheme.PAUSE_CARD_HEIGHT, sh * 0.60);
        var cardX = (sw - cardW) * 0.5;
        var cardY = Math.max(80.0, (sh - cardH) * 0.5 + 16.0);

        drawStyledCardBase(g, cardX, cardY, cardW, cardH, UITheme.PAUSE_CARD_RADIUS, UITheme.COLOR_ACCENT_GOLD);

        var rowCount = 4;
        var totalRowsH = rowCount * UITheme.PAUSE_ROW_STRIDE;
        var startY = cardY + (cardH - totalRowsH) * 0.5 + 8.0;

        for (i in 0...rowCount) {
            var ry = startY + (i * UITheme.PAUSE_ROW_STRIDE);
            if (i == selectedIdx) {
                drawChamferedBox(g, cardX + 24, ry - 6, cardW - 48, 44, 6.0, UITheme.COLOR_ACCENT_CYAN, UITheme.ALPHA_SLOT_FILL, UITheme.COLOR_ACCENT_CYAN, UITheme.ALPHA_SLOT_BORDER, 1.8);

                g.beginFill(UITheme.COLOR_ACCENT_GOLD, 1.0);
                g.lineStyle(0);
                g.drawRect(cardX + 24, ry - 1, 5, 34);
                g.endFill();
            } else {
                drawChamferedBox(g, cardX + 28, ry - 6, cardW - 56, 44, 5.0, 0x161E2C, 0.42, UITheme.COLOR_DIVIDER, 0.40, 1.0);
            }
        }
    }

    /**
     * Draws the options modal backdrop and active tab button capsule.
     *
     * @param g Target graphics context.
     * @param sw Screen width in pixels.
     * @param sh Screen height in pixels.
     * @param activeTabIdx Currently active tab index.
     * @param tabCount Total number of options tabs.
     */
    public static function drawOptionsMenu(g:Graphics, sw:Float, sh:Float, activeTabIdx:Int, tabCount:Int) {
        var cardW = Math.min(UITheme.OPTIONS_CARD_WIDTH, sw - 24.0);
        var cardH = Math.min(UITheme.OPTIONS_CARD_HEIGHT, sh - (sh * 0.16) - 16.0);
        var cardX = (sw - cardW) * 0.5;
        var cardY = Math.max(12.0, (sh - cardH) * 0.5);

        drawStyledCardBase(g, cardX, cardY, cardW, cardH, UITheme.OPTIONS_CARD_RADIUS, UITheme.COLOR_ACCENT_CYAN);

        // Header divider line below tabs
        g.lineStyle(1.2, UITheme.COLOR_DIVIDER, 0.70);
        g.moveTo(cardX + 20, cardY + 60);
        g.lineTo(cardX + cardW - 20, cardY + 60);
        g.lineStyle(0);

        var tabSpacing = Math.min(UITheme.OPTIONS_TAB_SPACING, (cardW - 140.0) / tabCount);
        var tabStartX = (sw - (tabCount * tabSpacing)) * 0.5;
        var tabX = tabStartX + (activeTabIdx * tabSpacing);
        var tabBtnW = Math.min(150.0, tabSpacing - 8.0);
        drawChamferedBox(g, tabX + 4, cardY + 12.0, tabBtnW, 42, 6.0, UITheme.COLOR_ACCENT_CYAN, UITheme.ALPHA_TAB_FILL, UITheme.COLOR_ACCENT_CYAN, 0.90, 2.0);
    }

    /**
     * Draws the credits screen backdrop and lead architect accent box.
     *
     * @param g Target graphics context.
     * @param sw Screen width in pixels.
     * @param sh Screen height in pixels.
     */
    public static function drawCreditsScreen(g:Graphics, sw:Float, sh:Float) {
        var cardW = Math.min(UITheme.CREDITS_CARD_WIDTH, sw - 24.0);
        var cardH = Math.min(UITheme.CREDITS_CARD_HEIGHT, sh - 60.0);
        var cardX = (sw - cardW) * 0.5;
        var cardY = Math.max(24.0, (sh - cardH) * 0.5);

        drawStyledCardBase(g, cardX, cardY, cardW, cardH, UITheme.CREDITS_CARD_RADIUS, UITheme.COLOR_ACCENT_CYAN);

        // Lead Architect Accent Container
        drawChamferedBox(g, cardX + 36, sh * 0.215, cardW - 72, 78, 8.0, UITheme.COLOR_ACCENT_CYAN, 0.08, UITheme.COLOR_ACCENT_CYAN, 0.50, 1.5);
    }
}
