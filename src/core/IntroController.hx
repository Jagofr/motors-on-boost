package core;

import config.GameConfig;
import config.GameConfig.IntroConfig;
import h2d.Bitmap;
import h2d.Graphics;
import h2d.Object;
import h2d.Scene;
import h2d.Text;
import h2d.Tile;
import ui.FontManager;

/**
 * Sequential boot phase progression prior to interactive Splash screen.
 *
 * @enum {Int} IntroState
 * @module core/IntroController
 */
@:keep
enum IntroState {
    /** Intro sequence has not yet entered an active state. */
    None;
    /** Publisher branding splash screen. */
    Studio;
    /** Game engine and technology attribution splash screen. */
    Engine;
    /** Legal and health disclosure notice screen holding until background loading finishes. */
    Disclaimer;
    /** Boot intro finished; main splash screen and 3D showcase active. */
    Complete;
}

/**
 * Controller managing publisher (`Studio`), engine attribution (`Engine`), and legal disclosure
 * (`Disclaimer`) screens while `AssetPreloader` finishes loading game resources in memory
 * in the background without displaying any progress bar.
 *
 * @class IntroController
 * @module core/IntroController
 */
class IntroController {
    /** Active stage of the boot sequence state machine. */
    public var state:IntroState = None;

    /** Elapsed time on the current intro stage in seconds. */
    public var timer:Float = 0.0;

    /** Active opacity factor of the visible intro screen [0..1]. */
    public var alpha:Float = 0.0;

    /** True when user skip accelerated the current slide fade-out. */
    public var isFadingOut:Bool = false;

    /** Timing and branding asset configuration. */
    public var config:IntroConfig;

    /** Background preloader monitored before exiting the disclaimer phase. */
    public var preloader:AssetPreloader;

    /** Parent 2D root scene graph (optional in headless unit tests). */
    public var rootLayer:Null<Scene>;

    /** Top-level container wrapping all intro screens and backdrop. */
    public var introContainer:Object;

    /** Opaque black backdrop behind intro slides. */
    public var introBg:Bitmap;

    /** Container for Publisher screen. */
    public var screenStudio:Object;

    /** Publisher splash bitmap element. */
    public var studioSplashBmp:Bitmap;

    /** Container for Engine attribution screen. */
    public var screenEngine:Object;

    /** Engine attribution background splash bitmap element. */
    public var engineSplashBmp:Bitmap;

    /** Container for Trademark & Legal Disclosures screen (no progress bar). */
    public var screenDisclaimer:Object;

    /** Stylized corner-bracket card frame graphics behind disclaimer copy. */
    public var discGraphics:Graphics;

    /** Legal disclaimer header title text. */
    public var discHeader:Text;

    /** Legal disclaimer body copy text. */
    public var discBody:Text;

    /** Legal disclaimer build/version watermark text. */
    public var discVersion:Text;

    /** Row container centering partner/technology badges inside the disclaimer frame. */
    public var logoRow:Object;

    /** Partner badge bitmap instances [Heaps, Haxe, WebGL]. */
    public var discLogos:Array<Bitmap> = [];

    /** Fullscreen black cross-fade curtain revealing 3D showcase after intro completes. */
    public var showcaseCurtain:Bitmap;

    /** True while post-intro showcase fade-in curtain is fading out. */
    public var isShowcaseFadingIn:Bool = false;

    /** Elapsed post-intro showcase fade timer in seconds. */
    public var showcaseFadeTimer:Float = 0.0;

    /** Invoked once Disclaimer completes AND `preloader.isComplete` is true. */
    public var onIntroComplete:Null<Void -> Void> = null;

    /** Invoked whenever async splash bitmaps/logos finish attaching to display containers. */
    public var onAssetsBound:Null<Void -> Void> = null;

    /** Invoked whenever the active IntroState changes. */
    public var onStateChanged:Null<IntroState -> Void> = null;

