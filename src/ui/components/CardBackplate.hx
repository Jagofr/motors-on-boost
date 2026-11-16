package ui.components;

import h2d.Graphics;

/**
 * Modal background frame and active item backdrop card renderer.
 * Draws chamfered translucent cyber panels with crisp continuous borders, corner brackets,
 * header accent stripes, and active highlight slots driven by `UITheme`.
 *
 * @class CardBackplate
 * @module ui/components/CardBackplate
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
        var cardH = Math.min(UITheme.MAIN_CARD_HEIGHT, sh * 0.72);
        var cardX = (sw - cardW) * 0.5;
        var cardY = Math.max(76.0, (sh - cardH) * 0.5 + 14.0);

        drawStyledCardBase(g, cardX, cardY, cardW, cardH, UITheme.MAIN_CARD_RADIUS, UITheme.COLOR_ACCENT_CYAN);

        // Row slots
        var rowCount = 6;
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

    /**
     * Draws the peer-to-peer multiplayer Host-or-Join entry modal backdrop,
     * two selectable mode cards, and the Invite Code terminal box on Card 1.
     */
    public static function drawMultiplayerMenu(g:Graphics, sw:Float, sh:Float, selectedIdx:Int, hasCode:Bool) {
        var cardW = Math.min(UITheme.MAP_SELECT_CARD_WIDTH, sw - 32.0);
        var cardH = Math.min(UITheme.MAP_SELECT_CARD_HEIGHT, sh - 110.0);
        var cardX = (sw - cardW) * 0.5;
        var cardY = Math.max(68.0, (sh - cardH) * 0.5 + 8.0);

        drawStyledCardBase(g, cardX, cardY, cardW, cardH, UITheme.MAP_SELECT_CARD_RADIUS, UITheme.COLOR_ACCENT_CYAN);

        g.lineStyle(1.2, UITheme.COLOR_DIVIDER, 0.75);
        g.moveTo(cardX + 24, cardY + 58);
        g.lineTo(cardX + cardW - 24, cardY + 58);
        g.lineStyle(0);

        var padX = 28.0;
        var gap = 24.0;
        var modeCardW = (cardW - (padX * 2.0) - gap) * 0.5;
        var modeCardH = cardH - 134.0;
        var modeCardY = cardY + 74.0;

        for (i in 0...2) {
            var mx = cardX + padX + i * (modeCardW + gap);
            var isSel = (i == selectedIdx);
            var accent = isSel ? UITheme.COLOR_ACCENT_CYAN : UITheme.COLOR_DIVIDER;

            drawChamferedBox(
                g, mx, modeCardY, modeCardW, modeCardH, 10.0,
                isSel ? 0x132235 : 0x101622, isSel ? 0.94 : 0.78,
                accent, isSel ? 0.95 : 0.55,
                isSel ? 2.2 : 1.2
            );

            var prevX = mx + 16.0;
            var prevY = modeCardY + 16.0;
            var prevW = modeCardW - 32.0;
            var prevH = Math.max(84.0, modeCardH * 0.40);

            drawChamferedBox(
                g, prevX, prevY, prevW, prevH, 6.0,
                0x080D14, 0.92,
                isSel ? UITheme.COLOR_ACCENT_CYAN : 0x253549, isSel ? 0.65 : 0.45,
                1.2
            );

            if (i == 0) {
                // Host hub network schematic
                var cx = prevX + prevW * 0.5;
                var cy = prevY + prevH * 0.5;
                var nodeColor = isSel ? UITheme.COLOR_ACCENT_CYAN : 0x5A738E;
                var offsetsX = [-prevW * 0.24, prevW * 0.24, 0.0];
                var offsetsY = [-prevH * 0.24, -prevH * 0.24, prevH * 0.26];
                g.lineStyle(1.8, nodeColor, 0.75);
                for (n in 0...3) {
                    g.moveTo(cx, cy);
                    g.lineTo(cx + offsetsX[n], cy + offsetsY[n]);
                }
                g.lineStyle(0);
                for (n in 0...3) {
                    g.beginFill(nodeColor, 0.9);
                    g.drawCircle(cx + offsetsX[n], cy + offsetsY[n], 5.5);
                    g.endFill();
                }
                g.beginFill(UITheme.COLOR_ACCENT_GOLD, 1.0);
                g.drawCircle(cx, cy, 8.5);
                g.endFill();
            } else {
                // Join by Invite Code interactive input box & Clear pill
                var boxX = prevX + 14.0;
                var boxY = prevY + 34.0;
                var boxW = Math.max(120.0, prevW - 92.0);
                var boxH = 40.0;
                var boxAccent = (isSel || hasCode) ? UITheme.COLOR_ACCENT_GOLD : UITheme.COLOR_DIVIDER;
                drawChamferedBox(
                    g, boxX, boxY, boxW, boxH, 5.0,
                    0x0F1B2B, 0.96,
                    boxAccent, (isSel || hasCode) ? 0.95 : 0.55,
                    (isSel || hasCode) ? 1.8 : 1.1
                );

                var clrX = prevX + prevW - 72.0;
                drawChamferedBox(
                    g, clrX, boxY, 58.0, boxH, 5.0,
                    0x172130, 0.90,
                    hasCode ? UITheme.COLOR_ACCENT_ORANGE : UITheme.COLOR_DIVIDER, hasCode ? 0.85 : 0.45,
                    1.1
                );
            }

            // Action Launch Pill at bottom of card
            var pillW = modeCardW - 36.0;
            var pillH = 38.0;
            var pillX = mx + 18.0;
            var pillY = modeCardY + modeCardH - pillH - 14.0;
            drawChamferedBox(
                g, pillX, pillY, pillW, pillH, 6.0,
                isSel ? UITheme.COLOR_ACCENT_CYAN : 0x1B2638, isSel ? 0.24 : 0.55,
                isSel ? UITheme.COLOR_ACCENT_CYAN : UITheme.COLOR_DIVIDER, isSel ? 0.95 : 0.50,
                1.5
            );
        }
    }

    /**
     * Draws the peer-to-peer multiplayer staging lobby container, invite banner, map selector cards,
     * and driver roster box.
     */
    public static function drawMultiplayerLobby(g:Graphics, sw:Float, sh:Float, isHost:Bool, selectedMapIdx:Int, focusIdx:Int) {
        var cardW = Math.min(UITheme.LOBBY_CARD_WIDTH, sw - 28.0);
        var cardH = Math.min(UITheme.LOBBY_CARD_HEIGHT, sh - 76.0);
        var cardX = (sw - cardW) * 0.5;
        var cardY = Math.max(46.0, (sh - cardH) * 0.5 + 6.0);

        drawStyledCardBase(g, cardX, cardY, cardW, cardH, UITheme.LOBBY_CARD_RADIUS, UITheme.COLOR_ACCENT_CYAN);

        // Header divider
        g.lineStyle(1.2, UITheme.COLOR_DIVIDER, 0.75);
        g.moveTo(cardX + 24, cardY + 54);
        g.lineTo(cardX + cardW - 24, cardY + 54);
        g.lineStyle(0);

        // Room & Invite Link banner box
        drawChamferedBox(g, cardX + 24, cardY + 64, cardW - 48, 56, 8.0, 0x101928, 0.88, UITheme.COLOR_ACCENT_CYAN, 0.55, 1.4);

        var bodyTop = cardY + 132.0;
        var bodyH = cardH - 208.0;
        var leftW = (cardW - 64.0) * 0.52;
        var rightW = (cardW - 64.0) - leftW;
        var rightX = cardX + 24.0 + leftW + 16.0;

        // Left: Two Map Choice Cards stacked cleanly
        var mapBtnH = (bodyH - 12.0) * 0.5;
        for (i in 0...2) {
            var my = bodyTop + i * (mapBtnH + 12.0);
            var isSel = (i == selectedMapIdx);
            var accent = isSel ? UITheme.COLOR_ACCENT_CYAN : UITheme.COLOR_DIVIDER;
            drawChamferedBox(g, cardX + 24.0, my, leftW, mapBtnH, 8.0,
                isSel ? 0x132438 : 0x101622, isSel ? 0.94 : 0.76,
                accent, isSel ? 0.95 : 0.50,
                isSel ? 2.0 : 1.1);
        }

        // Right: Driver Roster Panel
        drawChamferedBox(g, rightX, bodyTop, rightW, bodyH, 8.0, 0x0E1520, 0.88, UITheme.COLOR_DIVIDER, 0.65, 1.2);

        // Bottom Primary Action Button Highlights
        var btnY = cardY + cardH - 58.0;
        var btnH = 38.0;
        if (isHost) {
            // Copy Invite Link + Start Match
            var halfBtnW = Math.min(230.0, (cardW - 200.0) * 0.5);
            drawChamferedBox(g, cardX + 24.0, btnY, halfBtnW, btnH, 6.0,
                focusIdx == 0 ? 0x152B40 : 0x121A26, 0.92,
                UITheme.COLOR_ACCENT_CYAN, focusIdx == 0 ? 1.0 : 0.65, focusIdx == 0 ? 1.8 : 1.1);

            drawChamferedBox(g, cardX + cardW - 24.0 - halfBtnW, btnY, halfBtnW, btnH, 6.0,
                focusIdx == 1 ? 0x2B2510 : 0x1E1B12, 0.95,
                UITheme.COLOR_ACCENT_GOLD, focusIdx == 1 ? 1.0 : 0.75, focusIdx == 1 ? 2.0 : 1.3);
        }
    }
}
