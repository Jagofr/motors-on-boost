package;

import h2d.Bitmap;
import h2d.Object;
import h2d.Text;
import h3d.Engine;
import camera.ChaseCamera;
import config.GameConfig;
import config.GameConfig.GameConfigData;
import core.AssetPreloader;
import core.IntroController;
import core.IntroController.IntroState;
import entities.CarMesh;
import entities.TrafficSystem;
import graphics.GraphicsManager;
import input.InputController;
import audio.AudioManager;
import net.MultiplayerManager;
import net.NetworkProtocol.LobbyStatus;
import net.NetworkProtocol.NetworkRole;
import net.NetworkProtocol.PeerSlotInfo;
import net.NetworkProtocol.SpawnSlot;
import net.SocketTransport.WebSocketTransport;
import physics.CarPhysics;
import save.SaveSystem;
import ui.FontManager;
import ui.UIManager;
import ui.components.UIEnums.MenuAction;
import world.SandboxMap;
import world.Track;
import world.WorldManager;
import world.WorldManager.MapMode;

/**
 * Top-level application lifecycle phase.
 *
 * @enum {Int} AppState
 * @module Main
 */
enum AppState {
    /** Boot sequence displaying studio, engine, and legal disclaimer screens while loading assets. */
    IntroSequence;

    /** Interactive 3D world showcase, UI navigation, and gameplay active. */
    InGameUI;
}

/**
 * Thin application entry point and coordinator for M.O.B. (Motors on Boost).
 * Delegates boot sequencing to `IntroController`, asynchronous loading to `AssetPreloader`,
 * 3D world orchestration to `WorldManager`, and UI workflows to `UIManager`.
 *
 * @class Main
 * @extends hxd.App
 * @module Main
 */
@:keep
class Main extends hxd.App {
    /** Default virtual canvas width in logical pixels. @default 1280 */
    public static inline var VIRTUAL_BASE_WIDTH:Int = 1280;

    /** Default virtual canvas height in logical pixels. @default 720 */
    public static inline var VIRTUAL_BASE_HEIGHT:Int = 720;

    /** Minimum legal disclaimer dwell duration in seconds. @default 5.5 */
    public static inline var DISCLAIMER_MIN_DURATION:Float = 5.5;

    /** Showcase reveal curtain fade duration in seconds. @default 1.2 */
    public static inline var SHOWCASE_FADE_DURATION:Float = 1.2;

    /** Speed threshold activating radial blur in km/h. @default 140.0 */
    public static inline var RADIAL_BLUR_SPEED_THRESHOLD_KMH:Float = 140.0;

    /** Camera far clipping distance in meters. @default 1500.0 */
    public static inline var CAMERA_FAR_PLANE:Float = 1500.0;

    /** Top-level runtime configuration bundle. */
    public var config:GameConfigData;

    /** Active lifecycle state (boot sequence vs interactive UI/gameplay). */
    public var appState:AppState = IntroSequence;

    /** Current intro state mirrored for external inspection. */
    @:keep public var introState:IntroState = Studio;

    /** Active playable map mode mirrored for external inspection. */
    @:keep public var currentMapMode:MapMode = Circuit;

    /** Background WebP/texture/scene preloader running silently without progress bars. */
    @:keep public var preloader:AssetPreloader;

    /** Intro slide and disclosure sequence state machine. */
    @:keep public var introController:IntroController;

    /** Unified 3D world, skybox, physics, traffic, and camera manager. */
    @:keep public var world:WorldManager;

    /** Modular 2D menu and HUD coordinator. */
    @:keep public var ui:UIManager;

    /** Peer-to-peer multiplayer coordinator (Host-authoritative validation over dumb socket relay). */
    @:keep public var multiplayer:MultiplayerManager;

    /** Unified keyboard, gamepad, and multi-touch input rack controller. */
    @:keep public var input:InputController;

    /** WebAudio synthesized SFX and ambient music manager. */
    @:keep public var audio:AudioManager;

    /** GPU shadows, lighting, MSAA, and resolution profile manager. */
    @:keep public var gfx:GraphicsManager;

    /** Serialized player progress, settings, and bindings profile. */
    @:keep public var saveData:GameSaveData;

    // =========================================================================
    // EXTERNAL JS FACADE MIRRORS (COMPATIBLE WITH PLAYWRIGHT / AITESTS)
    // =========================================================================

