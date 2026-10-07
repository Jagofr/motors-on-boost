package core;

import h2d.Object;
import h2d.Text;
import h2d.Graphics;
import h2d.Bitmap;
import h2d.Tile;
import h2d.Interactive;

import input.InputController;
import core.SaveSystem;
import core.SaveSystem.GraphicsSettings;

enum MenuAction {
    StartGame;
    ResumeGame;
    OpenOptions;
    OpenCredits;
    QuitToTitle;
}

enum UIState {
    Splash;
    MainMenu;
    InGameHUD;
    PauseMenu;
    OptionsMenu;
    CreditsScreen;
}

enum OptionsTab {
    Graphics;
    Audio;
    Keyboard;
    Gamepad;
}

class UIManager extends Object {
    public var currentState:UIState = Splash;
    public var isOpenedFromPause:Bool = false;

    var splashContainer:Object;
    var mainMenuContainer:Object;
    var pauseContainer:Object;
    var optionsContainer:Object;
    var creditsContainer:Object;

    var modalDimmer:Bitmap;
    var cardBg:Graphics;

    // Splash
    var splashTitle:Text;
    var splashPrompt:Text;
    var promptBlinkTimer:Float = 0.0;
    var splashInputCooldown:Float = 0.0;

    // Main Menu
    var mainTitle:Text;
    var mainMenuButtons:Array<Text> = [];
    var mainMenuIcons:Array<Bitmap> = [];
    var mainMenuInteractives:Array<Interactive> = [];
    var mainSelectedIndex:Int = 0;
    var hasActiveSave:Bool = false;

    // Pause Menu
    var pauseTitle:Text;
    var pauseButtons:Array<Text> = [];
    var pauseIcons:Array<Bitmap> = [];
    var pauseInteractives:Array<Interactive> = [];
    var pauseSelectedIndex:Int = 0;

    // Options
    var optionsTitle:Text;
    var tabLabels:Array<Text> = [];
    var tabIcons:Array<Bitmap> = [];
    var tabInteractives:Array<Interactive> = [];
    var currentTab:OptionsTab = Graphics;
    static var TAB_ORDER:Array<OptionsTab> = [Graphics, Audio, Keyboard, Gamepad];

    // Audio Subpanel
    var audioContainer:Object;
    var audioItems:Array<Text> = [];
    var audioIcons:Array<Bitmap> = [];
    var audioInteractives:Array<Interactive> = [];
    var audioIndex:Int = 0;

    // Graphics Subpanel
    var graphicsContainer:Object;
    var graphicsItems:Array<Text> = [];
    var graphicsInteractives:Array<Interactive> = [];
    var graphicsIndex:Int = 0;

    // Controls Subpanel
    var controlsContainer:Object;
    var diagramViewer:ControlDiagrams;
    var remapContainer:Object;
    var remapItems:Array<Text> = [];
    var remapInteractives:Array<Interactive> = [];
    var remapIndex:Int = 0;
    var toggleExclusiveBtn:Text;
    var toggleExclusiveInter:Interactive;
    var toggleViewModeBtn:Text;
    var toggleViewModeInter:Interactive;
    var remapStatusNotice:Text;
    var controlViewMode:String = "Diagram";

    // Credits Screen
    var creditsTitle:Text;
    var creditsLeadTitle:Text;
    var creditsLeadName:Text;
    var creditsPubTitle:Text;
    var creditsPubName:Text;
    var creditsAiTitle:Text;
    var creditsAiName:Text;
    var creditsTechDetails:Text;
    var creditsDevBadge:Bitmap;
    var creditsBackBtn:Text;
    var creditsBackInter:Interactive;

    var helpText:Text;

    public var onMenuAction:MenuAction->Void;
    var inputRef:InputController;
    public var gfxSettings:GraphicsSettings;

    public function new(input:InputController, initialGfx:GraphicsSettings, hasSave:Bool, ?parent:Object) {
        super(parent);
        this.visible = false; // Stay hidden until finishIntroSequence() triggers
        this.inputRef = input;
        this.gfxSettings = initialGfx;
        this.hasActiveSave = hasSave;

        modalDimmer = new Bitmap(Tile.fromColor(0x000000, 1, 1, 0.78), this);
        cardBg = new Graphics(this);

        buildSplashScreen();
        buildMainMenu();
        buildPauseMenu();
        buildOptionsMenu();
        buildCreditsScreen();

        helpText = new Text(FontManager.regularFont, this);
        helpText.textColor = 0x8FA1B3;
    }

    public function setHasActiveSave(val:Bool) {
        hasActiveSave = val;
        updateMainMenuStyles();
    }

    function buildSplashScreen() {
        splashContainer = new Object(this);

        splashTitle = new Text(FontManager.heroFont, splashContainer);
        splashTitle.text = "M.O.B. // MOTORS ON BOOST";
        splashTitle.textColor = 0xFF9800;

        splashPrompt = new Text(FontManager.titleFont, splashContainer);
        splashPrompt.text = "PRESS ANY BUTTON OR CLICK TO ENTER";
        splashPrompt.textColor = 0xFFFFFF;

        var hit = new Interactive(3000, 3000, splashContainer);
        hit.onClick = function(_) {
            if (currentState == Splash && splashInputCooldown <= 0.0) showMainMenu();
        };
    }