    /**
     * Constructs intro display layers on the 2D scene without creating any progress bar UI.
     *
     * @param {Null<Scene>} s2d Root 2D scene graph (null allowed in headless tests).
     * @param {AssetPreloader} preloader Active background asset preloader.
     * @param {Null<IntroConfig>} [config] Optional intro timings and asset URLs.
     */
    public function new(s2d:Null<Scene>, preloader:AssetPreloader, ?config:IntroConfig) {
        this.rootLayer = s2d;
        this.preloader = preloader;
        this.config = config != null ? config : GameConfig.getDefault().intro;
        buildScreens();
    }

    /**
     * Instantiates the Studio, Engine, and Disclaimer display trees and binds async tiles.
     *
     * @returns {Void}
     */
    private function buildScreens():Void {
        introContainer = new Object(rootLayer);
        introBg = new Bitmap(Tile.fromColor(0x000000, 1, 1, 1.0), introContainer);

        // 1. Studio / Publisher Screen
        screenStudio = new Object(introContainer);
        preloader.onTileReady(config.studioSplashPath, function(tile) {
            if (tile != null) {
                studioSplashBmp = new Bitmap(tile, screenStudio);
                layout();
                if (onAssetsBound != null) onAssetsBound();
            }
        });

        // 2. Engine / Technology Attribution Screen
        screenEngine = new Object(introContainer);
        preloader.onTileReady(config.engineSplashPath, function(tile) {
            if (tile != null) {
                engineSplashBmp = new Bitmap(tile, screenEngine);
                layout();
                if (onAssetsBound != null) onAssetsBound();
            }
        });

        // 3. Trademark & Legal Disclosures Screen (holds with zero progress bar)
        screenDisclaimer = new Object(introContainer);
        discGraphics = new Graphics(screenDisclaimer);

        discHeader = new Text(FontManager.titleFont, screenDisclaimer);
        discHeader.text = "TRADEMARK & LEGAL DISCLOSURES";
        discHeader.textColor = 0x00E5FF;
        discHeader.textAlign = Center;

        discBody = new Text(FontManager.regularFont, screenDisclaimer);
        discBody.textColor = 0xC2D1E0;
        discBody.textAlign = Center;
        discBody.lineSpacing = 5.0;
        discBody.text =
            "M.O.B. (Motors on Boost) is an original racing simulation prototype.\n" +
            "Created and developed by Gerard \"Jamie\" (Jagofr) Francis. Published by RvL // ROGUE.\n" +
            "All custom codebases, vehicles, handling physics, tracks, and original visual assets\n" +
            "are the intellectual property of their respective creators. All rights reserved.\n\n" +
            "Haxe and Heaps.io are trademarks or registered trademarks of their respective owners.\n" +
            "WebGL is a trademark of the Khronos Group Inc. Typography licensed under SIL OFL & Apache 2.0.\n" +
            "Any vehicular likenesses or architectural references are used strictly for artistic illustration.\n\n" +
            "HEALTH & SAFETY ADVISORY: Photosensitivity and seizure precautions apply.\n" +
            "Please play in a well-lit environment and take a 15-minute break for every hour of play.";

        discVersion = new Text(FontManager.regularFont, screenDisclaimer);
        discVersion.text = Version.DISPLAY;
        discVersion.textColor = 0x5A738E;
        discVersion.textAlign = Center;

        logoRow = new Object(screenDisclaimer);
        for (logoPath in config.engineLogoPaths) {
            preloader.onTileReady(logoPath, function(tile) {
                if (tile != null) {
                    var bmp = new Bitmap(tile, logoRow);
                    discLogos.push(bmp);
                    layout();
                }
            });
        }

        screenStudio.visible = false;
        screenEngine.visible = false;
        screenDisclaimer.visible = false;
    }