    @:keep public var introTimer:Float = 0.0;
    var syncedIntroTimer:Float = 0.0;

    @:keep public var introContainer:Object;
    @:keep public var introBg:Bitmap;
    @:keep public var screenStudio:Object;
    @:keep public var screenEngine:Object;
    @:keep public var screenDisclaimer:Object;
    @:keep public var studioSplashBmp:Bitmap;
    @:keep public var engineSplashBmp:Bitmap;
    @:keep public var discHeader:Text;

    @:keep public var track:Track;
    @:keep public var sandboxMap:SandboxMap;
    @:keep public var traffic:TrafficSystem;
    @:keep public var playerMesh:CarMesh;
    @:keep public var carPhysics:CarPhysics;
    @:keep public var chaseCam:ChaseCamera;

    var systemsInitialized:Bool = false;
    /** Whether mobile/tablet portrait orientation lock currently suspends game updates and rendering. */
    @:keep public var pausedByOrientation:Bool = false;
    var raceTimer:Float = 0.0;
    var currentLap:Int = 1;
    var totalLaps:Int = 3;

    /**
     * Initializes engine scaling, embedded assets, background preloader, and the boot intro sequence.
     *
     * @returns {Void}
     */
    override function init() {
        super.init();
        config = GameConfig.getDefault();

        #if js
        untyped js.Browser.window.app = this;
        untyped js.Browser.window.IntroState = IntroState;
        untyped js.Browser.window.MapMode = MapMode;
        syncOrientationPauseFromHost();
        #end

        s2d.scaleMode = AutoZoom(config.resolution.baseWidth, config.resolution.baseHeight, false);
        engine.backgroundColor = 0x000000;

        #if js
        hxd.Res.initEmbed();
        #else
        try {
            hxd.Res.initEmbed();
        } catch (e:Dynamic) {}
        #end

        FontManager.init();
        input = new InputController(config.input);

        preloader = new AssetPreloader(config.intro);
        introController = new IntroController(s2d, preloader, config.intro);
        introController.onAssetsBound = syncIntroFacade;
        introController.onStateChanged = function(_) syncIntroFacade();
        introController.onIntroComplete = activateMainSplash;
        introController.setScreen(Studio);
        syncIntroFacade();

        // Begin background preloading & deferred 3D world build immediately without any progress bar UI
        preloader.start(ensureDeferredSystemsInitialized);
    }

    /**
     * Lazily constructs audio, persistent save data, 3D world systems, and hidden UI views.
     * Safe and idempotent if invoked asynchronously during boot or synchronously on fast-forward.
     *
     * @returns {Void}
     */
    function ensureDeferredSystemsInitialized():Void {
        if (systemsInitialized) return;
        systemsInitialized = true;

        saveData = SaveSystem.load();
        input.loadFromSave(saveData);

        audio = new AudioManager(config.audio);
        audio.masterVolume = saveData.masterVol;
        audio.musicVolume = saveData.musicVol;
        audio.sfxVolume = saveData.sfxVol;

        world = new WorldManager(s3d, config);

        gfx = new GraphicsManager(s3d, s2d, world.dirLight, saveData.graphics);
        gfx.applyAll();

        multiplayer = new MultiplayerManager(new WebSocketTransport());

        ui = new UIManager(input, saveData.graphics, saveData.hasActiveRun, s2d, multiplayer);
        ui.visible = false;
        ui.onMenuAction = handleMenuAction;
        ui.onPauseRequested = pauseActiveGame;
        ui.builder.optionsView.controlsPanel.getSaveData = function() return saveData;
        ui.builder.optionsView.controlsPanel.onSaveDataUpdated = function(updated) saveData = updated;
        ui.builder.touchControlsHUD.getTouchSettings = function() return saveData != null ? saveData.touchSettings : null;

        multiplayer.onLobbyChanged = function() {
            if (ui != null && ui.builder != null && ui.builder.multiplayerLobbyView != null) {
                ui.builder.multiplayerLobbyView.refreshFromManager();
                if (ui.currentState == MultiplayerLobby) ui.layout();
            }
        };
        multiplayer.onMatchStart = function(mode:MapMode, mySpawn:SpawnSlot, roster:Array<PeerSlotInfo>) {
            loadMap(mode);
            if (world != null) {
                world.clearRemoteCars();
                world.setTrafficEnabled(false);
                world.spawnPlayerAt(mySpawn.x, mySpawn.y, mySpawn.z, mySpawn.yaw);
                for (p in roster) {
                    if (p.peerId == multiplayer.localPeerId) {
                        world.setPlayerPaintColor(p.colorHex);
                    }
                }
            }
            if (ui != null) {
                ui.inGameHUD.remotePeerMarkers = [];
                raceTimer = 0.0;
                currentLap = 1;
                appState = InGameUI;
                ui.visible = true;
                ui.alpha = 1.0;
                ui.showInGame();
            }
        };
        multiplayer.onReturnToLobby = function() {
            if (world != null) {
                world.clearRemoteCars();
                world.setTrafficEnabled(true);
            }
            if (ui != null) {
                ui.inGameHUD.remotePeerMarkers = [];
                ui.showMultiplayerLobby();
            }
        };
        multiplayer.onHostDisconnected = function() {
            if (world != null) {
                world.clearRemoteCars();
                world.setTrafficEnabled(true);
            }
            if (ui != null) {
                ui.inGameHUD.remotePeerMarkers = [];
            }
        };

        syncWorldFacade();
        syncHUDMapBounds();
        if (appState == IntroSequence) {
            if (engine != null) engine.backgroundColor = 0x000000;
            layoutIntro();
        }
    }