    function buildMainMenu() {
        mainMenuContainer = new Object(this);

        mainTitle = new Text(FontManager.heroFont, mainMenuContainer);
        mainTitle.text = "MAIN MENU";
        mainTitle.textColor = 0x00E5FF;

        var labels = ["START NEW RACE", "RESUME SAVED RACE", "OPTIONS", "CREDITS", "EXIT TO SPLASH"];
        var iconTypes = [
            core.UIIcons.IconType.Play,
            core.UIIcons.IconType.Resume,
            core.UIIcons.IconType.Settings,
            core.UIIcons.IconType.Credits,
            core.UIIcons.IconType.Exit
        ];
        var actions = [MenuAction.StartGame, MenuAction.ResumeGame, MenuAction.OpenOptions, MenuAction.OpenCredits, MenuAction.QuitToTitle];

        for (i in 0...labels.length) {
            var row = new Object(mainMenuContainer);

            var iconBmp = new Bitmap(core.UIIcons.get(iconTypes[i], 24, 0x00E5FF), row);
            mainMenuIcons.push(iconBmp);

            var labelTxt = new Text(FontManager.regularFont, row);
            labelTxt.text = labels[i];
            mainMenuButtons.push(labelTxt);

            var inter = new Interactive(440, 44, mainMenuContainer);
            inter.onOver = function(_) {
                if (currentState == MainMenu) {
                    mainSelectedIndex = i;
                    updateMainMenuStyles();
                }
            };
            inter.onClick = function(_) {
                if (currentState == MainMenu) {
                    if (i == 1 && !hasActiveSave) return;
                    AudioManager.inst.playMenuBeep(520, 0.08);
                    triggerMainAction(actions[i]);
                }
            };
            mainMenuInteractives.push(inter);
        }
    }

    function buildPauseMenu() {
        pauseContainer = new Object(this);

        pauseTitle = new Text(FontManager.heroFont, pauseContainer);
        pauseTitle.text = "PAUSED";
        pauseTitle.textColor = 0xFFEE00;

        var labels = ["RESUME RACE", "RESTART RACE", "OPTIONS", "MAIN MENU"];
        var pauseIconTypes = [
            core.UIIcons.IconType.Resume,
            core.UIIcons.IconType.Restart,
            core.UIIcons.IconType.Settings,
            core.UIIcons.IconType.Exit
        ];

        for (i in 0...labels.length) {
            var row = new Object(pauseContainer);

            var iconBmp = new Bitmap(core.UIIcons.get(pauseIconTypes[i], 24, 0xFFEE00), row);
            pauseIcons.push(iconBmp);

            var labelTxt = new Text(FontManager.regularFont, row);
            labelTxt.text = labels[i];
            pauseButtons.push(labelTxt);

            var inter = new Interactive(380, 44, pauseContainer);
            inter.onOver = function(_) {
                if (currentState == PauseMenu) {
                    pauseSelectedIndex = i;
                    updatePauseStyles();
                }
            };
            inter.onClick = function(_) {
                if (currentState == PauseMenu) {
                    AudioManager.inst.playMenuBeep(520, 0.08);
                    switch (i) {
                        case 0: if (onMenuAction != null) onMenuAction(ResumeGame);
                        case 1: if (onMenuAction != null) onMenuAction(StartGame);
                        case 2: openOptions(true);
                        case 3: if (onMenuAction != null) onMenuAction(QuitToTitle);
                    }
                }
            };
            pauseInteractives.push(inter);
        }
    }

    function buildOptionsMenu() {
        optionsContainer = new Object(this);

        optionsTitle = new Text(FontManager.titleFont, optionsContainer);
        optionsTitle.text = "CONFIGURATION & HARDWARE";
        optionsTitle.textColor = 0x00E5FF;

        var tabNames = ["GRAPHICS", "AUDIO", "KEYBOARD", "GAMEPAD"];
        var tabIconTypes = [
            core.UIIcons.IconType.Graphics,
            core.UIIcons.IconType.Volume,
            core.UIIcons.IconType.Keyboard,
            core.UIIcons.IconType.Gamepad
        ];

        for (i in 0...tabNames.length) {
            var tIcon = new Bitmap(core.UIIcons.get(tabIconTypes[i], 22, 0x00E5FF), optionsContainer);
            tabIcons.push(tIcon);

            var tTxt = new Text(FontManager.regularFont, optionsContainer);
            tTxt.text = tabNames[i];
            tabLabels.push(tTxt);

            var tabInter = new Interactive(150, 42, optionsContainer);
            tabInter.onClick = function(_) switchTab(TAB_ORDER[i]);
            tabInteractives.push(tabInter);
        }

        buildGraphicsPanel();
        buildAudioPanel();
        buildControlsPanel();
    }

    function buildGraphicsPanel() {
        graphicsContainer = new Object(optionsContainer);

        var names = [
            "Textures", "Shadow Level", "Shadow Res", "Lighting", "Lighting Res",
            "Mipmapping", "Anisotropy", "Anti-Aliasing", "AA Level", "Model Geometry",
            "Reflections", "Reflection Level", "Render Scale"
        ];

        for (i in 0...names.length) {
            var txt = new Text(FontManager.regularFont, graphicsContainer);
            graphicsItems.push(txt);

            var inter = new Interactive(560, 28, graphicsContainer);
            inter.onOver = function(_) {
                if (currentState == OptionsMenu && currentTab == Graphics) {
                    graphicsIndex = i;
                    updateGraphicsStyles();
                }
            };
            inter.onClick = function(_) cycleGraphicsOption(i, 1);
            graphicsInteractives.push(inter);
        }
    }

    function buildAudioPanel() {
        audioContainer = new Object(optionsContainer);
        var optLabels = ["Master Volume", "Music Track", "Sound Effects (SFX)"];
        var audioIconTypes = [
            core.UIIcons.IconType.Volume,
            core.UIIcons.IconType.Music,
            core.UIIcons.IconType.Sfx
        ];

        for (i in 0...optLabels.length) {
            var row = new Object(audioContainer);

            var iconBmp = new Bitmap(core.UIIcons.get(audioIconTypes[i], 28, 0x00E5FF), row);
            audioIcons.push(iconBmp);

            var txt = new Text(FontManager.regularFont, row);
            audioItems.push(txt);

            var inter = new Interactive(560, 48, audioContainer);
            inter.onOver = function(_) {
                audioIndex = i;
                updateAudioStyles();
            };
            inter.onClick = function(_) adjustVolume(i, 0.1);
            audioInteractives.push(inter);
        }
    }