    /**
     * Switches to the requested boot screen stage and resets alpha/timer transitions.
     *
     * @param {IntroState} target Stage enum value to display.
     * @returns {Void}
     */
    public function setScreen(target:IntroState):Void {
        state = target;
        timer = 0.0;
        alpha = 0.0;
        isFadingOut = false;

        screenStudio.visible = (state == Studio);
        screenEngine.visible = (state == Engine);
        screenDisclaimer.visible = (state == Disclaimer);

        screenStudio.alpha = 0.0;
        screenEngine.alpha = 0.0;
        screenDisclaimer.alpha = 0.0;

        layout();
        if (onStateChanged != null) onStateChanged(state);
    }

    /**
     * Steps the active intro timeline or showcase fade-out curtain.
     * Guarantees Disclaimer does not transition to Splash screen until `preloader.isComplete` is true.
     *
     * @param {Float} dt Elapsed frame time in seconds.
     * @returns {Void}
     */
    public function update(dt:Float):Void {
        if (state != Complete) {
            timer += dt;

            if (isFadingOut) {
                alpha -= dt * 2.5;
                if (alpha <= 0.0) {
                    alpha = 0.0;
                    isFadingOut = false;
                    if (state == Studio) setScreen(Engine);
                    else if (state == Engine) setScreen(Disclaimer);
                    return;
                }
                applyActiveAlpha();
                return;
            }

            switch (state) {
                case Studio:
                    updateFadeHoldFade(config.studioDuration, config.studioFadeDuration, function() {
                        setScreen(Engine);
                    });

                case Engine:
                    updateFadeHoldFade(config.engineDuration, config.engineFadeDuration, function() {
                        setScreen(Disclaimer);
                    });

                case Disclaimer:
                    var fadeInEnd = 1.0;
                    var fadeOutDur = config.disclaimerFadeOutDuration;

                    if (timer < fadeInEnd) {
                        alpha = timer / fadeInEnd;
                        screenDisclaimer.alpha = alpha;
                    } else if (timer < config.disclaimerMinDuration || !preloader.isComplete) {
                        alpha = 1.0;
                        screenDisclaimer.alpha = 1.0;
                        if (timer >= config.disclaimerMinDuration) {
                            timer = config.disclaimerMinDuration;
                        }
                    } else if (timer < config.disclaimerMinDuration + fadeOutDur) {
                        alpha = 1.0 - ((timer - config.disclaimerMinDuration) / fadeOutDur);
                        screenDisclaimer.alpha = alpha;
                    } else {
                        finishSequence();
                    }

                default:
            }
        }
    }

    /**
     * Updates optional black fade curtain revealing the 3D showcase after intro completes.
     *
     * @param {Float} dt Elapsed frame time in seconds.
     * @param {Null<h2d.Object>} [uiRoot] Root UI view fading in opposite the curtain.
     * @returns {Void}
     */
    public function updateShowcaseCurtain(dt:Float, ?uiRoot:h2d.Object):Void {
        if (!isShowcaseFadingIn) return;
        showcaseFadeTimer += dt;
        var progress = Math.min(1.0, showcaseFadeTimer / config.showcaseFadeDuration);
        if (showcaseCurtain != null) {
            showcaseCurtain.alpha = 1.0 - progress;
        }
        if (uiRoot != null) {
            uiRoot.alpha = progress;
        }
        if (progress >= 1.0) {
            isShowcaseFadingIn = false;
            if (showcaseCurtain != null) {
                showcaseCurtain.remove();
                showcaseCurtain = null;
            }
            if (uiRoot != null) uiRoot.alpha = 1.0;
        }
    }

    /**
     * Allows user input to skip Publisher or Engine splash slides early.
     * Disclaimer slide remains unskippable until mandatory read time and asset preload finish.
     *
     * @returns {Bool} True if a slide skip fade-out was triggered.
     */
    public function trySkip():Bool {
        if ((state == Studio || state == Engine) && !isFadingOut) {
            isFadingOut = true;
            return true;
        }
        return false;
    }

