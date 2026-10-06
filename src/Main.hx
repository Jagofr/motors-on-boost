package;

import h3d.scene.Mesh;
import h3d.prim.Cube;
import h3d.scene.fwd.DirLight;
import h3d.Vector;
import h2d.Object;
import h2d.Text;
import h2d.Bitmap;
import h2d.Tile;

import input.InputController;
import physics.CarPhysics;
import core.ChaseCamera;
import core.UIManager;
import core.AudioManager;
import core.GraphicsManager;
import core.SaveSystem;
import core.FontManager;
import world.Track;
import entities.CarMesh;
import entities.TrafficSystem;

enum IntroState {
    None;
    Studio;
    Engine;
    Disclaimer;
    Complete;
}

enum AppState {
    IntroSequence;
    InGameUI;
}

class Main extends hxd.App {
    var appState:AppState = IntroSequence;
    var introState:IntroState = Studio;

    // Intro Phase Timers & Transitions
    var introTimer:Float = 0.0;
    var introAlpha:Float = 0.0;
    var isFadingOut:Bool = false;
    var introContainer:Object;
    var introBg:Bitmap;
    var screenStudio:Object;
    var screenEngine:Object;
    var screenDisclaimer:Object;

    // Post-Intro Showcase Fade-in Transition
    var showcaseFadeTimer:Float = 0.0;
    var showcaseFadeDuration:Float = 1.2;
    var isShowcaseFadingIn:Bool = false;
    var showcaseCurtain:Bitmap;

    // Splash Bitmaps loaded via WebP decoder
    var studioSplashBmp:Bitmap;
    var engineSplashBmp:Bitmap;
    var discLogos:Array<Bitmap> = [];

    // Background Asset Pre-loading
    var isLoadingStarted:Bool = false;
    var isLoadingComplete:Bool = false;
    var disclaimerMinDuration:Float = 5.5; // Locked time (seconds)

    // Game Core Systems & Singletons
    var fpsText:Text;
    var speedText:Text;
    var ui:UIManager;
    var audio:AudioManager;
    var gfx:GraphicsManager;
    var saveData:GameSaveData;

    var track:Track;
    var traffic:TrafficSystem;
    var playerMesh:CarMesh;
    var carPhysics:CarPhysics;
    var terrainGround:Mesh;
    var input:InputController;
    var chaseCam:ChaseCamera;
    var dirLight:DirLight;

    var showcaseAngle:Float = 0.0;

    override function init() {
        super.init();

        engine.backgroundColor = 0x000000;

        #if js
        hxd.Res.initEmbed();
        #else
        hxd.Res.initLocal();
        #end

        FontManager.init();
        input = new InputController();

        buildIntroScreens();
        setIntroScreen(Studio);
    }

    // =========================================================================
    // NATIVE WEBP DECODER (DOM Image -> Canvas -> Bytes -> Heaps Texture -> Tile)
    // =========================================================================

    function loadWebpTile(path:String, onLoaded:Tile->Void) {
        #if js
        var img = new js.html.Image();
        img.onload = function(_) {
            var w = img.naturalWidth;
            var h = img.naturalHeight;

            var canvas = js.Browser.document.createCanvasElement();
            canvas.width = w;
            canvas.height = h;

            var ctx = canvas.getContext2d();
            ctx.drawImage(img, 0, 0);

            var imgData = ctx.getImageData(0, 0, w, h);
            var bytes = haxe.io.Bytes.ofData(imgData.data.buffer);

            var bmp = new hxd.BitmapData(w, h);
            bmp.setPixels(new hxd.Pixels(w, h, bytes, hxd.PixelFormat.RGBA));

            var tex = h3d.mat.Texture.fromBitmap(bmp);
            var tile = Tile.fromTexture(tex);
            onLoaded(tile);
        };
        img.onerror = function(err) {
            trace("WebP load failure for: " + path);
        };
        img.src = path;
        #else
        trace("WebP loading requires JS/HTML5 target.");
        #end
    }

    // =========================================================================
    // INTRO SCREEN BUILDERS & STATE MACHINE
    // =========================================================================