    function buildControlsPanel() {
        controlsContainer = new Object(optionsContainer);

        toggleExclusiveBtn = new Text(FontManager.regularFont, controlsContainer);
        toggleExclusiveInter = new Interactive(340, 36, controlsContainer);
        toggleExclusiveInter.onClick = function(_) toggleExclusiveDevice();

        toggleViewModeBtn = new Text(FontManager.regularFont, controlsContainer);
        toggleViewModeInter = new Interactive(340, 36, controlsContainer);
        toggleViewModeInter.onClick = function(_) {
            controlViewMode = (controlViewMode == "Diagram") ? "Custom" : "Diagram";
            updateControlViewMode();
        };

        diagramViewer = new ControlDiagrams(controlsContainer);

        remapContainer = new Object(controlsContainer);
        var actions = ["Throttle (Gas)", "Brake / Reverse", "Steer Left", "Steer Right", "Handbrake", "Nitro Boost", "Reset All to Defaults"];
        for (i in 0...actions.length) {
            var txt = new Text(FontManager.regularFont, remapContainer);
            remapItems.push(txt);

            var inter = new Interactive(500, 36, remapContainer);
            inter.onOver = function(_) {
                remapIndex = i;
                updateRemapStyles();
            };
            inter.onClick = function(_) triggerRemapEntry(i);
            remapInteractives.push(inter);
        }

        remapStatusNotice = new Text(FontManager.regularFont, controlsContainer);
        remapStatusNotice.textColor = 0xFFEE00;
        remapStatusNotice.visible = false;
    }

    function buildCreditsScreen() {
        creditsContainer = new Object(this);

        creditsTitle = new Text(FontManager.heroFont, creditsContainer);
        creditsTitle.text = "M.O.B. // MOTORS ON BOOST";
        creditsTitle.textColor = 0xFF9800;

        // Lead Developer Section
        creditsLeadTitle = new Text(FontManager.regularFont, creditsContainer);
        creditsLeadTitle.text = "LEAD ARCHITECT & TECHNICAL DESIGNER";
        creditsLeadTitle.textColor = 0x8FA1B3;

        creditsLeadName = new Text(FontManager.titleFont, creditsContainer);
        creditsLeadName.text = "Gerard \"Jamie\" (Jagofr) Francis";
        creditsLeadName.textColor = 0x00E5FF;

        // Developer Emblem Icon
        creditsDevBadge = new Bitmap(core.UIIcons.get(core.UIIcons.IconType.Credits, 28, 0x00E5FF), creditsContainer);

        // Publisher Section
        creditsPubTitle = new Text(FontManager.regularFont, creditsContainer);
        creditsPubTitle.text = "PUBLISHED & DEVELOPED IN-HOUSE BY";
        creditsPubTitle.textColor = 0x8FA1B3;

        creditsPubName = new Text(FontManager.titleFont, creditsContainer);
        creditsPubName.text = "RvL // ROGUE";
        creditsPubName.textColor = 0xE5C07B;

        // AI Collaboration Section
        creditsAiTitle = new Text(FontManager.regularFont, creditsContainer);
        creditsAiTitle.text = "AI ENGINEERING COLLABORATION";
        creditsAiTitle.textColor = 0x8FA1B3;

        creditsAiName = new Text(FontManager.regularFont, creditsContainer);
        creditsAiName.text = "Google Gemini 3.8 Flash";
        creditsAiName.textColor = 0x98C379;

        // Frameworks & Inspiration
        creditsTechDetails = new Text(FontManager.regularFont, creditsContainer);
        creditsTechDetails.textAlign = Center;
        creditsTechDetails.maxWidth = 820;
        creditsTechDetails.textColor = 0xA0B2C6;
        creditsTechDetails.text = 
            "Built with Haxe, Heaps.io (Hardware-Accelerated WebGL) & Modern Shaders\n" +
            "Typography: Stack Sans Headline & Material Symbols Sharp\n" +
            "Homage & Inspiration: Need for Speed: Most Wanted (2005) & Burnout Revenge (2005)\n\n" +
            "Thank you for playing!";

        creditsBackBtn = new Text(FontManager.titleFont, creditsContainer);
        creditsBackBtn.text = "> BACK TO MAIN MENU <";
        creditsBackBtn.textColor = 0x00E5FF;

        creditsBackInter = new Interactive(420, 46, creditsContainer);
        creditsBackInter.onClick = function(_) showMainMenu();
    }

    public function showSplash() {
        this.visible = true; // Reveal UI container
        inputRef.flushInputs();
        splashInputCooldown = 0.35;
        currentState = Splash;
        modalDimmer.visible = false;
        cardBg.visible = false;
        splashContainer.visible = true;
        mainMenuContainer.visible = false;
        pauseContainer.visible = false;
        optionsContainer.visible = false;
        creditsContainer.visible = false;
        helpText.visible = false;
        layout();
    }

    public function showMainMenu() {
        inputRef.flushInputs();
        currentState = MainMenu;
        modalDimmer.visible = true;
        cardBg.visible = true;
        splashContainer.visible = false;
        mainMenuContainer.visible = true;
        pauseContainer.visible = false;
        optionsContainer.visible = false;
        creditsContainer.visible = false;
        helpText.text = "[Up / Down / D-Pad] Select    [A / Enter] Confirm";
        helpText.visible = true;
        mainSelectedIndex = hasActiveSave ? 1 : 0;
        updateMainMenuStyles();
        layout();
    }

    public function showInGame() {
        inputRef.flushInputs();
        currentState = InGameHUD;
        modalDimmer.visible = false;
        cardBg.visible = false;
        splashContainer.visible = false;
        mainMenuContainer.visible = false;
        pauseContainer.visible = false;
        optionsContainer.visible = false;
        creditsContainer.visible = false;
        helpText.visible = false;
    }

    public function showPause() {
        inputRef.flushInputs();
        currentState = PauseMenu;
        modalDimmer.visible = true;
        cardBg.visible = true;
        splashContainer.visible = false;
        mainMenuContainer.visible = false;
        pauseContainer.visible = true;
        optionsContainer.visible = false;
        creditsContainer.visible = false;
        pauseSelectedIndex = 0;
        helpText.text = "[Up / Down] Select    [A / Enter] Confirm    [B / Esc] Resume";
        helpText.visible = true;
        updatePauseStyles();
        layout();
    }