    /**
     * Tears down the intro display layers, initializes the showcase reveal curtain,
     * and fires `onIntroComplete`.
     *
     * @returns {Void}
     */
    public function finishSequence():Void {
        if (state == Complete) return;
        state = Complete;
        if (onStateChanged != null) onStateChanged(state);

        if (introContainer != null) {
            introContainer.removeChildren();
            introContainer.remove();
            introContainer = null;
        }

        if (showcaseCurtain == null && rootLayer != null) {
            var sw = rootLayer.width > 0 ? Std.int(rootLayer.width) : 1280;
            var sh = rootLayer.height > 0 ? Std.int(rootLayer.height) : 720;
            showcaseCurtain = new Bitmap(Tile.fromColor(0x000000, 1, 1, 1.0), rootLayer);
            showcaseCurtain.scaleX = sw;
            showcaseCurtain.scaleY = sh;
            showcaseCurtain.alpha = 1.0;
            isShowcaseFadingIn = true;
            showcaseFadeTimer = 0.0;
        }

        if (onIntroComplete != null) {
            onIntroComplete();
        }
    }

    /**
     * Repositions and scales intro backdrops, splashes, disclaimer brackets, and logo row.
     *
     * @returns {Void}
     */
    public function layout():Void {
        var sw:Float = (rootLayer != null && rootLayer.width > 0) ? rootLayer.width : 1280.0;
        var sh:Float = (rootLayer != null && rootLayer.height > 0) ? rootLayer.height : 720.0;

        if (introBg != null) {
            introBg.scaleX = sw;
            introBg.scaleY = sh;
        }
        if (showcaseCurtain != null) {
            showcaseCurtain.scaleX = sw;
            showcaseCurtain.scaleY = sh;
        }

        scaleAndCenterSplash(studioSplashBmp, sw, sh);
        scaleAndCenterSplash(engineSplashBmp, sw, sh);

        if (discHeader != null && discBody != null) {
            if (discGraphics != null) {
                discGraphics.clear();
                var pad = 28.0;
                var frameW = Math.max(200.0, sw - pad * 2.0);
                var frameH = Math.max(200.0, sh - pad * 2.0);
                discGraphics.beginFill(0x060A10, 0.90);
                discGraphics.lineStyle(1.5, 0x00E5FF, 0.35);
                discGraphics.drawRoundedRect(pad, pad, frameW, frameH, 12.0);
                discGraphics.endFill();

                var bl = 22.0;
                discGraphics.lineStyle(3.0, 0x00E5FF, 0.85);
                discGraphics.moveTo(pad, pad + bl); discGraphics.lineTo(pad, pad); discGraphics.lineTo(pad + bl, pad);
                discGraphics.moveTo(pad + frameW - bl, pad); discGraphics.lineTo(pad + frameW, pad); discGraphics.lineTo(pad + frameW, pad + bl);
                discGraphics.moveTo(pad, pad + frameH - bl); discGraphics.lineTo(pad, pad + frameH); discGraphics.lineTo(pad + bl, pad + frameH);
                discGraphics.moveTo(pad + frameW - bl, pad + frameH); discGraphics.lineTo(pad + frameW, pad + frameH); discGraphics.lineTo(pad + frameW, pad + frameH - bl);
            }

            var maxTextWidth = Math.min(sw * 0.88, 960.0);
            discHeader.maxWidth = maxTextWidth;
            discBody.maxWidth = maxTextWidth;

            var headerGap = 16.0;
            var logoGap = 22.0;
            var targetIconHeight = Math.min(38.0, sh * 0.06);
            var logoSpacing = 32.0;
            var totalLogoWidth = 0.0;

            if (logoRow != null && discLogos.length > 0) {
                for (bmp in discLogos) {
                    if (bmp.tile != null && bmp.tile.height > 0) {
                        var s = targetIconHeight / bmp.tile.height;
                        bmp.scaleX = s;
                        bmp.scaleY = s;
                        totalLogoWidth += bmp.tile.width * s;
                    }
                }
                totalLogoWidth += logoSpacing * (discLogos.length - 1);
            }
            if (Math.isNaN(totalLogoWidth)) totalLogoWidth = 0.0;

            var hHeight = discHeader.textHeight;
            if (Math.isNaN(hHeight) || hHeight <= 0) hHeight = 36.0;
            var bHeight = discBody.textHeight;
            if (Math.isNaN(bHeight) || bHeight <= 0) bHeight = 320.0;

            var vGap = 14.0;
            var vHeight = discVersion != null ? discVersion.textHeight : 0.0;
            if (Math.isNaN(vHeight)) vHeight = 20.0;

            var totalBlockHeight = hHeight + headerGap + bHeight + (discLogos.length > 0 ? (logoGap + targetIconHeight) : 0.0) + (discVersion != null ? (vGap + vHeight) : 0.0);
            if (Math.isNaN(totalBlockHeight) || totalBlockHeight <= 0) totalBlockHeight = 400.0;

            var blockStartY = Math.max(16.0, (sh - totalBlockHeight) * 0.5);
            if (Math.isNaN(blockStartY)) blockStartY = 24.0;

            discHeader.x = (sw - maxTextWidth) * 0.5;
            discHeader.y = blockStartY;
            discBody.x = (sw - maxTextWidth) * 0.5;
            discBody.y = discHeader.y + hHeight + headerGap;

            var rowY = discBody.y + bHeight + logoGap;
            if (logoRow != null && discLogos.length > 0) {
                var currX = (sw - totalLogoWidth) * 0.5;
                if (Math.isNaN(currX)) currX = (sw - 200.0) * 0.5;
                for (bmp in discLogos) {
                    bmp.x = currX;
                    bmp.y = rowY;
                    currX += (bmp.tile.width * bmp.scaleX) + logoSpacing;
                }
            }

            if (discVersion != null) {
                discVersion.maxWidth = maxTextWidth;
                discVersion.x = (sw - maxTextWidth) * 0.5;
                discVersion.y = discLogos.length > 0 ? (rowY + targetIconHeight + vGap) : (discBody.y + bHeight + vGap);
            }
        }
    }