    /**
     * Transitions cleanly from finished boot sequence into the interactive 3D showcase and Title Splash.
     *
     * @returns {Void}
     */
    function activateMainSplash():Void {
        ensureDeferredSystemsInitialized();
        syncIntroFacade();
        appState = InGameUI;
        engine.backgroundColor = 0x1A1F26;
        input.flushInputs();

        if (ui != null) {
            ui.visible = true;
            var inviteRoom = MultiplayerManager.detectInviteRoomFromUrl();
            if (inviteRoom != null && multiplayer != null) {
                ui.alpha = 1.0;
                multiplayer.joinRoom(inviteRoom, "GUEST");
                ui.showMultiplayerLobby();
            } else {
                ui.alpha = 0.0;
                ui.showSplash();
            }
        }
    }

    /**
     * Mirrors `IntroController` nodes and state onto `Main` fields for external script inspection.
     *
     * @returns {Void}
     */
    function syncIntroFacade():Void {
        if (introController == null) return;
        introState = introController.state;
        introTimer = introController.timer;
        syncedIntroTimer = introTimer;
        introContainer = introController.introContainer;
        introBg = introController.introBg;
        screenStudio = introController.screenStudio;
        screenEngine = introController.screenEngine;
        screenDisclaimer = introController.screenDisclaimer;
        studioSplashBmp = introController.studioSplashBmp;
        engineSplashBmp = introController.engineSplashBmp;
        discHeader = introController.discHeader;
    }

    /**
     * Mirrors `WorldManager` active subsystems onto `Main` fields for external inspection.
     *
     * @returns {Void}
     */
    function syncWorldFacade():Void {
        if (world == null) return;
        currentMapMode = world.currentMapMode;
        track = world.track;
        sandboxMap = world.sandboxMap;
        traffic = world.traffic;
        playerMesh = world.playerMesh;
        carPhysics = world.carPhysics;
        chaseCam = world.chaseCam;
    }

    /**
     * Updates minimap coordinate bounds inside the in-game HUD to match the active map mode.
     *
     * @returns {Void}
     */
    function syncHUDMapBounds():Void {
        if (ui == null || ui.inGameHUD == null || world == null) return;
        if (world.currentMapMode == Circuit && world.track != null) {
            ui.inGameHUD.initWaypoints(world.track.waypoints);
        } else if (world.currentMapMode == Sandbox) {
            ui.inGameHUD.initSandboxBounds(SandboxMap.WALL_LIMIT);
        }
    }

    /**
     * Switches the active intro slide stage.
     *
     * @param {IntroState} target Intro stage to display.
     * @returns {Void}
     */
    @:keep public function setIntroScreen(target:IntroState):Void {
        if (introController != null) {
            introController.setScreen(target);
            syncIntroFacade();
        }
    }