    public function openOptions(fromPause:Bool) {
        inputRef.flushInputs();
        currentState = OptionsMenu;
        isOpenedFromPause = fromPause;
        modalDimmer.visible = true;
        cardBg.visible = true;
        splashContainer.visible = false;
        mainMenuContainer.visible = false;
        pauseContainer.visible = false;
        optionsContainer.visible = true;
        creditsContainer.visible = false;
        helpText.text = "[LB / RB / Q / E] Switch Tabs    [Left / Right] Value    [B / Esc] Back";
        helpText.visible = true;
        switchTab(Graphics);
    }

    public function showCredits() {
        inputRef.flushInputs();
        currentState = CreditsScreen;
        modalDimmer.visible = true;
        cardBg.visible = true;
        splashContainer.visible = false;
        mainMenuContainer.visible = false;
        pauseContainer.visible = false;
        optionsContainer.visible = false;
        creditsContainer.visible = true;
        helpText.text = "[B / Esc / Enter] Return to Main Menu";
        helpText.visible = true;
        layout();
    }

    function switchTab(newTab:OptionsTab) {
        currentTab = newTab;
        AudioManager.inst.playMenuBeep(420, 0.05);

        graphicsContainer.visible = (currentTab == Graphics);
        audioContainer.visible = (currentTab == Audio);
        controlsContainer.visible = (currentTab == Keyboard || currentTab == Gamepad);

        if (currentTab == Keyboard || currentTab == Gamepad) updateControlViewMode();
        else if (currentTab == Graphics) updateGraphicsStyles();
        else if (currentTab == Audio) updateAudioStyles();

        updateTabStyles();
        layout();
    }

    function triggerMainAction(act:MenuAction) {
        switch (act) {
            case StartGame: if (onMenuAction != null) onMenuAction(StartGame);
            case ResumeGame: if (hasActiveSave && onMenuAction != null) onMenuAction(ResumeGame);
            case OpenOptions: openOptions(false);
            case OpenCredits: showCredits();
            case QuitToTitle: showSplash();
        }
    }

    function cycleGraphicsOption(idx:Int, dir:Int) {
        AudioManager.inst.playMenuBeep(480, 0.05);
        var s = gfxSettings;

        switch (idx) {
            case 0:
                if (isOpenedFromPause) return;
                var list = ["Off", "Very Low", "Low", "Medium", "High", "Ultra", "Unreal"];
                s.textures = cycleArray(list, s.textures, dir);
            case 1:
                var list = ["Off", "Normal", "High", "Ultra", "Dynamic"];
                s.shadowLevel = cycleArray(list, s.shadowLevel, dir);
                GraphicsManager.inst.applyShadows();
            case 2:
                var list = [512, 1024, 2048, 4096];
                s.shadowRes = cycleArray(list, s.shadowRes, dir);
                GraphicsManager.inst.applyShadows();
            case 3:
                if (isOpenedFromPause) return;
                var list = ["Low", "Medium", "High", "Ultra (RTX/Path)"];
                s.lightingLevel = cycleArray(list, s.lightingLevel, dir);
                GraphicsManager.inst.applyLighting();
            case 4:
                var list = [512, 1024, 2048];
                s.lightingRes = cycleArray(list, s.lightingRes, dir);
            case 5:
                if (isOpenedFromPause) return;
                s.mipmapping = !s.mipmapping;
            case 6:
                if (isOpenedFromPause) return;
                var list = [1, 2, 4, 8, 16];
                s.anisotropic = cycleArray(list, s.anisotropic, dir);
            case 7:
                var list = ["None", "FXAA", "TSAA", "SMAA", "MSAA"];
                s.aaType = cycleArray(list, s.aaType, dir);
            case 8:
                var list = [2, 4, 8];
                s.aaLevel = cycleArray(list, s.aaLevel, dir);
            case 9:
                if (isOpenedFromPause) return;
                var list = ["Very Low", "Low", "Medium", "High", "Ultra"];
                s.modelGeometry = cycleArray(list, s.modelGeometry, dir);
            case 10:
                s.modelReflections = !s.modelReflections;
            case 11:
                var list = ["Low", "Medium", "High", "Ultra"];
                s.reflectionLevel = cycleArray(list, s.reflectionLevel, dir);
            case 12:
                var list = [0.25, 0.334, 0.5, 0.75, 1.0, 2.0, 3.0, 4.0];
                s.renderScale = cycleArray(list, s.renderScale, dir);
                GraphicsManager.inst.applyRenderScale();
        }

        updateGraphicsStyles();
    }

    function cycleArray<T>(arr:Array<T>, curr:T, dir:Int):T {
        var idx = arr.indexOf(curr);
        if (idx == -1) idx = 0;
        var next = (idx + dir + arr.length) % arr.length;
        return arr[next];
    }

