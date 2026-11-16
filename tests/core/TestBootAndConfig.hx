package tests.core;

import utest.Test;
import utest.Assert;
import config.GameConfig;
import config.WorldConfig;
import core.AssetPreloader;
import core.IntroController;
import core.IntroController.IntroState;
import ui.FontManager;

/**
 * Unit test suite validating centralized configuration presets, silent background preloading,
 * and boot intro sequence gating before the splash screen activates.
 */
class TestBootAndConfig extends Test {
    public function setup() {
        FontManager.init();
    }

    public function testDefaultConfigsIntegrity() {
        var cfg = GameConfig.getDefault();
        Assert.equals(1280, cfg.resolution.baseWidth);
        Assert.equals(720, cfg.resolution.baseHeight);
        Assert.isTrue(cfg.intro.studioDuration > 0.0);
        Assert.isTrue(cfg.intro.disclaimerMinDuration >= 5.0);
        Assert.equals(3, cfg.intro.engineLogoPaths.length);
        Assert.equals(4, cfg.intro.touchIconPaths.length);

        var tr = WorldConfig.getDefaultTrack();
        Assert.equals(20.0, tr.roadWidth);
        Assert.equals(10.0, tr.halfWidth);

        var sb = WorldConfig.getDefaultSandbox();
        Assert.equals(200.0, sb.halfSpan);
        Assert.equals(195.0, sb.wallLimit);
    }

    public function testPreloaderAndIntroGatedByBackgroundLoading() {
        var cfg = GameConfig.getDefault().intro;
        var preloader = new AssetPreloader(cfg);
        var pendingDone = preloader.beginExternalTask();
        preloader.start();

        Assert.isTrue(preloader.isStarted, "Preloader should mark started immediately");
        Assert.isFalse(preloader.isComplete, "Preloader must stay incomplete while external warmup task is open");

        var intro = new IntroController(null, preloader, cfg);
        var completedCount = 0;
        intro.onIntroComplete = function() {
            completedCount++;
        };

        // Ensure disclaimer container has NO progress bar objects/text
        Assert.notNull(intro.discHeader);
        Assert.notNull(intro.discBody);
        Assert.equals("TRADEMARK & LEGAL DISCLOSURES", intro.discHeader.text);
        var bodyLower = intro.discBody.text.toLowerCase();
        Assert.isTrue(bodyLower.indexOf("loading...") == -1 && bodyLower.indexOf("%") == -1);

        // Step Studio -> Engine -> Disclaimer
        intro.setScreen(IntroState.Studio);
        Assert.equals(IntroState.Studio, intro.state);
        intro.update(cfg.studioDuration + 0.1);
        Assert.equals(IntroState.Engine, intro.state);

        intro.update(cfg.engineDuration + 0.1);
        Assert.equals(IntroState.Disclaimer, intro.state);

        // Even past disclaimerMinDuration + fadeOutDuration, intro MUST hold on Disclaimer until preload finishes
        intro.update(1.0);
        intro.update(cfg.disclaimerMinDuration + 2.0);
        Assert.equals(IntroState.Disclaimer, intro.state);
        Assert.equals(0, completedCount, "Splash must NOT open while background loading is still pending");

        // Resolve remaining background asset/world task -> now Disclaimer fades out cleanly and fires onIntroComplete
        pendingDone();
        Assert.isTrue(preloader.isComplete, "Preloader should complete once final task resolves");

        intro.update(cfg.disclaimerFadeOutDuration + 0.15);
        Assert.equals(IntroState.Complete, intro.state);
        Assert.equals(1, completedCount, "onIntroComplete must fire once loading completes and disclaimer finishes");
    }

    public function testIntroSkipAllowedOnlyOnStudioAndEngine() {
        var preloader = new AssetPreloader();
        var intro = new IntroController(null, preloader);

        intro.setScreen(IntroState.Studio);
        Assert.isTrue(intro.trySkip(), "Publisher splash may be skipped early");

        intro.setScreen(IntroState.Engine);
        Assert.isTrue(intro.trySkip(), "Engine attribution splash may be skipped early");

        intro.setScreen(IntroState.Disclaimer);
        Assert.isFalse(intro.trySkip(), "Legal disclaimer must not skip while background preloading is active");
    }
}
