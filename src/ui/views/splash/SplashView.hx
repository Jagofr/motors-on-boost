package ui.views.splash;

import h2d.Object;
import h2d.Text;
import h2d.Interactive;
import ui.FontManager;
import ui.components.UITheme;

/**
 * Title splash screen with game logo and animated pulsating entrance prompt.
 */
class SplashView extends Object {
    /** Title banner display. */
    public var titleText:Text;

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

        titleText = new Text(FontManager.heroFont, this);
        titleText.text = "M.O.B. // MOTORS ON BOOST";
        titleText.textColor = UITheme.COLOR_ACCENT_ORANGE;

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
        promptText.alpha = (Math.sin(blinkTimer) * 0.4) + 0.6;

        if (inputCooldown <= 0.0 && anyKeyPressed && onEnter != null) {
            onEnter();
        }
    }

    /**
     * Positions splash title and prompt text relative to viewport dimensions.
     *
     * @param sw Screen width in pixels.
     * @param sh Screen height in pixels.
     */
    public function layout(sw:Float, sh:Float) {
        if (titleText != null) {
            titleText.x = (sw - titleText.textWidth) * 0.5;
            titleText.y = sh * 0.36;
        }
        if (promptText != null) {
            promptText.x = (sw - promptText.textWidth) * 0.5;
            promptText.y = sh * 0.52;
        }
        if (versionText != null) {
            versionText.x = (sw - versionText.textWidth) * 0.5;
            versionText.y = sh * 0.62;
        }
        if (screenHit != null) {
            screenHit.width = sw;
            screenHit.height = sh;
        }
    }
}
