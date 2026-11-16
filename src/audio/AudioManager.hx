package audio;

import config.GameConfig;

/**
 * Web Audio API synthesizer sound manager and volume pipeline.
 * Procedurally generates UI feedback tones and manages master, music, and SFX gains.
 *
 * @class AudioManager
 * @module audio/AudioManager
 */
class AudioManager {
    /** Global singleton instance for access across UI and gameplay modules. */
    public static var inst:AudioManager;

    /** Active audio configuration defaults. */
    public var config:config.GameConfig.AudioConfig;

    /** Global master volume level clamped in range [0.0, 1.0]. @default 0.8 */
    public var masterVolume:Float = 0.8;

    /** Background music volume level clamped in range [0.0, 1.0]. @default 0.7 */
    public var musicVolume:Float = 0.7;

    /** Sound effects, tire screech, and collision volume level clamped in range [0.0, 1.0]. @default 0.9 */
    public var sfxVolume:Float = 0.9;

    /** Native HTML5 AudioContext instance. */
    var audioCtx:js.html.audio.AudioContext;

    /**
     * Initializes the AudioManager singleton and establishes the browser Web Audio context.
     *
     * @param {Null<config.GameConfig.AudioConfig>} [config] Optional volume & synth defaults.
     */
    public function new(?config:config.GameConfig.AudioConfig) {
        inst = this;
        this.config = config != null ? config : GameConfig.getDefault().audio;
        masterVolume = this.config.defaultMaster;
        musicVolume = this.config.defaultMusic;
        sfxVolume = this.config.defaultSfx;
        #if js
        try {
            var w = js.Browser.window;
            if (w != null) {
                if (js.Syntax.code("window.AudioContext")) {
                    audioCtx = new js.html.audio.AudioContext();
                } else if (js.Syntax.code("window.webkitAudioContext")) {
                    audioCtx = js.Syntax.code("new window.webkitAudioContext()");
                }
            }
        } catch (e:haxe.Exception) {}
        #end
    }

    /**
     * Synthesizes an instantaneous sine wave beep for UI navigation feedback.
     *
     * @param {Float} [freq=440.0] Oscillator frequency in Hertz (Hz).
     * @param {Float} [duration=0.06] Tone duration in seconds before ramp zeroing.
     * @returns {Void}
     */
    public function playMenuBeep(freq:Float = 440.0, duration:Float = 0.06):Void {
        #if js
        if (audioCtx == null) return;
        try {
            if (audioCtx.state == js.html.audio.AudioContextState.SUSPENDED) {
                audioCtx.resume();
            }
            var osc = audioCtx.createOscillator();
            var gain = audioCtx.createGain();

            osc.type = js.html.audio.OscillatorType.SINE;
            osc.frequency.setValueAtTime(freq, audioCtx.currentTime);

            var finalVol = masterVolume * sfxVolume * config.beepGainScale;
            gain.gain.setValueAtTime(finalVol, audioCtx.currentTime);
            gain.gain.exponentialRampToValueAtTime(0.0001, audioCtx.currentTime + duration);

            osc.connect(gain);
            gain.connect(audioCtx.destination);

            osc.start();
            osc.stop(audioCtx.currentTime + duration);
        } catch (e:haxe.Exception) {}
        #end
    }

    /**
     * Suspends the active Web Audio context while playback is blocked by portrait orientation.
     *
     * @returns {Void}
     */
    public function suspend():Void {
        #if js
        if (audioCtx == null) return;
        try {
            if (audioCtx.state == js.html.audio.AudioContextState.RUNNING) {
                audioCtx.suspend();
            }
        } catch (e:haxe.Exception) {}
        #end
    }

    /**
     * Resumes the Web Audio context when orientation or active playback is restored.
     *
     * @returns {Void}
     */
    public function resume():Void {
        #if js
        if (audioCtx == null) return;
        try {
            if (audioCtx.state == js.html.audio.AudioContextState.SUSPENDED) {
                audioCtx.resume();
            }
        } catch (e:haxe.Exception) {}
        #end
    }
}