    public function update(dt:Float, uiUp:Bool, uiDown:Bool, uiLeft:Bool, uiRight:Bool, uiConfirm:Bool, uiCancel:Bool) {
        if (splashInputCooldown > 0.0) splashInputCooldown -= dt;

        if (currentState == Splash) {
            promptBlinkTimer += dt * 3.5;
            splashPrompt.alpha = (Math.sin(promptBlinkTimer) * 0.4) + 0.6;
            if (splashInputCooldown <= 0.0 && inputRef.anyKeyPressed) showMainMenu();
            return;
        }

        if (currentState == MainMenu) {
            if (uiUp) {
                mainSelectedIndex = (mainSelectedIndex - 1 + mainMenuButtons.length) % mainMenuButtons.length;
                AudioManager.inst.playMenuBeep(380, 0.04);
                updateMainMenuStyles();
            } else if (uiDown) {
                mainSelectedIndex = (mainSelectedIndex + 1) % mainMenuButtons.length;
                AudioManager.inst.playMenuBeep(380, 0.04);
                updateMainMenuStyles();
            }
            if (uiConfirm) {
                var actions = [MenuAction.StartGame, MenuAction.ResumeGame, MenuAction.OpenOptions, MenuAction.OpenCredits, MenuAction.QuitToTitle];
                if (mainSelectedIndex == 1 && !hasActiveSave) return;
                AudioManager.inst.playMenuBeep(520, 0.08);
                triggerMainAction(actions[mainSelectedIndex]);
            }
        } else if (currentState == PauseMenu) {
            if (uiUp) {
                pauseSelectedIndex = (pauseSelectedIndex - 1 + pauseButtons.length) % pauseButtons.length;
                AudioManager.inst.playMenuBeep(380, 0.04);
                updatePauseStyles();
            } else if (uiDown) {
                pauseSelectedIndex = (pauseSelectedIndex + 1) % pauseButtons.length;
                AudioManager.inst.playMenuBeep(380, 0.04);
                updatePauseStyles();
            }
            if (uiConfirm) {
                AudioManager.inst.playMenuBeep(520, 0.08);
                switch (pauseSelectedIndex) {
                    case 0: if (onMenuAction != null) onMenuAction(ResumeGame);
                    case 1: if (onMenuAction != null) onMenuAction(StartGame);
                    case 2: openOptions(true);
                    case 3: if (onMenuAction != null) onMenuAction(QuitToTitle);
                }
            } else if (uiCancel) {
                if (onMenuAction != null) onMenuAction(ResumeGame);
            }
        } else if (currentState == OptionsMenu) {
            if (inputRef.tabPrevPressed) {
                var currentIdx = TAB_ORDER.indexOf(currentTab);
                var nextIdx = (currentIdx - 1 + TAB_ORDER.length) % TAB_ORDER.length;
                switchTab(TAB_ORDER[nextIdx]);
            } else if (inputRef.tabNextPressed) {
                var currentIdx = TAB_ORDER.indexOf(currentTab);
                var nextIdx = (currentIdx + 1) % TAB_ORDER.length;
                switchTab(TAB_ORDER[nextIdx]);
            }

            if (currentTab == Graphics) {
                if (uiUp) {
                    graphicsIndex = (graphicsIndex - 1 + graphicsItems.length) % graphicsItems.length;
                    AudioManager.inst.playMenuBeep(380, 0.04);
                    updateGraphicsStyles();
                } else if (uiDown) {
                    graphicsIndex = (graphicsIndex + 1) % graphicsItems.length;
                    AudioManager.inst.playMenuBeep(380, 0.04);
                    updateGraphicsStyles();
                }
                if (uiLeft) cycleGraphicsOption(graphicsIndex, -1);
                if (uiRight || uiConfirm) cycleGraphicsOption(graphicsIndex, 1);
            } else if (currentTab == Audio) {
                if (uiUp) {
                    audioIndex = (audioIndex - 1 + audioItems.length) % audioItems.length;
                    AudioManager.inst.playMenuBeep(380, 0.04);
                    updateAudioStyles();
                } else if (uiDown) {
                    audioIndex = (audioIndex + 1) % audioItems.length;
                    AudioManager.inst.playMenuBeep(380, 0.04);
                    updateAudioStyles();
                }
                if (uiLeft) adjustVolume(audioIndex, -0.1);
                if (uiRight) adjustVolume(audioIndex, 0.1);
            } else {
                if (controlViewMode == "Custom") {
                    if (uiUp) {
                        remapIndex = (remapIndex - 1 + remapItems.length) % remapItems.length;
                        AudioManager.inst.playMenuBeep(380, 0.04);
                        updateRemapStyles();
                    } else if (uiDown) {
                        remapIndex = (remapIndex + 1) % remapItems.length;
                        AudioManager.inst.playMenuBeep(380, 0.04);
                        updateRemapStyles();
                    }
                    if (uiConfirm) triggerRemapEntry(remapIndex);
                }
            }

            if (uiCancel) {
                if (isOpenedFromPause) showPause();
                else showMainMenu();
            }
        } else if (currentState == CreditsScreen) {
            if (uiCancel || uiConfirm) showMainMenu();
        }
    }

    function updateMainMenuStyles() {
        for (i in 0...mainMenuButtons.length) {
            var b = mainMenuButtons[i];
            var ic = mainMenuIcons[i];

            if (i == 1 && !hasActiveSave) {
                b.textColor = 0x55606E;
                ic.color.setColor(0x55606E);
                continue;
            }
            if (i == mainSelectedIndex) {
                b.textColor = 0x00E5FF;
                ic.color.setColor(0x00E5FF);
            } else {
                b.textColor = 0xC2D1E0;
                ic.color.setColor(0x8FA1B3);
            }
        }
        drawBackplates();
    }

    function updatePauseStyles() {
        for (i in 0...pauseButtons.length) {
            var b = pauseButtons[i];
            var ic = pauseIcons[i];

            if (i == pauseSelectedIndex) {
                b.textColor = 0x00E5FF;
                ic.color.setColor(0x00E5FF);
            } else {
                b.textColor = 0xC2D1E0;
                ic.color.setColor(0x8FA1B3);
            }
        }
        drawBackplates();
    }