    function buildIntroScreens() {
        introContainer = new Object(s2d);

        // Solid Black Opaque Backplate
        introBg = new Bitmap(Tile.fromColor(0x000000, 1, 1, 1.0), introContainer);

        // 1. Studio Splash
        screenStudio = new Object(introContainer);
        loadWebpTile("intro/jagofr-rvl-splash.webp", function(tile) {
            studioSplashBmp = new Bitmap(tile, screenStudio);
            layoutIntro();
        });

        // 2. Engine Splash
        screenEngine = new Object(introContainer);
        loadWebpTile("intro/heaps-haxe-splash.webp", function(tile) {
            engineSplashBmp = new Bitmap(tile, screenEngine);
            layoutIntro();
        });

        // 3. Disclaimer Screen
        screenDisclaimer = new Object(introContainer);

        var discHeader = new Text(FontManager.titleFont, screenDisclaimer);
        discHeader.text = "IMPORTANT NOTICES & DISCLAIMERS";
        discHeader.textColor = 0xFFEE00;
        discHeader.name = "header";

        var discBody = new Text(FontManager.regularFont, screenDisclaimer);
        discBody.textColor = 0xD0DCE8;
        discBody.textAlign = Center;
        discBody.maxWidth = 880;
        discBody.text = 
            "DEVELOPMENT & IN-HOUSE PUBLISHING\n" +
            "Developed by Gerard \"Jamie\" (Jagofr) Francis.\n" +
            "Published and developed in-house by RvL // ROGUE, with assistance by Google Gemini 3.8 Flash.\n\n" +
            "COMMUNITY ASSET & FOSS DISCLOSURE\n" +
            "Built with Haxe and Heaps.io. Typography provided under the SIL Open Font License and Apache 2.0.\n\n" +
            "INTELLECTUAL PROPERTY NOTICE\n" +
            "All custom codebases, vehicles, handling physics, procedural tracks, and original visual designs\n" +
            "are the intellectual property of the creators. All rights reserved.\n\n" +
            "HEALTHY GAMING ADVISORY\n" +
            "Please take a 15-minute break for every 1 hour of playtime.";
        discBody.name = "body";

        var logoRow = new Object(screenDisclaimer);
        logoRow.name = "logoRow";

        var logoPaths = [
            "intro/icons/logo_haxe.webp",
            "intro/icons/logo_heaps.webp",
            "intro/icons/logo_webgl.webp"
        ];

        for (path in logoPaths) {
            loadWebpTile(path, function(tile) {
                var bmp = new Bitmap(tile, logoRow);
                discLogos.push(bmp);
                layoutIntro();
            });
        }

        layoutIntro();
    }

    function setIntroScreen(target:IntroState) {
        introState = target;
        introTimer = 0.0;
        introAlpha = 0.0;
        isFadingOut = false;

        screenStudio.visible = (introState == Studio);
        screenEngine.visible = (introState == Engine);
        screenDisclaimer.visible = (introState == Disclaimer);

        screenStudio.alpha = 0.0;
        screenEngine.alpha = 0.0;
        screenDisclaimer.alpha = 0.0;

        if (introState == Disclaimer && !isLoadingStarted) {
            startBackgroundLoading();
        }

        layoutIntro();
    }

