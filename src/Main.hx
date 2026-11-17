package;

import graphics.SceneGraph;
import graphics.SceneGraph.EngineStub;
import graphics.SceneGraph.Scene3D;
import graphics.WebGpuRenderer;
import core.WebBridge;
import input.GamepadDevice;
import input.InputKey;
import haxe.Json;
import haxe.Timer;
import ui.nodes.UINodes.UIBitmap as Bitmap;
import ui.nodes.UINodes.UIScaleMode;
import ui.nodes.UINodes.UIObject as Object;
import ui.nodes.UINodes.UIText as Text;
import ui.nodes.UINodes.UIScene2D as Scene2D;
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
import physics.CarConfig;
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
class Main {
    public var s2d:Scene2D;
    public var s3d:Scene3D;
    public var engine:EngineStub;
    public var gpuRenderer:Null<WebGpuRenderer> = null;
    private var bridgeHudWaypointsSent:Bool = false;
    private var initialStorageApplied:Bool = false;

    public function new() {
        s2d = new Scene2D(VIRTUAL_BASE_WIDTH, VIRTUAL_BASE_HEIGHT);
        s3d = new Scene3D();
        engine = EngineStub.getCurrent();
    }

    public function attachGpuRenderer(renderer:WebGpuRenderer):Void {
        gpuRenderer = renderer;
        if (world != null) world.attachGpuRenderer(renderer);
        if (gfx != null) gfx.setWebGpuRenderer(renderer);
    }
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
    public function init():Void {
        config = GameConfig.getDefault();

        syncOrientationPauseFromHost();

        s2d.scaleMode = UIScaleMode.LetterBox(config.resolution.baseWidth, config.resolution.baseHeight, false);
        engine.backgroundColor = 0x000000;

        

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
        world.applyPlayerVehicle(saveData.selectedCarId, saveData.selectedPaintHex);
        if (gpuRenderer != null) world.attachGpuRenderer(gpuRenderer);

        gfx = new GraphicsManager(s3d, s2d, world.dirLight, saveData.graphics);
        if (gpuRenderer != null) gfx.setWebGpuRenderer(gpuRenderer);
        gfx.applyAll();

        multiplayer = new MultiplayerManager(new WebSocketTransport());

        ui = new UIManager(input, saveData.graphics, saveData.hasActiveRun, s2d, multiplayer);
        ui.visible = false;
        ui.preferredCarId = saveData.selectedCarId;
        ui.preferredPaintHex = saveData.selectedPaintHex;
        ui.onMenuAction = handleMenuAction;
        ui.onCarLaunch = function(mode:MapMode, carId:String, paintHex:Int) {
            launchSingleplayerWithVehicle(mode, carId, paintHex);
        };
        ui.onCarPreview = function(carId:String, paintHex:Int) {
            if (world != null) world.applyPlayerVehicle(carId, paintHex);
        };
        ui.onPauseRequested = pauseActiveGame;
        ui.builder.optionsView.gfxPanel.onSettingsChanged = function() {
            if (saveData != null && gfx != null) {
                ui.gfxSettings = gfx.settings;
                saveData.graphics = gfx.settings;
                SaveSystem.save(saveData);
            }
        };
        ui.builder.optionsView.audioPanel.onVolumeChanged = function() {
            if (saveData != null && audio != null) {
                saveData.masterVol = audio.masterVolume;
                saveData.musicVol = audio.musicVolume;
                saveData.sfxVol = audio.sfxVolume;
                SaveSystem.save(saveData);
            }
        };
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
        if (gfx != null) {
            saveData.graphics = gfx.settings;
            if (ui != null) ui.gfxSettings = gfx.settings;
        } else if (ui != null) {
            saveData.graphics = ui.gfxSettings;
        }
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

    function launchSingleplayerWithVehicle(mode:MapMode, carId:String, paintHex:Int):Void {
        if (multiplayer != null && multiplayer.role != None) multiplayer.leaveRoom();
        if (saveData != null) {
            saveData.selectedCarId = carId;
            saveData.selectedPaintHex = paintHex;
            SaveSystem.save(saveData);
        }
        if (world != null) {
            world.clearRemoteCars();
            world.applyPlayerVehicle(carId, paintHex);
            world.setTrafficEnabled(true);
        }
        ui.inGameHUD.remotePeerMarkers = [];
        loadMap(mode);
        if (mode == Sandbox) {
            resetCarToSandboxCenter();
        } else {
            resetCarToStartLine();
            if (traffic != null) traffic.resetPositions();
        }
        raceTimer = 0.0;
        currentLap = 1;
        ui.showInGame();
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
                if (ui != null && ui.currentState == MapSelect) {
                    ui.showCarSelect(Circuit, saveData != null ? saveData.selectedCarId : null, saveData != null ? saveData.selectedPaintHex : null);
                    return;
                }
                var cid = (saveData != null && saveData.selectedCarId != null) ? saveData.selectedCarId : CarConfig.ID_RACE_AWD;
                var chex = (saveData != null && saveData.selectedPaintHex != null) ? saveData.selectedPaintHex : CarConfig.getPresetMeta(cid).defaultColorHex;
                launchSingleplayerWithVehicle(Circuit, cid, chex);

            case StartSandbox:
                if (ui != null && ui.currentState == MapSelect) {
                    ui.showCarSelect(Sandbox, saveData != null ? saveData.selectedCarId : null, saveData != null ? saveData.selectedPaintHex : null);
                    return;
                }
                var sCid = (saveData != null && saveData.selectedCarId != null) ? saveData.selectedCarId : CarConfig.ID_RACE_AWD;
                var sChex = (saveData != null && saveData.selectedPaintHex != null) ? saveData.selectedPaintHex : CarConfig.getPresetMeta(sCid).defaultColorHex;
                launchSingleplayerWithVehicle(Sandbox, sCid, sChex);

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
                        world.applyPlayerVehicle(saveData.selectedCarId, saveData.selectedPaintHex);
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
                ui.openOptions(ui != null && ui.currentState == PauseMenu);

            case OpenCredits:
                ui.showCredits();

            case QuitToTitle:
                if (ui != null && ui.currentState == MainMenu) {
                    ui.showSplash();
                    return;
                }
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
    public function onResize() {
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
        var blocked = WebBridge.inst.isPortraitBlocked();
        if (blocked != pausedByOrientation) {
            setOrientationPaused(blocked);
        }
        return pausedByOrientation;
    }

    /**
     * Suppresses 3D world rendering while boot intro screens are active or orientation is blocked
     * so no gameplay frame ever flashes prematurely or during portrait lock.
     *
     * @param {Engine} e Active Heaps hardware engine.
     * @returns {Void}
     */
    public function renderFrame() {
        if (pausedByOrientation || appState == IntroSequence) {
            if (gpuRenderer != null && gpuRenderer.initialized) {
                gpuRenderer.renderBlackFrame();
            }
            return;
        }
        if (world != null) world.renderGpuFrame();
    }

    /**
     * Main per-frame update loop stepping input polling, boot progression, world showcase/driving,
     * and HUD telemetry.
     *
     * @param {Float} dt Elapsed frame time in seconds.
     * @returns {Void}
     */
    @:keep public function update(dt:Float):Void {
        processBridgeCommands();
        stepSimulation(dt);
        publishBridgeState();
    }

    private function stepSimulation(dt:Float):Void {
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
            && (ui.currentState == MapSelect || ui.currentState == CarSelect || ui.currentState == MultiplayerMenu || ui.currentState == MultiplayerLobby || ui.currentState == CreditsScreen || ui.currentState == OptionsMenu)) {
            uiCancel = true;
        }
        if (multiplayer != null) {
            multiplayer.update(dt);
        }
        ui.update(dt, input.uiUpPressed, input.uiDownPressed, input.uiLeftPressed, input.uiRightPressed, input.uiConfirmPressed, uiCancel);
        world.syncSkybox();

        switch (ui.currentState) {
            case Splash | MainMenu | MapSelect | CarSelect | MultiplayerMenu | MultiplayerLobby | CreditsScreen:
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
    public function getS2d():Scene2D return s2d;

    /** Returns the 3D world scene instance. @returns {h3d.scene.Scene} */
    public function getS3d():Scene3D return s3d;

    /** Returns the underlying Heaps hardware engine. @returns {h3d.Engine} */
    public function getEngine():EngineStub return engine;
    private function processBridgeCommands():Void {
        var cmds = WebBridge.inst.pollCommands();
        for (raw in cmds) {
            var ev:Dynamic = null;
            try {
                ev = Json.parse(raw);
            } catch (_:Dynamic) {
                continue;
            }
            if (ev == null) continue;
            var typ:String = ev.type;
            switch (typ) {
                case "save_load":
                    if (ev.key != null && ev.value != null) {
                        WebBridge.inst.localStorageCache.set(Std.string(ev.key), Std.string(ev.value));
                    }
                    if (!initialStorageApplied && ev.done == true) {
                        initialStorageApplied = true;
                        var reloaded = SaveSystem.load();
                        if (reloaded != null) {
                            saveData = reloaded;
                            if (input != null) input.loadFromSave(reloaded);
                            if (audio != null) {
                                audio.masterVolume = reloaded.masterVol;
                                audio.musicVolume = reloaded.musicVol;
                                audio.sfxVolume = reloaded.sfxVol;
                            }
                            if (gfx != null && reloaded.graphics != null) {
                                gfx.settings = reloaded.graphics;
                                gfx.applyAll();
                            }
                            if (ui != null) {
                                if (reloaded.graphics != null) ui.gfxSettings = reloaded.graphics;
                                ui.preferredCarId = reloaded.selectedCarId;
                                ui.preferredPaintHex = reloaded.selectedPaintHex;
                                if (world != null) world.applyPlayerVehicle(reloaded.selectedCarId, reloaded.selectedPaintHex);
                                ui.setHasActiveSave(reloaded.hasActiveRun);
                                if (ui.builder != null && ui.builder.optionsView != null) {
                                    if (reloaded.graphics != null) {
                                        ui.builder.optionsView.gfxPanel.settings = reloaded.graphics;
                                        ui.builder.optionsView.gfxPanel.updateStyles();
                                    }
                                    ui.builder.optionsView.audioPanel.updateStyles();
                                    ui.builder.optionsView.controlsPanel.updateSensitivityDisplay();
                                    ui.builder.optionsView.controlsPanel.updateControlHeaderButtons();
                                    ui.builder.optionsView.controlsPanel.updateRemapStyles();
                                }
                                ui.builder.touchControlsHUD.refreshSettings();
                            }
                        }
                    }
                case "browser_env":
                    if (ev.baseUrl != null) {
                        WebBridge.inst.localStorageCache.set("__mob_base_url", Std.string(ev.baseUrl));
                    }
                    if (ev.room != null && Std.string(ev.room) != "" && multiplayer != null) {
                        var roomCode = MultiplayerManager.extractRoomCode(Std.string(ev.room));
                        if (roomCode != "") {
                            ensureDeferredSystemsInitialized();
                            multiplayer.joinRoom(roomCode);
                        }
                    }
                case "key_state":
                    var code:Int = ev.code != null ? Std.int(ev.code) : 0;
                    var down:Bool = ev.down == true;
                    InputKey.setKeyState(code, down);
                case "pad_state":
                    var conn:Bool = ev.connected == true;
                    var axes:Array<Float> = ev.axes != null ? cast ev.axes : [];
                    var btns:Array<Bool> = ev.buttons != null ? cast ev.buttons : [];
                    var vals:Array<Float> = ev.values != null ? cast ev.values : [];
                    GamepadDevice.applyExternalSnapshot(conn, axes, btns, vals);
                case "net_ev":
                    WebSocketTransport.dispatchBridgeEvent(ev);
                case "ui_cmd":
                    handleDomUiCommand(ev);
                case "e2e_cmd":
                    handleE2eCommand(ev);
                default:
            }
        }
    }

    private function handleDomUiCommand(ev:Dynamic):Void {
        ensureDeferredSystemsInitialized();
        var cmd:String = ev.cmd != null ? Std.string(ev.cmd) : "";
        switch (cmd) {
            case "skip_intro":
                if (appState == IntroSequence && introController != null) {
                    introController.trySkip();
                }
            case "splash_continue":
                if (ui != null && ui.currentState == Splash) {
                    ui.showMainMenu();
                }
            case "menu_select":
                if (ui != null) {
                    var idx:Int = ev.index != null ? Std.int(ev.index) : 0;
                    switch (ui.currentState) {
                        case MainMenu:
                            var mv = ui.builder.mainMenuView;
                            if (mv != null) {
                                mv.selectedIndex = idx;
                                mv.updateStyles();
                            }
                        case MapSelect:
                            var ms = ui.builder.mapSelectView;
                            if (ms != null) {
                                ms.selectedIndex = idx;
                                ms.updateStyles();
                            }
                        case PauseMenu:
                            var pv = ui.builder.pauseMenuView;
                            if (pv != null) {
                                pv.selectedIndex = idx;
                                pv.updateStyles();
                            }
                        default:
                    }
                }
            case "action":
                var name:String = ev.action != null ? Std.string(ev.action) : "";
                switch (name) {
                    case "StartGame": handleMenuAction(StartGame);
                    case "OpenMapSelect": handleMenuAction(OpenMapSelect);
                    case "OpenMultiplayer": handleMenuAction(OpenMultiplayer);
                    case "StartSandbox": handleMenuAction(StartSandbox);
                    case "RestartRace": handleMenuAction(RestartRace);
                    case "ResumeGame": handleMenuAction(ResumeGame);
                    case "OpenOptions": handleMenuAction(OpenOptions);
                    case "OpenOptionsBackPause": if (ui != null) ui.showPause();
                    case "OpenCredits": handleMenuAction(OpenCredits);
                    case "QuitToTitle": handleMenuAction(QuitToTitle);
                    case "PauseGame": pauseActiveGame();
                    default:
                }
            case "ui_back":
                if (ui != null) {
                    switch (ui.currentState) {
                        case MapSelect | MultiplayerMenu | CreditsScreen:
                            ui.showMainMenu();
                        case CarSelect:
                            ui.showMapSelect();
                        case MultiplayerLobby:
                            if (multiplayer != null) multiplayer.leaveRoom();
                            ui.showMultiplayerMenu();
                        case OptionsMenu:
                            if (ui.isOpenedFromPause) ui.showPause() else ui.showMainMenu();
                        case PauseMenu:
                            handleMenuAction(ResumeGame);
                        default:
                    }
                }
            case "car_select_pick":
                if (ui != null && ui.builder.carSelectView != null) {
                    var cIdx:Int = ev.idx != null ? Std.int(ev.idx) : 0;
                    ui.builder.carSelectView.selectCar(cIdx);
                    if (ev.launch == true) ui.builder.carSelectView.confirmSelection();
                }
            case "car_select_color":
                if (ui != null && ui.builder.carSelectView != null) {
                    var swIdx:Int = ev.idx != null ? Std.int(ev.idx) : 0;
                    ui.builder.carSelectView.selectColor(swIdx);
                }
            case "car_select_launch":
                if (ui != null && ui.builder.carSelectView != null) {
                    ui.builder.carSelectView.confirmSelection();
                }
            case "options_tab":
                if (ui != null && ui.builder.optionsView != null) {
                    var tabName:String = ev.tab != null ? Std.string(ev.tab) : "Graphics";
                    var opt = ui.builder.optionsView;
                    switch (tabName) {
                        case "Graphics": opt.switchTab(Graphics);
                        case "Audio": opt.switchTab(Audio);
                        case "Keyboard": opt.switchTab(Keyboard);
                        case "Gamepad": opt.switchTab(Gamepad);
                        case "Touch": opt.switchTab(Touch);
                        default:
                    }
                }
            case "options_step":
                if (ui != null && ui.builder.optionsView != null) {
                    var opt = ui.builder.optionsView;
                    var rowIdx:Int = ev.row != null ? Std.int(ev.row) : 0;
                    var dir:Int = ev.dir != null ? Std.int(ev.dir) : 1;
                    switch (opt.currentTab) {
                        case Graphics:
                            opt.gfxPanel.selectedIndex = rowIdx;
                            opt.gfxPanel.cycleOption(rowIdx, dir);
                        case Audio:
                            opt.audioPanel.selectedIndex = rowIdx;
                            opt.audioPanel.adjustVolume(rowIdx, dir * 0.1);
                        case Keyboard | Gamepad | Touch:
                            opt.controlsPanel.remapIndex = rowIdx;
                            if (opt.currentTab == Touch) {
                                if (rowIdx == 11) {
                                    opt.controlsPanel.resetTouchDefaults();
                                } else if (dir != 0) {
                                    opt.controlsPanel.cycleCustomTouchRow(rowIdx, dir);
                                }
                            } else if (dir == 0) {
                                opt.controlsPanel.controlViewMode = "Custom";
                                opt.controlsPanel.triggerRemapEntry(rowIdx);
                            } else {
                                opt.controlsPanel.adjustSensitivity(dir);
                            }
                    }
                }
            case "controls_sensitivity":
                if (ui != null && ui.builder.optionsView != null) {
                    var dir:Int = ev.dir != null ? Std.int(ev.dir) : 1;
                    ui.builder.optionsView.controlsPanel.adjustSensitivity(dir);
                }
            case "controls_remap":
                if (ui != null && ui.builder.optionsView != null) {
                    var rowIdx:Int = ev.row != null ? Std.int(ev.row) : 0;
                    var cp = ui.builder.optionsView.controlsPanel;
                    cp.controlViewMode = "Custom";
                    cp.remapIndex = rowIdx;
                    cp.triggerRemapEntry(rowIdx);
                }
            case "touch_toggle_custom":
                if (ui != null && ui.builder.optionsView != null) {
                    ui.builder.optionsView.controlsPanel.toggleCustomMode();
                }
            case "touch_set_offset":
                if (ui != null && ui.builder.optionsView != null) {
                    var part:String = ev.part != null ? Std.string(ev.part) : "";
                    var ox:Float = ev.x != null ? ev.x : 0.0;
                    var oy:Float = ev.y != null ? ev.y : 0.0;
                    ui.builder.optionsView.controlsPanel.setTouchControlOffset(part, ox, oy);
                }
            case "touch_reset_defaults":
                if (ui != null && ui.builder.optionsView != null) {
                    ui.builder.optionsView.controlsPanel.resetTouchDefaults();
                }
            case "controls_toggle_device":
                if (ui != null && ui.builder.optionsView != null) {
                    ui.builder.optionsView.controlsPanel.toggleExclusiveDevice();
                }
            case "mp_host":
                if (multiplayer != null && ui != null) {
                    var mapIdx:Int = ev.mapIndex != null ? Std.int(ev.mapIndex) : 0;
                    multiplayer.hostRoom();
                    multiplayer.setSelectedMap((mapIdx == 1) ? Sandbox : Circuit);
                    ui.showMultiplayerLobby();
                }
            case "mp_set_code":
                if (ui != null && ui.builder.multiplayerMenuView != null && ev.code != null) {
                    ui.builder.multiplayerMenuView.setInviteCode(Std.string(ev.code));
                }
            case "mp_join":
                if (multiplayer != null && ui != null) {
                    var rawCode:String = ev.code != null ? Std.string(ev.code) : "";
                    var extracted = MultiplayerManager.extractRoomCode(rawCode);
                    if (extracted != "") {
                        multiplayer.joinRoom(extracted);
                        ui.showMultiplayerLobby();
                    }
                }
            case "mp_select_map":
                if (multiplayer != null) {
                    var mode = Std.string(ev.map) == "Sandbox" ? Sandbox : Circuit;
                    multiplayer.setSelectedMap(mode);
                }
            case "mp_copy_invite":
                if (multiplayer != null) {
                    MultiplayerManager.copyInviteLinkToClipboard(multiplayer.getInviteLink());
                }
            case "mp_start_match":
                if (multiplayer != null) {
                    multiplayer.startMatch();
                }
            case "mp_leave":
                if (multiplayer != null && ui != null) {
                    multiplayer.leaveRoom();
                    ui.showMultiplayerMenu();
                }
            default:
        }
    }

    private function handleE2eCommand(ev:Dynamic):Void {
        ensureDeferredSystemsInitialized();
        var cmd:String = ev.cmd != null ? Std.string(ev.cmd) : "";
        switch (cmd) {
            case "load_map":
                var m = Std.string(ev.map) == "Sandbox" ? Sandbox : Circuit;
                loadMap(m);
            case "set_touch_enabled":
                var on:Bool = ev.enabled == true;
                if (input != null) input.isTouchActive = on;
                if (ui != null && ui.builder.touchControlsHUD != null) {
                    ui.builder.touchControlsHUD.visible = on;
                }
            case "pause_game":
                pauseActiveGame();
            case "reset_car":
                if (currentMapMode == Sandbox) resetCarToSandboxCenter() else resetCarToStartLine();
            default:
        }
    }

    private function publishBridgeState():Void {
        var speedKmh = carPhysics != null ? Math.abs(carPhysics.forwardSpeed) * 3.6 : 0.0;
        var maxRpm = (carPhysics != null && carPhysics.config != null && carPhysics.config.drivetrain != null) ? carPhysics.config.drivetrain.redlineRPM : 7600.0;
        var rpmNorm = carPhysics != null ? Math.max(0.0, Math.min(1.0, carPhysics.engineRPM / maxRpm)) : 0.0;
        var gear = carPhysics != null ? carPhysics.currentGear : 1;
        var boost = carPhysics != null ? carPhysics.boostFuel : 1.0;
        var cx = carPhysics != null ? carPhysics.pos.x : 0.0;
        var cy = carPhysics != null ? carPhysics.pos.y : 0.0;
        var cyaw = carPhysics != null ? carPhysics.yaw : 0.0;
        var lapProg = 0.0;
        var lapCnt = 0;
        if (world != null && world.track != null && currentMapMode == Circuit) {
            lapProg = 0.0;
        }
        var inMenu = (appState == IntroSequence) || (ui != null && ui.currentState != InGameHUD);
        WebBridge.inst.writeTelemetry(
            speedKmh,
            rpmNorm,
            gear,
            boost,
            lapProg,
            lapCnt,
            0.0,
            cx,
            cy,
            cyaw,
            input != null ? input.steer : 0.0,
            engine != null ? engine.fps : 60.0,
            inMenu
        );

        var uiStateName = ui != null ? Std.string(ui.currentState) : "Splash";
        var appStateName = appState == IntroSequence ? "IntroSequence" : "InGameUI";
        var introStateName = Std.string(introState);
        var mapName = currentMapMode == Sandbox ? "Sandbox" : "Circuit";

        var mpData:Dynamic = null;
        if (multiplayer != null) {
            mpData = {
                role: Std.string(multiplayer.role),
                status: Std.string(multiplayer.status),
                roomId: multiplayer.roomId,
                inviteLink: multiplayer.getInviteLink(),
                selectedMap: multiplayer.selectedMap == Sandbox ? "Sandbox" : "Circuit",
                peers: [for (p in multiplayer.peers) { id: p.peerId, name: p.name, slot: p.slotIndex, color: p.colorHex, ready: p.ready, isHost: p.isHost }],
                enteredCode: (ui != null && ui.builder.multiplayerMenuView != null) ? ui.builder.multiplayerMenuView.enteredCode : "",
                menuIdx: (ui != null && ui.builder.multiplayerMenuView != null) ? ui.builder.multiplayerMenuView.selectedIndex : 0,
                lobbyFocusIdx: (ui != null && ui.builder.multiplayerLobbyView != null) ? ui.builder.multiplayerLobbyView.focusedActionIdx : 0
            };
        }

        var optData:Dynamic = null;
        if (ui != null && ui.builder.optionsView != null) {
            var ov = ui.builder.optionsView;
            var gp = ov.gfxPanel;
            var ap = ov.audioPanel;
            var cp = ov.controlsPanel;
            var gfxDisabled:Array<Bool> = [for (i in 0...14) gp.isOptionDisabled(i)];
            var gfxLocked:Array<Bool> = [for (i in 0...14) (ui.isOpenedFromPause && gp.isOptionMenuOnly(i))];
            optData = {
                tab: Std.string(ov.currentTab),
                gfxIdx: gp.selectedIndex,
                gfxDisabled: gfxDisabled,
                gfxLocked: gfxLocked,
                gfx: {
                    textures: gp.settings.textures,
                    shadowLevel: gp.settings.shadowLevel,
                    shadowRes: gp.settings.shadowRes,
                    lightingLevel: gp.settings.lightingLevel,
                    lightingRes: gp.settings.lightingRes,
                    mipmapping: gp.settings.mipmapping,
                    anisotropic: gp.settings.anisotropic,
                    aaType: gp.settings.aaType,
                    aaLevel: gp.settings.aaLevel,
                    modelGeometry: gp.settings.modelGeometry,
                    modelReflections: gp.settings.modelReflections,
                    reflectionLevel: gp.settings.reflectionLevel,
                    renderScale: gp.settings.renderScale,
                    uiResolution: gp.settings.uiResolution
                },
                audioIdx: ap.selectedIndex,
                audio: {
                    master: AudioManager.inst != null ? AudioManager.inst.masterVolume : 0.8,
                    music: AudioManager.inst != null ? AudioManager.inst.musicVolume : 0.7,
                    sfx: AudioManager.inst != null ? AudioManager.inst.sfxVolume : 0.9
                },
                ctrlIdx: cp.remapIndex,
                ctrlViewMode: cp.controlViewMode,
                device: input != null ? Std.string(input.exclusiveDevice) : "Both",
                steerSens: input != null ? input.steerSensitivity : 0.8,
                listening: input != null ? input.isListeningForRemap : false,
                listeningAction: (input != null && input.isListeningForRemap && input.listeningAction != null) ? Std.string(input.listeningAction) : null,
                gamepadConnected: input != null ? input.isPadConnected() : false,
                bindings: input != null ? {
                    throttle: InputController.getKeyName(input.bindings.keyGas),
                    brake: InputController.getKeyName(input.bindings.keyBrake),
                    steerLeft: InputController.getKeyName(input.bindings.keyLeft),
                    steerRight: InputController.getKeyName(input.bindings.keyRight),
                    handbrake: InputController.getKeyName(input.bindings.keyHandbrake),
                    boost: InputController.getKeyName(input.bindings.keyBoost),
                    padThrottle: InputController.getGamepadBtnName(input.bindings.padGas),
                    padBrake: InputController.getGamepadBtnName(input.bindings.padBrake),
                    padHandbrake: InputController.getGamepadBtnName(input.bindings.padHandbrake),
                    padBoost: InputController.getGamepadBtnName(input.bindings.padBoost)
                } : null
            };
        }

        var touchCfg = saveData != null && saveData.touchSettings != null ? saveData.touchSettings : SaveSystem.getDefaultTouchSettings();
        var storageHydrated = WebBridge.inst.mailbox.getInt32(WebBridge.OFF_STORAGE_READY) != 0;
        var minimapPts:Array<Array<Float>> = null;
        if (!bridgeHudWaypointsSent && world != null && world.track != null && world.track.waypoints.length > 0) {
            var wps = world.track.waypoints;
            var step = wps.length > 72 ? Std.int(wps.length / 72) : 1;
            minimapPts = [];
            var i = 0;
            while (i < wps.length) {
                minimapPts.push([Math.round(wps[i].x * 10) / 10, Math.round(wps[i].y * 10) / 10]);
                i += step;
            }
            if (storageHydrated) {
                bridgeHudWaypointsSent = true;
            }
        }

        var carSelectData:Dynamic = null;
        if (ui != null && ui.currentState == CarSelect && ui.builder.carSelectView != null) {
            var csv = ui.builder.carSelectView;
            var carList = [for (m in CarConfig.VEHICLE_PRESETS) {
                id: m.id,
                name: m.name,
                drivetrain: m.drivetrain,
                tag: m.tag,
                desc: m.desc,
                topSpeedKmh: m.topSpeedKmh,
                turnRadiusM: m.turnRadiusM,
                weightKg: m.weightKg
            }];
            var colorList = [for (c in CarConfig.PAINT_PALETTE) {
                name: c.name,
                cssHex: c.cssHex,
                hex: c.hex
            }];
            carSelectData = {
                mapMode: csv.targetMap == Sandbox ? "Sandbox" : "Circuit",
                carIdx: csv.selectedCarIndex,
                carId: csv.getSelectedCarId(),
                colorIdx: csv.selectedColorIndex,
                colorHex: csv.getSelectedColorHex(),
                focusRow: csv.focusRow,
                cars: carList,
                colors: colorList
            };
        }

        var alphaRounded = introController != null ? (Math.round(introController.alpha * 50.0) / 50.0) : 0.0;
        var showcaseAlpha = (introController != null && introController.isShowcaseFadingIn && introController.showcaseCurtain != null)
            ? (Math.round(introController.showcaseCurtain.alpha * 50.0) / 50.0) : 0.0;
        var payload:Dynamic = {
            version: Version.DISPLAY,
            appState: appStateName,
            introState: introStateName,
            introAlpha: alphaRounded,
            introShowcaseFading: introController != null ? introController.isShowcaseFadingIn : false,
            showcaseAlpha: showcaseAlpha,
            uiState: uiStateName,
            mapMode: mapName,
            pausedByOrientation: pausedByOrientation,
            hasSavedRun: ui != null ? ui.hasActiveSave : false,
            isOpenedFromPause: ui != null ? ui.isOpenedFromPause : false,
            touchEnabled: input != null ? input.isTouchActive : false,
            touchSettings: touchCfg,
            mainMenuIdx: (ui != null && ui.builder.mainMenuView != null) ? ui.builder.mainMenuView.selectedIndex : 0,
            mapIdx: (ui != null && ui.builder.mapSelectView != null) ? ui.builder.mapSelectView.selectedIndex : 0,
            pauseIdx: (ui != null && ui.builder.pauseMenuView != null) ? ui.builder.pauseMenuView.selectedIndex : 0,
            selectedCarId: world != null ? world.selectedCarId : CarConfig.ID_RACE_AWD,
            selectedPaintHex: world != null ? world.selectedPaintHex : 0xE64A19,
            carSelect: carSelectData,
            mp: mpData,
            options: optData,
            minimap: minimapPts
        };
        WebBridge.inst.publishState(payload);
    }

    static function main() {
        var renderer = new WebGpuRenderer();
        var gpuOk = renderer.initAsync(VIRTUAL_BASE_WIDTH, VIRTUAL_BASE_HEIGHT, "M.O.B. // Motors on Boost");
        trace("[MOB] WebGpuRenderer.initAsync => " + gpuOk);

        var app = new Main();
        if (gpuOk) {
            app.attachGpuRenderer(renderer);
        }
        app.init();
        app.publishBridgeState();
        trace("[MOB] Main.init complete, entering frame loop");

        if (!gpuOk || !renderer.win.valid()) {
            trace("WebGpuRenderer failed to open window/GPU device.");
            return;
        }

        renderer.win.requestRedraw();
        var lastStamp = Timer.stamp();
        var drewThisTick = false;
        var running = true;

        inline function tickFrame(renderGpu:Bool):Void {
            var now = Timer.stamp();
            var dt = now - lastStamp;
            lastStamp = now;
            if (dt < 0.001) dt = 0.001;
            if (dt > 0.05) dt = 0.05;
            if (dt > 0) app.engine.fps = 1.0 / dt;
            GamepadDevice.pollAll(false);
            app.update(dt);
            if (renderGpu) app.renderFrame();
            drewThisTick = true;
        }

        inline function handleWindowEvent(ev:window.Event):Void {
            switch (ev) {
                case Closed | Destroyed:
                    running = false;
                case Resized(w, h):
                    var wi = haxe.Int64.toInt(w);
                    var hi = haxe.Int64.toInt(h);
                    renderer.resize(wi, hi);
                    app.engine.resize(wi, hi);
                    app.onResize();
                case KeyboardInput(_, keyEv, _):
                    switch (keyEv) {
                        case Input(physKey, _, _, _, state, _, _):
                            switch (physKey) {
                                case Code(kc):
                                    var mapped = InputKey.fromWindowKeyCode(kc);
                                    if (mapped != 0) {
                                        InputKey.setKeyState(mapped, state == window.MouseElementState.Pressed);
                                    }
                                default:
                            }
                    }
                case MouseInput(state, button, _):
                    if (button == window.MouseButton.Left) {
                        InputKey.setKeyState(InputKey.MOUSE_LEFT, state == window.MouseElementState.Pressed);
                    }
                case RedrawRequested:
                    renderer.win.requestRedraw();
                    tickFrame(true);
                default:
            }
        }

        while (running) {
            drewThisTick = false;
            var ev = renderer.win.wait(0.05);
            handleWindowEvent(ev);
            while (running) {
                var nextEv = renderer.win.poll();
                if (nextEv == window.Event.None) break;
                handleWindowEvent(nextEv);
            }
            // Fallback tick if rAF/RedrawRequested is throttled in headless or background tabs
            if (!drewThisTick && (Timer.stamp() - lastStamp) >= 0.04) {
                tickFrame(false);
                renderer.win.requestRedraw();
            }
        }

        renderer.dispose();
    }
}