    function updateGraphicsStyles() {
        var s = gfxSettings;
        var inGameLocked = isOpenedFromPause;

        var vals = [
            s.textures + (inGameLocked ? " [LOCKED IN-RUN]" : ""),
            s.shadowLevel,
            s.shadowRes + "p",
            s.lightingLevel + (inGameLocked ? " [LOCKED IN-RUN]" : ""),
            s.lightingRes + "p",
            (s.mipmapping ? "Enabled" : "Disabled") + (inGameLocked ? " [LOCKED IN-RUN]" : ""),
            s.anisotropic + "x" + (inGameLocked ? " [LOCKED IN-RUN]" : ""),
            s.aaType,
            s.aaLevel + "x",
            s.modelGeometry + (inGameLocked ? " [LOCKED IN-RUN]" : ""),
            s.modelReflections ? "Active" : "Disabled",
            s.reflectionLevel,
            s.renderScale + "x (" + Math.round(s.renderScale * 100) + "%)"
        ];

        var titles = [
            "Texture Fidelity:    ", "Shadow Quality:      ", "Shadow Buffer:       ", "Lighting Pipeline:   ", "Light Buffer:        ",
            "Mipmapping Filters:  ", "Anisotropy Sampling: ", "Anti-Aliasing Pass:  ", "AA Multiplier:       ", "Model Geometry LOD:  ",
            "Screen Reflections:  ", "Reflection Updates:  ", "Resolution Scale:    "
        ];

        for (i in 0...graphicsItems.length) {
            var item = graphicsItems[i];
            var isLocked = inGameLocked && (i == 0 || i == 3 || i == 5 || i == 6 || i == 9);

            if (i == graphicsIndex) {
                item.textColor = isLocked ? 0x8FA1B3 : 0x00E5FF;
                item.text = "> " + titles[i] + vals[i] + " <";
            } else {
                item.textColor = isLocked ? 0x55606E : 0xC2D1E0;
                item.text = "  " + titles[i] + vals[i] + "  ";
            }
        }
        drawBackplates();
    }

    function formatSlider(val:Float):String {
        var pct = Math.round(val * 100);
        var totalBars = 12;
        var activeBars = Math.round(val * totalBars);

        var barStr = "";
        for (i in 0...totalBars) {
            barStr += (i < activeBars ? FontManager.BLOCK_FILLED : FontManager.BLOCK_EMPTY);
        }

        return "[" + barStr + "]  " + (pct < 100 ? (pct < 10 ? "  " : " ") : "") + pct + "%";
    }

    function updateAudioStyles() {
        var am = AudioManager.inst;
        var labels = [
            "Master Volume:     " + formatSlider(am.masterVolume),
            "Music Track:       " + formatSlider(am.musicVolume),
            "Sound FX & Tires:  " + formatSlider(am.sfxVolume)
        ];

        for (i in 0...audioItems.length) {
            var item = audioItems[i];
            var ic = audioIcons[i];
            if (i == audioIndex) {
                item.textColor = 0x00E5FF;
                ic.color.setColor(0x00E5FF);
                item.text = "> " + labels[i] + " <";
            } else {
                item.textColor = 0xC2D1E0;
                ic.color.setColor(0x8FA1B3);
                item.text = "  " + labels[i] + "  ";
            }
        }
        drawBackplates();
    }

    function updateTabStyles() {
        for (i in 0...TAB_ORDER.length) {
            var lbl = tabLabels[i];
            var ic = tabIcons[i];

            if (TAB_ORDER[i] == currentTab) {
                lbl.textColor = 0x00E5FF;
                ic.color.setColor(0x00E5FF);
            } else {
                lbl.textColor = 0x7E8E9F;
                ic.color.setColor(0x7E8E9F);
            }
        }
        drawBackplates();
    }

    function updateControlViewMode() {
        diagramViewer.visible = (controlViewMode == "Diagram");
        remapContainer.visible = (controlViewMode == "Custom");
        if (controlViewMode == "Diagram") {
            if (currentTab == Keyboard) diagramViewer.drawKeyboardLayout();
            else diagramViewer.drawGamepadLayout();
        } else {
            updateRemapStyles();
        }
        updateControlHeaderButtons();
        layout();
    }

    function updateControlHeaderButtons() {
        var isKbd = (currentTab == Keyboard);
        var active = inputRef.exclusiveDevice;
        var status = "BOTH ACTIVE";
        if (active == KeyboardOnly) status = isKbd ? "EXCLUSIVE (ACTIVE)" : "MUTED";
        else if (active == GamepadOnly) status = !isKbd ? "EXCLUSIVE (ACTIVE)" : "MUTED";

        toggleExclusiveBtn.text = "[DEVICE: " + status + "]";
        toggleExclusiveBtn.textColor = (status.indexOf("MUTED") >= 0) ? 0xE06C75 : 0x98C379;
        toggleViewModeBtn.text = "[MODE: " + (controlViewMode == "Diagram" ? "DEFAULT DIAGRAM" : "CUSTOM REMAPPING") + "]";
        toggleViewModeBtn.textColor = 0x00E5FF;
    }

    function toggleExclusiveDevice() {
        AudioManager.inst.playMenuBeep(480, 0.06);
        if (currentTab == Keyboard) inputRef.exclusiveDevice = (inputRef.exclusiveDevice == KeyboardOnly) ? Both : KeyboardOnly;
        else if (currentTab == Gamepad) inputRef.exclusiveDevice = (inputRef.exclusiveDevice == GamepadOnly) ? Both : GamepadOnly;
        updateControlHeaderButtons();
    }

    function triggerRemapEntry(idx:Int) {
        if (idx == 6) {
            AudioManager.inst.playMenuBeep(320, 0.08);
            if (currentTab == Keyboard) inputRef.bindings.resetKeyboardDefaults();
            else inputRef.bindings.resetGamepadDefaults();
            updateRemapStyles();
            return;
        }

        var isGamepad = (currentTab == Gamepad);
        var actList = [InputAction.Throttle, InputAction.Brake, InputAction.SteerLeft, InputAction.SteerRight, InputAction.Handbrake, InputAction.Boost];
        AudioManager.inst.playMenuBeep(640, 0.1);
        remapStatusNotice.text = "PRESS ANY " + (isGamepad ? "BUTTON" : "KEY") + "...";
        remapStatusNotice.visible = true;
        inputRef.startListening(actList[idx], isGamepad);
    }