    function updateIntro(dt:Float) {
        introTimer += dt;

        var allowSkip = (introState == Studio || introState == Engine);
        if (allowSkip && input.anyKeyPressed && !isFadingOut) {
            input.flushInputs();
            isFadingOut = true;
            introTimer = Math.max(introTimer, 2.5);
        }

        switch (introState) {
            case Studio | Engine:
                var fadeInEnd = 0.8;
                var holdEnd = 2.4;
                var fadeOutEnd = 3.2;

                if (introTimer < fadeInEnd) {
                    introAlpha = introTimer / fadeInEnd;
                } else if (introTimer < holdEnd) {
                    introAlpha = 1.0;
                } else if (introTimer < fadeOutEnd) {
                    introAlpha = 1.0 - ((introTimer - holdEnd) / (fadeOutEnd - holdEnd));
                } else {
                    introAlpha = 0.0;
                    setIntroScreen(introState == Studio ? Engine : Disclaimer);
                    return;
                }

                var currentScreen = (introState == Studio) ? screenStudio : screenEngine;
                currentScreen.alpha = Math.max(0.0, Math.min(1.0, introAlpha));

            case Disclaimer:
                var fadeInEnd = 1.0;

                if (introTimer < fadeInEnd) {
                    introAlpha = introTimer / fadeInEnd;
                    screenDisclaimer.alpha = introAlpha;
                } else if (introTimer < disclaimerMinDuration || !isLoadingComplete) {
                    introAlpha = 1.0;
                    screenDisclaimer.alpha = 1.0;
                } else if (introTimer < disclaimerMinDuration + 1.0) {
                    var fadeProgress = (introTimer - disclaimerMinDuration) / 1.0;
                    introAlpha = 1.0 - Math.min(1.0, fadeProgress);
                    
                    screenDisclaimer.alpha = introAlpha;
                    introBg.alpha = introAlpha;
                } else {
                    finishIntroSequence();
                    return;
                }

            default:
        }
    }

    function finishIntroSequence() {
        introState = Complete;
        appState = InGameUI;
        introContainer.remove();

        input.flushInputs();

        engine.backgroundColor = 0x1A1F26;

        // Setup smooth transition into the 3D scene & splash UI
        isShowcaseFadingIn = true;
        showcaseFadeTimer = 0.0;

        showcaseCurtain = new Bitmap(Tile.fromColor(0x000000, 1, 1, 1.0), s2d);
        showcaseCurtain.scaleX = hxd.Window.getInstance().width;
        showcaseCurtain.scaleY = hxd.Window.getInstance().height;

        if (ui != null) {
            ui.visible = true;
            ui.alpha = 0.0;
            ui.showSplash();
        }
    }

    // =========================================================================
    // BACKGROUND PRE-LOADING HOOK
    // =========================================================================

    function startBackgroundLoading() {
        isLoadingStarted = true;

        saveData = SaveSystem.load();

        audio = new AudioManager();
        audio.masterVolume = saveData.masterVol;
        audio.musicVolume = saveData.musicVol;
        audio.sfxVolume = saveData.sfxVol;

        carPhysics = new CarPhysics(0.0, 0.0, 0.0);
        chaseCam = new ChaseCamera(s3d.camera, 0.0, -10.0, 4.0);

        fpsText = new Text(FontManager.regularFont, s2d);
        fpsText.textColor = 0xFFEE00;
        fpsText.x = 14;
        fpsText.y = 14;
        fpsText.visible = false;

        speedText = new Text(FontManager.regularFont, s2d);
        speedText.textColor = 0x00E5FF;
        speedText.x = 14;
        speedText.y = 36;
        speedText.visible = false;

        dirLight = new DirLight(new Vector(-0.55, 0.45, -0.7), s3d);
        dirLight.color.setColor(0xFFE8C2);

        gfx = new GraphicsManager(s3d, dirLight, saveData.graphics);

        var terrainPrim = new Cube(800.0, 800.0, 0.4, true);
        terrainPrim.unindex();
        terrainPrim.addNormals();
        terrainGround = new Mesh(terrainPrim, s3d);
        terrainGround.material.color.setColor(0x111418);
        terrainGround.x = 110.0;
        terrainGround.y = 90.0;
        terrainGround.z = -2.5;

        track = new Track(s3d);
        traffic = new TrafficSystem(track.waypoints, s3d);
        playerMesh = new CarMesh(s3d);

        ui = new UIManager(input, saveData.graphics, saveData.hasActiveRun, s2d);
        ui.visible = false;
        ui.onMenuAction = handleMenuAction;

        resetCarToStartLine();

        isLoadingComplete = true;
    }