    /**
     * Recalculates responsive layout for active boot screens.
     *
     * @returns {Void}
     */
    @:keep public function layoutIntro():Void {
        if (introController != null) {
            introController.layout();
        }
    }

    /**
     * Finalizes the intro sequence early, ensuring deferred systems exist before showing the Splash UI.
     *
     * @returns {Void}
     */
    @:keep public function finishIntroSequence():Void {
        ensureDeferredSystemsInitialized();
        if (introController != null) {
            introController.finishSequence();
        } else {
            activateMainSplash();
        }
    }

    /**
     * Switches active 3D environment geometry, physics colliders, and HUD minimap bounds.
     *
     * @param {MapMode} mode Target map (`Circuit` or `Sandbox`).
     * @returns {Void}
     */
    @:keep public function loadMap(mode:MapMode):Void {
        if (world == null) return;
        world.loadMap(mode);
        syncWorldFacade();
        syncHUDMapBounds();
        if (appState == IntroSequence) {
            if (engine != null) engine.backgroundColor = 0x000000;
            layoutIntro();
        }
    }

    /**
     * Repositions the player vehicle at the Sandbox center launch pad.
     *
     * @returns {Void}
     */
    @:keep public function resetCarToSandboxCenter():Void {
        if (world != null) world.resetCarToSandboxCenter();
    }

    /**
     * Repositions the player vehicle at the Highway Circuit starting grid line.
     *
     * @returns {Void}
     */
    @:keep public function resetCarToStartLine():Void {
        if (world != null) world.resetCarToStartLine();
    }

    /**
     * Persists active race vehicle coordinates, volumes, bindings, and graphics settings.
     *
     * @returns {Void}
     */
    @:keep public function saveCurrentRun():Void {
        if (multiplayer != null && multiplayer.status == InMatch) return;
        if (saveData == null || carPhysics == null || world == null) return;
        saveData.hasActiveRun = true;
        saveData.playerState = {
            posX: carPhysics.pos.x,
            posY: carPhysics.pos.y,
            posZ: carPhysics.pos.z,
            yaw: carPhysics.yaw,
            forwardSpeed: carPhysics.forwardSpeed,
            mapMode: (world.currentMapMode == Sandbox) ? "Sandbox" : "Circuit"
        };
        if (audio != null) {
            saveData.masterVol = audio.masterVolume;
            saveData.musicVol = audio.musicVolume;
            saveData.sfxVol = audio.sfxVolume;
        }
        input.exportToSave(saveData);
        if (ui != null) saveData.graphics = ui.gfxSettings;
        SaveSystem.save(saveData);
        if (ui != null) ui.setHasActiveSave(true);
    }

    /**
     * Saves the active session cleanly and presents the in-game pause menu.
     *
     * @returns {Void}
     */
    @:keep public function pauseActiveGame():Void {
        input.flushInputs();
        if (world != null) world.clearPostEffects();
        saveCurrentRun();
        if (ui != null) ui.showPause();
    }