    /**
     * Scales a bitmap cover-style to fill viewport bounds cleanly without stretching aspect.
     *
     * @param {Null<Bitmap>} bmp Target splash image node.
     * @param {Float} sw Viewport width in virtual pixels.
     * @param {Float} sh Viewport height in virtual pixels.
     * @returns {Void}
     */
    private function scaleAndCenterSplash(bmp:Null<Bitmap>, sw:Float, sh:Float):Void {
        if (bmp == null || bmp.tile == null || bmp.tile.width <= 0 || bmp.tile.height <= 0) return;
        var naturalW = bmp.tile.width;
        var naturalH = bmp.tile.height;
        var scale = Math.max(sw / naturalW, sh / naturalH);
        bmp.scaleX = scale;
        bmp.scaleY = scale;
        bmp.x = (sw - naturalW * scale) * 0.5;
        bmp.y = (sh - naturalH * scale) * 0.5;
    }

    /**
     * Evaluates a symmetric fade-in, hold, and fade-out timeline envelope.
     *
     * @param {Float} totalDur Slide lifespan in seconds.
     * @param {Float} fadeDur In/out edge fade duration in seconds.
     * @param {Void -> Void} onFinish Transition callback when slide completes.
     * @returns {Void}
     */
    private function updateFadeHoldFade(totalDur:Float, fadeDur:Float, onFinish:Void -> Void):Void {
        var holdEnd = totalDur - fadeDur;
        if (timer < fadeDur) {
            alpha = timer / fadeDur;
        } else if (timer < holdEnd) {
            alpha = 1.0;
        } else if (timer < totalDur) {
            alpha = 1.0 - ((timer - holdEnd) / fadeDur);
        } else {
            onFinish();
            return;
        }
        applyActiveAlpha();
    }

    /**
     * Applies current computed alpha to whichever intro slide is currently active.
     *
     * @returns {Void}
     */
    private function applyActiveAlpha():Void {
        if (state == Studio) screenStudio.alpha = alpha;
        else if (state == Engine) screenEngine.alpha = alpha;
        else if (state == Disclaimer) screenDisclaimer.alpha = alpha;
    }
}