    function resetCarToStartLine() {
        carPhysics.pos.set(0.0, 0.0, 0.0);
        carPhysics.yaw = 1.5707963;
        carPhysics.forwardSpeed = 0.0;
        carPhysics.lateralVelocity = 0.0;
        carPhysics.isDrifting = false;

        playerMesh.x = 0.0;
        playerMesh.y = 0.0;
        playerMesh.z = Track.ROAD_LIFT;
        playerMesh.setRotation(0, 0, 0);
    }

    function saveCurrentRun() {
        saveData.hasActiveRun = true;
        saveData.playerState = {
            posX: carPhysics.pos.x,
            posY: carPhysics.pos.y,
            posZ: carPhysics.pos.z,
            yaw: carPhysics.yaw,
            forwardSpeed: carPhysics.forwardSpeed
        };
        saveData.masterVol = audio.masterVolume;
        saveData.musicVol = audio.musicVolume;
        saveData.sfxVol = audio.sfxVolume;
        saveData.graphics = ui.gfxSettings;
        SaveSystem.save(saveData);
        ui.setHasActiveSave(true);
    }

    function handleMenuAction(action:MenuAction) {
        input.flushInputs();

        switch (action) {
            case StartGame:
                resetCarToStartLine();
                ui.showInGame();
                fpsText.visible = true;
                speedText.visible = true;

            case ResumeGame:
                if (saveData.hasActiveRun) {
                    carPhysics.pos.set(saveData.playerState.posX, saveData.playerState.posY, saveData.playerState.posZ);
                    carPhysics.yaw = saveData.playerState.yaw;
                    carPhysics.forwardSpeed = saveData.playerState.forwardSpeed;
                }
                ui.showInGame();
                fpsText.visible = true;
                speedText.visible = true;

            case OpenOptions:
            case OpenCredits:
                ui.showCredits();

            case QuitToTitle:
                saveCurrentRun();
                fpsText.visible = false;
                speedText.visible = false;
                ui.showMainMenu();
        }
    }

    function scaleAndCenterSplash(bmp:Bitmap, sw:Float, sh:Float) {
        if (bmp == null || bmp.tile == null) return;
        var naturalW = bmp.tile.width;
        var naturalH = bmp.tile.height;

        var scale = Math.min((sw * 0.90) / naturalW, (sh * 0.90) / naturalH);
        bmp.scaleX = scale;
        bmp.scaleY = scale;

        bmp.x = (sw - (naturalW * scale)) * 0.5;
        bmp.y = (sh - (naturalH * scale)) * 0.5;
    }

    function layoutIntro() {
        var sw = hxd.Window.getInstance().width;
        var sh = hxd.Window.getInstance().height;

        if (introBg != null) {
            introBg.scaleX = sw;
            introBg.scaleY = sh;
        }

        if (studioSplashBmp != null) {
            scaleAndCenterSplash(studioSplashBmp, sw, sh);
        }

        if (engineSplashBmp != null) {
            scaleAndCenterSplash(engineSplashBmp, sw, sh);
        }

        var discHeader = screenDisclaimer.getObjectByName("header");
        var discBody = screenDisclaimer.getObjectByName("body");
        var logoRow = screenDisclaimer.getObjectByName("logoRow");

        if (discHeader != null && discBody != null) {
            var dh = cast(discHeader, Text);
            var db = cast(discBody, Text);

            dh.x = (sw - dh.textWidth) * 0.5;
            dh.y = sh * 0.12;

            db.x = (sw - db.textWidth) * 0.5;
            db.y = sh * 0.24;
        }

        if (logoRow != null && discLogos.length > 0) {
            var targetIconHeight = 44.0;
            var spacing = 64.0;
            var totalWidth = 0.0;

            for (bmp in discLogos) {
                var s = targetIconHeight / bmp.tile.height;
                bmp.scaleX = s;
                bmp.scaleY = s;
                totalWidth += (bmp.tile.width * s);
            }
            totalWidth += spacing * (discLogos.length - 1);

            var currX = (sw - totalWidth) * 0.5;
            var rowY = sh * 0.82;

            for (bmp in discLogos) {
                bmp.x = currX;
                bmp.y = rowY;
                currX += (bmp.tile.width * bmp.scaleX) + spacing;
            }
        }
    }