    function updateRemapStyles() {
        var isGamepad = (currentTab == Gamepad);
        var b = inputRef.bindings;
        var labels = [
            "Throttle (Gas):       " + (isGamepad ? InputController.getGamepadBtnName(b.padGas) : InputController.getKeyName(b.keyGas)),
            "Brake / Reverse:      " + (isGamepad ? InputController.getGamepadBtnName(b.padBrake) : InputController.getKeyName(b.keyBrake)),
            "Steer Left:           " + (isGamepad ? "Left Analog / D-Pad" : InputController.getKeyName(b.keyLeft)),
            "Steer Right:          " + (isGamepad ? "Left Analog / D-Pad" : InputController.getKeyName(b.keyRight)),
            "Handbrake (Drift):    " + (isGamepad ? InputController.getGamepadBtnName(b.padHandbrake) : InputController.getKeyName(b.keyHandbrake)),
            "Nitro Boost:          " + (isGamepad ? InputController.getGamepadBtnName(b.padBoost) : InputController.getKeyName(b.keyBoost)),
            "[RESET TO DEFAULTS]"
        ];

        for (i in 0...remapItems.length) {
            var item = remapItems[i];
            if (i == remapIndex) {
                item.textColor = 0x00E5FF;
                item.text = "> " + labels[i] + " <";
            } else {
                item.textColor = (i == 6) ? 0xE5C07B : 0xC2D1E0;
                item.text = "  " + labels[i] + "  ";
            }
        }
        drawBackplates();
    }

    function adjustVolume(channel:Int, delta:Float) {
        var am = AudioManager.inst;
        switch (channel) {
            case 0: am.masterVolume = Math.max(0.0, Math.min(1.0, am.masterVolume + delta));
            case 1: am.musicVolume = Math.max(0.0, Math.min(1.0, am.musicVolume + delta));
            case 2: am.sfxVolume = Math.max(0.0, Math.min(1.0, am.sfxVolume + delta));
        }
        am.playMenuBeep(480 + (channel * 60), 0.05);
        updateAudioStyles();
    }

    function drawBackplates() {
        cardBg.clear();
        if (!cardBg.visible) return;

        var sw = hxd.Window.getInstance().width;
        var sh = hxd.Window.getInstance().height;

        cardBg.beginFill(0x13171F, 0.88);
        cardBg.lineStyle(2.0, 0x00E5FF, 0.45);

        if (currentState == MainMenu) {
            var cardW = 540;
            var cardH = 360;
            var cardX = (sw - cardW) * 0.5;
            var cardY = sh * 0.28;
            cardBg.drawRoundedRect(cardX, cardY, cardW, cardH, 14);

            var activeY = sh * 0.32 + (mainSelectedIndex * 52);
            cardBg.beginFill(0x00E5FF, 0.12);
            cardBg.lineStyle(1.5, 0x00E5FF, 0.7);
            cardBg.drawRoundedRect(cardX + 24, activeY - 4, cardW - 48, 44, 8);
        } else if (currentState == PauseMenu) {
            var cardW = 500;
            var cardH = 320;
            var cardX = (sw - cardW) * 0.5;
            var cardY = sh * 0.32;
            cardBg.drawRoundedRect(cardX, cardY, cardW, cardH, 14);

            var activeY = sh * 0.38 + (pauseSelectedIndex * 54);
            cardBg.beginFill(0x00E5FF, 0.12);
            cardBg.lineStyle(1.5, 0x00E5FF, 0.7);
            cardBg.drawRoundedRect(cardX + 24, activeY - 4, cardW - 48, 44, 8);
        } else if (currentState == OptionsMenu) {
            var cardW = 920;
            var cardH = 560;
            var cardX = (sw - cardW) * 0.5;
            var cardY = sh * 0.16;
            cardBg.drawRoundedRect(cardX, cardY, cardW, cardH, 16);

            var activeTabIdx = TAB_ORDER.indexOf(currentTab);
            var tabStartX = (sw - (TAB_ORDER.length * 170)) * 0.5;
            var tabX = tabStartX + (activeTabIdx * 170);
            cardBg.beginFill(0x00E5FF, 0.18);
            cardBg.lineStyle(2.0, 0x00E5FF, 0.9);
            cardBg.drawRoundedRect(tabX + 6, sh * 0.18 - 4, 150, 42, 8);
        } else if (currentState == CreditsScreen) {
            var cardW = 860;
            var cardH = 610;
            var cardX = (sw - cardW) * 0.5;
            var cardY = sh * 0.12;
            cardBg.drawRoundedRect(cardX, cardY, cardW, cardH, 16);

            // Lead Architect Accent Container
            cardBg.beginFill(0x00E5FF, 0.08);
            cardBg.lineStyle(1.5, 0x00E5FF, 0.4);
            cardBg.drawRoundedRect(cardX + 32, sh * 0.22, cardW - 64, 76, 10);
        }
        cardBg.endFill();
    }

