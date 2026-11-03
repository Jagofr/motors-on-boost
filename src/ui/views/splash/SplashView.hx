package ui.views.splash;

import h2d.Object;
import h2d.Text;
import h2d.Graphics;
import h2d.Interactive;
import ui.FontManager;
import ui.components.UITheme;
import ui.components.CardBackplate;

/**
 * Title splash screen with game logo, cyber backing badge, and animated pulsating entrance prompt.
 */
class SplashView extends Object {
    /** Vector graphics backdrop for title and prompt capsules. */
    public var bgGraphics:Graphics;

    /** Title banner display. */
    public var titleText:Text;

    /** Subtitle tagline display. */
    public var subtitleText:Text;

    /** Pulsating entrance prompt text. */
    public var promptText:Text;

    /** Build version badge display. */
    public var versionText:Text;

    /** Fullscreen click/tap interceptor. */
    public var screenHit:Interactive;

    /** Internal blink timer for breathing prompt animation. */
    var blinkTimer:Float = 0.0;

    /** Input debounce cooldown timer in seconds. */
    public var inputCooldown:Float = 0.0;

    /** Entrance cooldown period in seconds. */
    public static inline var DEFAULT_COOLDOWN:Float = 0.35;

    /** Breathing oscillation speed frequency. */
    public static inline var BLINK_SPEED:Float = 3.5;

    /** Callback invoked when the user confirms entrance. */
    public var onEnter:Void->Void;

    /**
     * Instantiates the title splash screen view.
     *
     * @param parent Optional parent 2D scene object.
     */
    public function new(?parent:Object) {
        super(parent);

        bgGraphics = new Graphics(this);

        titleText = new Text(FontManager.heroFont, this);
        titleText.text = "M.O.B. // MOTORS ON BOOST";
        titleText.textColor = UITheme.COLOR_ACCENT_ORANGE;

        subtitleText = new Text(FontManager.regularFont, this);
        subtitleText.text = "HIGH-VELOCITY ARCADE RACING & PHYSICS SIMULATION";
        subtitleText.textColor = UITheme.COLOR_ACCENT_CYAN;

        promptText = new Text(FontManager.titleFont, this);
        promptText.text = "PRESS ANY BUTTON OR CLICK TO ENTER";
        promptText.textColor = 0xFFFFFF;

        versionText = new Text(FontManager.regularFont, this);
        versionText.text = Version.DISPLAY;
        versionText.textColor = UITheme.COLOR_TEXT_MUTED;

        screenHit = new Interactive(3000, 3000, this);
        screenHit.onClick = function(_) {
            if (inputCooldown <= 0.0 && onEnter != null) onEnter();
        };
    }

    /**
     * Resets animation timers and triggers entrance cooldown.
     */
    public function activate() {
        visible = true;
        inputCooldown = DEFAULT_COOLDOWN;
        blinkTimer = 0.0;
    }

    /**
     * Updates prompt pulsing animation and cooldown decay.
     *
     * @param dt Delta time in seconds.
     * @param anyKeyPressed True if any button or key was pressed.
     */
    public function update(dt:Float, anyKeyPressed:Bool) {
        if (inputCooldown > 0.0) inputCooldown -= dt;

        blinkTimer += dt * BLINK_SPEED;
        promptText.alpha = (Math.sin(blinkTimer) * 0.38) + 0.62;

        if (inputCooldown <= 0.0 && anyKeyPressed && onEnter != null) {
            onEnter();
        }
    }

    /**
     * Positions splash title, cyber frame, and prompt text relative to viewport dimensions.
     *
     * @param sw Screen width in pixels.
     * @param sh Screen height in pixels.
     */
    public function layout(sw:Float, sh:Float) {
        if (bgGraphics != null) {
            bgGraphics.clear();
            var bannerW = Math.min(760.0, sw * 0.88);
            var bannerH = 140.0;
            var bx = (sw - bannerW) * 0.5;
            var by = sh * 0.30;

            CardBackplate.drawChamferedBox(
                bgGraphics, bx, by, bannerW, bannerH, 12.0,
                UITheme.COLOR_CARD_BG, 0.82,
                UITheme.COLOR_ACCENT_ORANGE, 0.85, 2.0
            );
            CardBackplate.drawCornerBrackets(bgGraphics, bx - 3, by - 3, bannerW + 6, bannerH + 6, UITheme.COLOR_ACCENT_ORANGE, 14.0);

            // Prompt capsule
            var promptW = Math.min(640.0, sw * 0.82);
            var promptH = 54.0;
            var px = (sw - promptW) * 0.5;
            var py = sh * 0.54;
            CardBackplate.drawChamferedBox(
                bgGraphics, px, py, promptW, promptH, 10.0,
                0x0B131E, 0.85,
                UITheme.COLOR_ACCENT_CYAN, 0.75, 1.5
            );
        }

        if (titleText != null) {
            titleText.x = (sw - titleText.textWidth) * 0.5;
            titleText.y = sh * 0.33;
        }
        if (subtitleText != null) {
            subtitleText.x = (sw - subtitleText.textWidth) * 0.5;
            subtitleText.y = sh * 0.415;
        }
        if (promptText != null) {
            promptText.x = (sw - promptText.textWidth) * 0.5;
            promptText.y = sh * 0.54 + 10.0;
        }
        if (versionText != null) {
            versionText.x = (sw - versionText.textWidth) * 0.5;
            versionText.y = sh * 0.66;
        }
        if (screenHit != null) {
            screenHit.width = sw;
            screenHit.height = sh;
        }
    }
}