    override function onResize() {
        super.onResize();

        if (s2d != null) s2d.checkResize();
        if (gfx != null) gfx.applyRenderScale();

        if (showcaseCurtain != null) {
            showcaseCurtain.scaleX = hxd.Window.getInstance().width;
            showcaseCurtain.scaleY = hxd.Window.getInstance().height;
        }

        if (appState == IntroSequence) {
            layoutIntro();
        } else if (ui != null) {
            ui.layout();
        }
    }

    override function update(dt:Float) {
        input.update(dt);

        if (appState == IntroSequence) {
            updateIntro(dt);
            return;
        }

        // Post-intro smooth fade-in management
        if (isShowcaseFadingIn) {
            showcaseFadeTimer += dt;
            var progress = Math.min(1.0, showcaseFadeTimer / showcaseFadeDuration);

            if (showcaseCurtain != null) {
                showcaseCurtain.alpha = 1.0 - progress;
            }
            if (ui != null) {
                ui.alpha = progress;
            }

            if (progress >= 1.0) {
                isShowcaseFadingIn = false;
                if (showcaseCurtain != null) {
                    showcaseCurtain.remove();
                    showcaseCurtain = null;
                }
                if (ui != null) ui.alpha = 1.0;
            }
        }

        ui.update(dt, input.uiUpPressed, input.uiDownPressed, input.uiLeftPressed, input.uiRightPressed, input.uiConfirmPressed, input.uiCancelPressed);

        switch (ui.currentState) {
            case Splash | MainMenu | CreditsScreen:
                showcaseAngle += 0.35 * dt;
                var camDist = 11.0;
                s3d.camera.pos.set(
                    carPhysics.pos.x + Math.sin(showcaseAngle) * camDist,
                    carPhysics.pos.y - Math.cos(showcaseAngle) * camDist,
                    carPhysics.pos.z + 4.2
                );
                s3d.camera.target.set(carPhysics.pos.x, carPhysics.pos.y, carPhysics.pos.z + 1.2);

            case PauseMenu | OptionsMenu:
                if (ui.isOpenedFromPause && input.pausePressed && !input.isListeningForRemap) {
                    input.flushInputs();
                    ui.showInGame();
                }

            case InGameHUD:
                if (input.pausePressed) {
                    input.flushInputs();
                    saveCurrentRun();
                    ui.showPause();
                    return;
                }

                var wasDrifting = carPhysics.isDrifting;
                carPhysics.update(dt, input);

                if (!wasDrifting && carPhysics.isDrifting) chaseCam.addTrauma(0.35);
                if (input.boost && carPhysics.forwardSpeed > 20.0) chaseCam.addTrauma(0.12 * dt * 60.0);

                traffic.update(dt, carPhysics, chaseCam);

                playerMesh.x = carPhysics.pos.x;
                playerMesh.y = carPhysics.pos.y;
                playerMesh.z = carPhysics.pos.z + Track.ROAD_LIFT;
                playerMesh.setRotation(carPhysics.pitch, carPhysics.roll, carPhysics.yaw + carPhysics.driftAngle);

                var maxSteerAngle = 0.55;
                var currentSteer = input.steer * maxSteerAngle;
                if (playerMesh.wheels.length >= 2) {
                    playerMesh.wheels[0].setRotation(0, 0, currentSteer);
                    playerMesh.wheels[0].rotate(0, 1.5707963, 0);

                    playerMesh.wheels[1].setRotation(0, 0, currentSteer);
                    playerMesh.wheels[1].rotate(0, 1.5707963, 0);
                }

                chaseCam.update(dt, carPhysics, input.boost);

                var kmh = Math.round(Math.abs(carPhysics.forwardSpeed) * 3.6);
                speedText.text = kmh + " KM/H" + (carPhysics.isDrifting ? " [DRIFTING]" : "") + (input.boost ? " [NITRO]" : "");
                fpsText.text = "FPS: " + Math.round(hxd.Timer.fps());
        }
    }

    static function main() {
        #if js
        js.Browser.window.onload = function() {
            new Main();
        };
        #else
        new Main();
        #end
    }
}