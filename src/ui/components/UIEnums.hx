package ui.components;

/**
 * Dispatched user actions emitted from menu selections.
 */
enum MenuAction {
    /** Start a fresh new circuit race from the starting line. */
    StartGame;

    /** Resume an active in-progress race run restored from persistent storage. */
    ResumeGame;

    /** Open hardware and gameplay options configuration panel. */
    OpenOptions;

    /** Display game development credits and disclosures screen. */
    OpenCredits;

    /** Exit back to primary title splash screen. */
    QuitToTitle;
}

/**
 * State machine stages for user interface screens.
 */
enum UIState {
    /** Press any key / title splash entrance screen. */
    Splash;

    /** Primary main menu selection screen. */
    MainMenu;

    /** In-game transparent HUD with speedometer and frame counter. */
    InGameHUD;

    /** Mid-race pause menu modal. */
    PauseMenu;

    /** Hardware options and remapping configuration tabs modal. */
    OptionsMenu;

    /** Studio and engine credits overlay screen. */
    CreditsScreen;
}

/**
 * Tabs available within the options configuration modal.
 */
enum OptionsTab {
    /** Graphics rendering resolution, lighting, and shadow settings. */
    Graphics;

    /** Master, music, and sound effects volume slider controls. */
    Audio;

    /** Desktop keyboard bindings and layout schematic diagram. */
    Keyboard;

    /** Gamepad controller bindings and schematic diagram. */
    Gamepad;

    /** Mobile virtual touch controls layout and on-screen button positioning. */
    Touch;
}