    /**
     * Routes menu selections triggered across main menu, map select, and pause screens.
     *
     * @param {MenuAction} action Dispatched UI menu action.
     * @returns {Void}
     */
    @:keep public function handleMenuAction(action:MenuAction):Void {
        input.flushInputs();

        switch (action) {
            case OpenMapSelect:
                ui.showMapSelect();

            case OpenMultiplayer:
                ui.showMultiplayerMenu();

            case StartGame:
                if (multiplayer != null && multiplayer.role != None) multiplayer.leaveRoom();
                if (world != null) {
                    world.clearRemoteCars();
                    world.setTrafficEnabled(true);
                }
                ui.inGameHUD.remotePeerMarkers = [];
                loadMap(Circuit);
                resetCarToStartLine();
                if (traffic != null) traffic.resetPositions();
                raceTimer = 0.0;
                currentLap = 1;
                ui.showInGame();

            case StartSandbox:
                if (multiplayer != null && multiplayer.role != None) multiplayer.leaveRoom();
                if (world != null) {
                    world.clearRemoteCars();
                    world.setTrafficEnabled(true);
                }
                ui.inGameHUD.remotePeerMarkers = [];
                loadMap(Sandbox);
                resetCarToSandboxCenter();
                raceTimer = 0.0;
                currentLap = 1;
                ui.showInGame();

            case RestartRace:
                if (multiplayer != null && multiplayer.status == InMatch && multiplayer.localSpawnSlot != null) {
                    if (world != null) {
                        world.spawnPlayerAt(multiplayer.localSpawnSlot.x, multiplayer.localSpawnSlot.y, multiplayer.localSpawnSlot.z, multiplayer.localSpawnSlot.yaw);
                    }
                    ui.showInGame();
                    return;
                }
                if (world != null) {
                    world.reloadCurrentMap();
                    syncWorldFacade();
                    syncHUDMapBounds();
                }
                raceTimer = 0.0;
                currentLap = 1;
                ui.showInGame();

            case ResumeGame:
                if (multiplayer != null && multiplayer.role != None && multiplayer.status != InMatch) multiplayer.leaveRoom();
                if (multiplayer != null && multiplayer.status == InMatch) {
                    ui.showInGame();
                    return;
                }
                if (saveData != null && saveData.hasActiveRun && carPhysics != null) {
                    if (world != null) {
                        world.clearRemoteCars();
                        world.setTrafficEnabled(true);
                    }
                    ui.inGameHUD.remotePeerMarkers = [];
                    var targetMode = (saveData.playerState.mapMode == "Sandbox") ? Sandbox : Circuit;
                    loadMap(targetMode);
                    carPhysics.resetState(
                        saveData.playerState.posX,
                        saveData.playerState.posY,
                        saveData.playerState.posZ,
                        saveData.playerState.yaw
                    );
                    carPhysics.forwardSpeed = saveData.playerState.forwardSpeed;
                }
                ui.showInGame();

            case OpenOptions:
                ui.openOptions(false);

            case OpenCredits:
                ui.showCredits();

            case QuitToTitle:
                if (multiplayer != null && multiplayer.status == InMatch) {
                    if (multiplayer.role == Host) {
                        multiplayer.returnToLobby();
                    } else {
                        multiplayer.leaveRoom();
                        if (world != null) {
                            world.clearRemoteCars();
                            world.setTrafficEnabled(true);
                        }
                        ui.inGameHUD.remotePeerMarkers = [];
                        ui.showMainMenu();
                    }
                    return;
                }
                saveCurrentRun();
                ui.showMainMenu();
        }
    }

    /**
     * Propagates viewport resize events to graphics scaling and active boot or gameplay layouts.
     *
     * @returns {Void}
     */
    override function onResize() {
        super.onResize();

        if (gfx != null) {
            gfx.applyRenderScale();
            gfx.applyUIResolution();
        } else if (s2d != null) {
            s2d.checkResize();
        }

        if (appState == IntroSequence) {
            layoutIntro();
        } else {
            if (introController != null) introController.layout();
            if (ui != null) ui.layout();
        }
    }

    /**
     * Suspends or resumes game simulation, audio, and rendering in response to portrait orientation lock.
     * Automatically pauses an active drive so returning to landscape resumes cleanly from PauseMenu.
     *
     * @param {Bool} blocked True when a mobile/tablet viewport is in unsupported portrait orientation.
     * @returns {Void}
     */
    @:keep public function setOrientationPaused(blocked:Bool):Void {
        if (pausedByOrientation == blocked) return;
        pausedByOrientation = blocked;
        if (input != null) input.flushInputs();

        if (blocked) {
            if (systemsInitialized && ui != null && ui.currentState == InGameHUD) {
                pauseActiveGame();
            } else if (world != null) {
                world.clearPostEffects();
            }
            if (audio != null) audio.suspend();
        } else {
            if (audio != null) audio.resume();
            onResize();
        }
    }

    /**
     * Synchronizes orientation lock state from the HTML shell's `MOBOrientationGate` if present.
     *
     * @returns {Bool} True while portrait orientation blocks game execution.
     */
    function syncOrientationPauseFromHost():Bool {
        #if js
        var blocked:Bool = js.Syntax.code("Boolean(window.__mobPortraitBlocked)");
        if (blocked != pausedByOrientation) {
            setOrientationPaused(blocked);
        }
        #end
        return pausedByOrientation;
    }

