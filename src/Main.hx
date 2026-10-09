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
import camera.ChaseCamera;
import ui.UIManager;
import ui.components.UIEnums.MenuAction;
import audio.AudioManager;
import graphics.GraphicsManager;
import save.SaveSystem;
import ui.FontManager;
import world.Track;
import world.Skybox;
import entities.CarMesh;
import entities.TrafficSystem;
import graphics.PostProcessRenderer;

/**
 * Sequential boot loader and splash screen sequence stages.
 */
enum IntroState {
    /** Null or uninitialized state. */
    None;

    /** Studio production splash screen (RvL // Rogue). */
    Studio;

    /** Engine and language splash screen (Haxe & Heaps.io). */
    Engine;

    /** Legal disclosures, attribution notices, and health advisory screen. */
    Disclaimer;

    /** Splash sequence finished; transferred to 3D game showcase. */
    Complete;
}

/**
 * Top-level application lifecycle state.
 */
enum AppState {
    /** Boot sequence running intro splash screens. */
    IntroSequence;

    /** Interactive 3D gameplay and user interface system active. */
    InGameUI;
}

/**
 * Main application entry point for M.O.B. (Motors on Boost).
 * Manages boot splash sequencing, WebP texture decoding, 3D scene initialization,
 * car physics updates, third-person spring-arm camera tracking, and UI lifecycle.
 */
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
    var discHeader:Text;
    var discBody:Text;
    var discVersion:Text;
    var logoRow:Object;
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
    var skybox:Skybox;
    var postRenderer:PostProcessRenderer;
    var wheelSpinAngle:Float = 0.0;

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

        // Responsive High-DPI & Multi-Resolution UI Scaling
        // Target virtual baseline: 1280x720. AutoZoom scales UI elements, fonts,
        // and interactive touch hitboxes proportionally on 2K/4K and mobile Retina displays.
        s2d.scaleMode = AutoZoom(1280, 720, false);

        buildIntroScreens();
        setIntroScreen(Studio);

        #if js
        untyped js.Browser.window.app = this;
        #end
    }

    // =========================================================================
    // NATIVE WEBP DECODER (DOM Image -> Canvas -> Bytes -> Heaps Texture -> Tile)
    // =========================================================================

    /**
     * Decodes WebP image assets natively using an offscreen HTML5 canvas buffer pipeline.
     * Extracts RGBA byte buffers and uploads them into hardware Heaps textures.
     *
     * @param path Relative path to the WebP image asset.
     * @param onLoaded Callback invoked with the decoded Heaps `h2d.Tile`.
     */
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

        // 3. Trademark & Disclosure Notice Screen
        screenDisclaimer = new Object(introContainer);

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
                    introBg.alpha = 1.0; // Keep background completely black as text fades out
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
        showcaseCurtain.scaleX = s2d.width;
        showcaseCurtain.scaleY = s2d.height;

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

        // High-performance post-processing renderer supporting radial directional blur
        postRenderer = new PostProcessRenderer();
        s3d.renderer = postRenderer;
        s3d.camera.zFar = 1500.0;

        // Atmospheric panoramic gradient blue skybox
        skybox = new Skybox(s3d);

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

        // Position directional sunlight at the tallest south-east point of the entire map
        // (X: +350.0 [East], Y: -250.0 [South], Z: 140.0 [Apex Summit elevation])
        var sunDir = new Vector(-0.55, 0.78, -0.32);
        sunDir.normalize();
        dirLight = new DirLight(sunDir, s3d);
        dirLight.setPosition(350.0, -250.0, 140.0);
        dirLight.color.setColor(0xFFF2D9);

        gfx = new GraphicsManager(s3d, s2d, dirLight, saveData.graphics);

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

    /**
     * Repositions the player vehicle to the race track starting grid line.
     */
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

    /**
     * Serializes active race progress, coordinates, audio settings, and graphics profiles to storage.
     */
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

    /**
     * Dispatches user menu selections (Start, Resume, Options, Credits, Quit).
     *
     * @param action Selected MenuAction enum variant.
     */
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
        var sw = s2d != null ? s2d.width : hxd.Window.getInstance().width;
        var sh = s2d != null ? s2d.height : hxd.Window.getInstance().height;

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

        if (discHeader != null && discBody != null) {
            // Responsive line constraints ensuring text stays nicely proportioned
            var maxTextWidth = Math.min(sw * 0.88, 960.0);
            discHeader.maxWidth = maxTextWidth;
            discBody.maxWidth = maxTextWidth;

            var headerGap = 16.0;
            var logoGap = 22.0;

            var targetIconHeight = Math.min(38.0, sh * 0.06);
            var logoSpacing = 32.0; // very light spacing horizontally
            var totalLogoWidth = 0.0;

            if (logoRow != null && discLogos.length > 0) {
                for (bmp in discLogos) {
                    if (bmp.tile != null) {
                        var s = targetIconHeight / bmp.tile.height;
                        bmp.scaleX = s;
                        bmp.scaleY = s;
                        totalLogoWidth += (bmp.tile.width * s);
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
            var vHeight = (discVersion != null) ? discVersion.textHeight : 0.0;
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
                discVersion.y = (discLogos.length > 0) ? (rowY + targetIconHeight + vGap) : (discBody.y + bHeight + vGap);
            }
        }
    }

    override function onResize() {
        super.onResize();

        if (gfx != null) {
            gfx.applyRenderScale();
            gfx.applyUIResolution();
        } else if (s2d != null) {
            s2d.checkResize();
        }

        if (showcaseCurtain != null && s2d != null) {
            showcaseCurtain.scaleX = s2d.width;
            showcaseCurtain.scaleY = s2d.height;
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

        if (skybox != null) skybox.syncCamera(s3d.camera.pos);

        switch (ui.currentState) {
            case Splash | MainMenu | CreditsScreen:
                if (postRenderer != null) postRenderer.blurShader.blurIntensity = 0.0;
                showcaseAngle += 0.35 * dt;
                var camDist = 11.0;
                s3d.camera.pos.set(
                    carPhysics.pos.x + Math.sin(showcaseAngle) * camDist,
                    carPhysics.pos.y - Math.cos(showcaseAngle) * camDist,
                    carPhysics.pos.z + 4.2
                );
                s3d.camera.target.set(carPhysics.pos.x, carPhysics.pos.y, carPhysics.pos.z + 1.2);

            case PauseMenu | OptionsMenu:
                if (postRenderer != null) postRenderer.blurShader.blurIntensity = 0.0;
                if (ui.isOpenedFromPause && input.pausePressed && !input.isListeningForRemap) {
                    input.flushInputs();
                    ui.showInGame();
                }

            case InGameHUD:
                if (input.pausePressed) {
                    input.flushInputs();
                    if (postRenderer != null) postRenderer.blurShader.blurIntensity = 0.0;
                    saveCurrentRun();
                    ui.showPause();
                    return;
                }

                var wasDrifting = carPhysics.isDrifting;
                carPhysics.update(dt, input, track != null ? track.waypoints : null);

                if (!wasDrifting && carPhysics.isDrifting) chaseCam.addTrauma(0.35);
                if (input.boost && carPhysics.forwardSpeed > 20.0) chaseCam.addTrauma(0.12 * dt * 60.0);

                // High-speed radial directional blur scaling
                var kmh = Math.round(Math.abs(carPhysics.forwardSpeed) * 3.6);
                var blurIntensity = 0.0;
                if (kmh > 140) {
                    blurIntensity = Math.min(0.065, ((kmh - 140.0) / 180.0) * 0.055);
                }
                if (input.boost && kmh > 70) blurIntensity = Math.min(0.08, blurIntensity + 0.025);
                if (postRenderer != null) postRenderer.blurShader.blurIntensity = blurIntensity;

                traffic.update(dt, carPhysics, chaseCam);

                playerMesh.x = carPhysics.pos.x;
                playerMesh.y = carPhysics.pos.y;
                playerMesh.z = carPhysics.pos.z + Track.ROAD_LIFT;
                playerMesh.setRotation(carPhysics.pitch, carPhysics.roll, carPhysics.yaw + carPhysics.driftAngle);

                // Four-wheel steering and longitudinal spin animation
                wheelSpinAngle += (carPhysics.forwardSpeed * dt) / 0.36;
                var maxSteerAngle = 0.55;
                var currentSteer = input.steer * maxSteerAngle;
                if (playerMesh.wheels.length >= 4) {
                    // Front-Left (0): Steer & Roll
                    playerMesh.wheels[0].setRotation(0, 0, currentSteer);
                    playerMesh.wheels[0].rotate(0, 1.5707963, 0);
                    playerMesh.wheels[0].rotate(wheelSpinAngle, 0, 0);

                    // Front-Right (1): Steer & Roll
                    playerMesh.wheels[1].setRotation(0, 0, currentSteer);
                    playerMesh.wheels[1].rotate(0, 1.5707963, 0);
                    playerMesh.wheels[1].rotate(wheelSpinAngle, 0, 0);

                    // Rear-Left (2): Roll
                    playerMesh.wheels[2].setRotation(0, 0, 0);
                    playerMesh.wheels[2].rotate(0, 1.5707963, 0);
                    playerMesh.wheels[2].rotate(wheelSpinAngle, 0, 0);

                    // Rear-Right (3): Roll
                    playerMesh.wheels[3].setRotation(0, 0, 0);
                    playerMesh.wheels[3].rotate(0, 1.5707963, 0);
                    playerMesh.wheels[3].rotate(wheelSpinAngle, 0, 0);
                }

                chaseCam.update(dt, carPhysics, input.boost);

                var gearStr = carPhysics.currentGear == -1 ? "R" : (carPhysics.currentGear == 0 ? "N" : "G" + carPhysics.currentGear);
                var rpm = Math.round(carPhysics.engineRPM);
                speedText.text = kmh + " KM/H [" + gearStr + "] (" + rpm + " RPM)" + (carPhysics.isDrifting ? " [DRIFTING]" : "") + (input.boost ? " [NITRO]" : "");
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