package ui.components;

import h2d.Graphics;

/**
 * Modal background frame and active item backdrop card renderer.
 * Draws rounded translucent panels with cyber cyan borders and highlight slots
 * driven by visual design constants in `UITheme`.
 */
class CardBackplate {
    /**
     * Draws the main menu backdrop and active row highlight slot.
     *
     * @param g Target graphics context.
     * @param sw Screen width in pixels.
     * @param sh Screen height in pixels.
     * @param selectedIdx Currently focused item index.
     */
    public static function drawMainMenu(g:Graphics, sw:Float, sh:Float, selectedIdx:Int) {
        var cardW = UITheme.MAIN_CARD_WIDTH;
        var cardH = UITheme.MAIN_CARD_HEIGHT;
        var cardX = (sw - cardW) * 0.5;
        var cardY = sh * 0.25;
        g.drawRoundedRect(cardX, cardY, cardW, cardH, UITheme.MAIN_CARD_RADIUS);

        var activeY = sh * 0.31 + (selectedIdx * UITheme.MAIN_ROW_STRIDE);
        g.beginFill(UITheme.COLOR_ACCENT_CYAN, UITheme.ALPHA_SLOT_FILL);
        g.lineStyle(1.5, UITheme.COLOR_ACCENT_CYAN, UITheme.ALPHA_SLOT_BORDER);
        g.drawRoundedRect(cardX + 24, activeY - 4, cardW - 48, 44, 8);
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
        var cardW = UITheme.PAUSE_CARD_WIDTH;
        var cardH = UITheme.PAUSE_CARD_HEIGHT;
        var cardX = (sw - cardW) * 0.5;
        var cardY = sh * 0.32;
        g.drawRoundedRect(cardX, cardY, cardW, cardH, UITheme.PAUSE_CARD_RADIUS);

        var activeY = sh * 0.38 + (selectedIdx * UITheme.PAUSE_ROW_STRIDE);
        g.beginFill(UITheme.COLOR_ACCENT_CYAN, UITheme.ALPHA_SLOT_FILL);
        g.lineStyle(1.5, UITheme.COLOR_ACCENT_CYAN, UITheme.ALPHA_SLOT_BORDER);
        g.drawRoundedRect(cardX + 24, activeY - 4, cardW - 48, 44, 8);
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
        g.drawRoundedRect(cardX, cardY, cardW, cardH, UITheme.OPTIONS_CARD_RADIUS);

        var tabSpacing = Math.min(UITheme.OPTIONS_TAB_SPACING, (cardW - 140.0) / tabCount);
        var tabStartX = (sw - (tabCount * tabSpacing)) * 0.5;
        var tabX = tabStartX + (activeTabIdx * tabSpacing);
        var tabBtnW = Math.min(150.0, tabSpacing - 8.0);
        g.beginFill(UITheme.COLOR_ACCENT_CYAN, UITheme.ALPHA_TAB_FILL);
        g.lineStyle(2.0, UITheme.COLOR_ACCENT_CYAN, 0.9);
        g.drawRoundedRect(tabX + 4, cardY + 12.0, tabBtnW, 42, 8);
    }

    /**
     * Draws the credits screen backdrop and lead architect accent box.
     *
     * @param g Target graphics context.
     * @param sw Screen width in pixels.
     * @param sh Screen height in pixels.
     */
    public static function drawCreditsScreen(g:Graphics, sw:Float, sh:Float) {
        var cardW = UITheme.CREDITS_CARD_WIDTH;
        var cardH = UITheme.CREDITS_CARD_HEIGHT;
        var cardX = (sw - cardW) * 0.5;
        var cardY = sh * 0.12;
        g.drawRoundedRect(cardX, cardY, cardW, cardH, UITheme.CREDITS_CARD_RADIUS);

        // Lead Architect Accent Container
        g.beginFill(UITheme.COLOR_ACCENT_CYAN, 0.08);
        g.lineStyle(1.5, UITheme.COLOR_ACCENT_CYAN, 0.4);
        g.drawRoundedRect(cardX + 32, sh * 0.22, cardW - 64, 76, 10);
    }
}