    /**
     * Suppresses 3D world rendering while boot intro screens are active or orientation is blocked
     * so no gameplay frame ever flashes prematurely or during portrait lock.
     *
     * @param {Engine} e Active Heaps hardware engine.
     * @returns {Void}
     */
    override function render(e:Engine) {
        if (pausedByOrientation) {
            if (e != null) e.clear(0x000000, 1.0);
            return;
        }
        if (appState == IntroSequence) {
            if (e != null) e.clear(0x000000, 1.0);
            if (s2d != null) s2d.render(e);
            return;
        }
        super.render(e);
    }

    /**
     * Main per-frame update loop stepping input polling, boot progression, world showcase/driving,
     * and HUD telemetry.
     *
     * @param {Float} dt Elapsed frame time in seconds.
     * @returns {Void}
     */
    @:keep public override function update(dt:Float) {
        if (syncOrientationPauseFromHost()) {
            return;
        }

        input.update(dt);

        if (appState == IntroSequence) {
            if (introController != null) {
                if (introTimer != syncedIntroTimer) {
                    introController.timer = introTimer;
                }
                if (input.anyKeyPressed || input.uiConfirmPressed) {
                    introController.trySkip();
                }
                introController.update(dt);
                introTimer = introController.timer;
                syncedIntroTimer = introTimer;
            }
            return;
        }

        if (introController != null) {
            introController.updateShowcaseCurtain(dt, ui);
        }

        if (ui == null || world == null) return;

        var uiCancel = input.uiCancelPressed;
        if (!uiCancel && !ui.isOpenedFromPause && input.pausePressed
            && (ui.currentState == MapSelect || ui.currentState == MultiplayerMenu || ui.currentState == MultiplayerLobby || ui.currentState == CreditsScreen || ui.currentState == OptionsMenu)) {
            uiCancel = true;
        }
        if (multiplayer != null) {
            multiplayer.update(dt);
        }
        ui.update(dt, input.uiUpPressed, input.uiDownPressed, input.uiLeftPressed, input.uiRightPressed, input.uiConfirmPressed, uiCancel);
        world.syncSkybox();

        switch (ui.currentState) {
            case Splash | MainMenu | MapSelect | MultiplayerMenu | MultiplayerLobby | CreditsScreen:
                world.updateShowcaseCamera(dt);

            case PauseMenu | OptionsMenu:
                world.clearPostEffects();
                if ((ui.currentState == PauseMenu || ui.isOpenedFromPause) && input.pausePressed && !input.isListeningForRemap) {
                    input.flushInputs();
                    ui.showInGame();
                }

            case InGameHUD:
                if (input.pausePressed) {
                    pauseActiveGame();
                    return;
                }
                var kmh = world.updateDriving(dt, input);
                if (multiplayer != null && multiplayer.status == InMatch) {
                    multiplayer.updateInMatch(dt, world.carPhysics, input, world.getActiveGround());
                    world.syncRemoteCars(dt, multiplayer.remoteStates);
                    var markers:Array<{ x:Float, y:Float, colorHex:Int }> = [];
                    for (st in multiplayer.remoteStates) {
                        markers.push({ x: st.x, y: st.y, colorHex: st.colorHex });
                    }
                    ui.inGameHUD.remotePeerMarkers = markers;
                }
                raceTimer += dt;
                ui.inGameHUD.updateTelemetry(dt, world.carPhysics, kmh, world.carPhysics.isBoosting, raceTimer, currentLap, totalLaps);
        }
    }

    /** Returns the 2D UI scene instance. @returns {h2d.Scene} */
    public function getS2d():h2d.Scene return s2d;

    /** Returns the 3D world scene instance. @returns {h3d.scene.Scene} */
    public function getS3d():h3d.scene.Scene return s3d;

    /** Returns the underlying Heaps hardware engine. @returns {h3d.Engine} */
    public function getEngine():h3d.Engine return engine;

    static function main() {
        #if js
        var startApp = function() {
            if (js.Syntax.code("Boolean(window.__mobPortraitBlocked)")) {
                js.Browser.window.addEventListener("mob-orientation-unlocked", function(_) {
                    if (js.Syntax.code("!window.app && !window.__mobPortraitBlocked")) {
                        new Main();
                    }
                }, { once: true });
                return;
            }
            new Main();
        };
        var readyState:String = untyped js.Browser.document.readyState;
        if (readyState == "complete") {
            startApp();
        } else {
            js.Browser.window.addEventListener("load", function(_) startApp(), { once: true });
        }
        #else
        new Main();
        #end
    }
}