    public function layout() {
        var sw = hxd.Window.getInstance().width;
        var sh = hxd.Window.getInstance().height;

        if (modalDimmer != null) {
            modalDimmer.scaleX = sw;
            modalDimmer.scaleY = sh;
        }

        drawBackplates();

        if (splashTitle != null) {
            splashTitle.x = (sw - splashTitle.textWidth) * 0.5;
            splashTitle.y = sh * 0.36;
        }
        if (splashPrompt != null) {
            splashPrompt.x = (sw - splashPrompt.textWidth) * 0.5;
            splashPrompt.y = sh * 0.52;
        }

        if (mainTitle != null) {
            mainTitle.x = (sw - mainTitle.textWidth) * 0.5;
            mainTitle.y = sh * 0.16;
        }
        for (i in 0...mainMenuButtons.length) {
            var b = mainMenuButtons[i];
            var ic = mainMenuIcons[i];
            var inter = mainMenuInteractives[i];

            var rowY = sh * 0.32 + (i * 52);
            var rowStartX = sw * 0.5 - 190;

            ic.x = rowStartX;
            ic.y = rowY + 3;

            b.x = rowStartX + 36;
            b.y = rowY;

            inter.x = sw * 0.5 - 220;
            inter.y = rowY - 4;
            inter.width = 440;
            inter.height = 44;
        }

        if (pauseTitle != null) {
            pauseTitle.x = (sw - pauseTitle.textWidth) * 0.5;
            pauseTitle.y = sh * 0.20;
        }
        for (i in 0...pauseButtons.length) {
            var b = pauseButtons[i];
            var ic = pauseIcons[i];
            var inter = pauseInteractives[i];

            var rowY = sh * 0.38 + (i * 54);
            var rowStartX = sw * 0.5 - 160;

            ic.x = rowStartX;
            ic.y = rowY + 3;

            b.x = rowStartX + 36;
            b.y = rowY;

            inter.x = sw * 0.5 - 190;
            inter.y = rowY - 4;
            inter.width = 380;
            inter.height = 44;
        }

        if (optionsTitle != null) {
            optionsTitle.x = (sw - optionsTitle.textWidth) * 0.5;
            optionsTitle.y = sh * 0.10;
        }

        var tabSpacing = 170;
        var tabStartX = (sw - (TAB_ORDER.length * tabSpacing)) * 0.5;
        for (i in 0...TAB_ORDER.length) {
            var ic = tabIcons[i];
            var lbl = tabLabels[i];
            var inter = tabInteractives[i];

            var colX = tabStartX + (i * tabSpacing);
            var colY = sh * 0.18;

            ic.x = colX + 18;
            ic.y = colY + 4;

            lbl.x = colX + 48;
            lbl.y = colY + 3;

            inter.x = colX + 6;
            inter.y = colY - 4;
            inter.width = 150;
            inter.height = 42;
        }

        for (i in 0...graphicsItems.length) {
            var item = graphicsItems[i];
            var inter = graphicsInteractives[i];
            item.x = (sw - item.textWidth) * 0.5;
            item.y = sh * 0.26 + (i * 28);
            inter.x = sw * 0.5 - 280;
            inter.y = item.y;
            inter.width = 560;
            inter.height = 28;
        }

        for (i in 0...audioItems.length) {
            var item = audioItems[i];
            var ic = audioIcons[i];
            var inter = audioInteractives[i];

            var rowY = sh * 0.36 + (i * 64);
            var rowX = sw * 0.5 - 260;

            ic.x = rowX;
            ic.y = rowY - 3;

            item.x = rowX + 44;
            item.y = rowY;

            inter.x = rowX;
            inter.y = rowY - 4;
            inter.width = 560;
            inter.height = 48;
        }

        if (toggleExclusiveBtn != null) {
            toggleExclusiveBtn.x = sw * 0.5 - 340;
            toggleExclusiveBtn.y = sh * 0.25;
            toggleExclusiveInter.x = toggleExclusiveBtn.x;
            toggleExclusiveInter.y = toggleExclusiveBtn.y;
            toggleExclusiveInter.width = 300;
            toggleExclusiveInter.height = 34;
        }
        if (toggleViewModeBtn != null) {
            toggleViewModeBtn.x = sw * 0.5 + 40;
            toggleViewModeBtn.y = sh * 0.25;
            toggleViewModeInter.x = toggleViewModeBtn.x;
            toggleViewModeInter.y = toggleViewModeBtn.y;
            toggleViewModeInter.width = 300;
            toggleViewModeInter.height = 34;
        }
        if (diagramViewer != null) {
            diagramViewer.x = sw * 0.5;
            diagramViewer.y = sh * 0.58;
        }
        for (i in 0...remapItems.length) {
            var item = remapItems[i];
            var inter = remapInteractives[i];
            item.x = (sw - item.textWidth) * 0.5;
            item.y = sh * 0.33 + (i * 38);
            inter.x = sw * 0.5 - 250;
            inter.y = item.y;
            inter.width = 500;
            inter.height = 36;
        }

        // Credits Hierarchy Layout
        if (creditsTitle != null) {
            creditsTitle.x = (sw - creditsTitle.textWidth) * 0.5;
            creditsTitle.y = sh * 0.15;
        }
        if (creditsLeadTitle != null) {
            creditsLeadTitle.x = (sw - creditsLeadTitle.textWidth) * 0.5;
            creditsLeadTitle.y = sh * 0.23;
        }
        if (creditsLeadName != null && creditsDevBadge != null) {
            var comboWidth = creditsLeadName.textWidth + 38;
            var startX = (sw - comboWidth) * 0.5;

            creditsDevBadge.x = startX;
            creditsDevBadge.y = sh * 0.27 + 2;

            creditsLeadName.x = startX + 38;
            creditsLeadName.y = sh * 0.27;
        }
        if (creditsPubTitle != null) {
            creditsPubTitle.x = (sw - creditsPubTitle.textWidth) * 0.5;
            creditsPubTitle.y = sh * 0.36;
        }
        if (creditsPubName != null) {
            creditsPubName.x = (sw - creditsPubName.textWidth) * 0.5;
            creditsPubName.y = sh * 0.40;
        }
        if (creditsAiTitle != null) {
            creditsAiTitle.x = (sw - creditsAiTitle.textWidth) * 0.5;
            creditsAiTitle.y = sh * 0.48;
        }
        if (creditsAiName != null) {
            creditsAiName.x = (sw - creditsAiName.textWidth) * 0.5;
            creditsAiName.y = sh * 0.52;
        }
        if (creditsTechDetails != null) {
            creditsTechDetails.x = (sw - creditsTechDetails.textWidth) * 0.5;
            creditsTechDetails.y = sh * 0.58;
        }
        if (creditsBackBtn != null) {
            creditsBackBtn.x = (sw - creditsBackBtn.textWidth) * 0.5;
            creditsBackBtn.y = sh * 0.72;
            creditsBackInter.x = creditsBackBtn.x - 20;
            creditsBackInter.y = creditsBackBtn.y - 4;
            creditsBackInter.width = creditsBackBtn.textWidth + 40;
            creditsBackInter.height = 46;
        }

        if (helpText != null) {
            helpText.x = (sw - helpText.textWidth) * 0.5;
            helpText.y = sh * 0.94;
        }
    }
}