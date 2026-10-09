package audio;

/**
 * Web Audio API synthesize sound manager and audio pipeline.
 * Procedurally generates UI feedback tones, menu navigation chirps, and manages
 * volume attenuation across master, music, and sound effects channels.
 */
class AudioManager {
    /** Global singleton instance for access across UI and gameplay modules. */
    public static var inst:AudioManager;

    /** Global master volume level clamped in range [0.0, 1.0]. */
    public var masterVolume:Float = 0.8;

    /** Background music volume level clamped in range [0.0, 1.0]. */
    public var musicVolume:Float = 0.7;

    /** Sound effects, tire screech, and collision volume level clamped in range [0.0, 1.0]. */
    public var sfxVolume:Float = 0.9;

    /** Native HTML5 AudioContext instance. */
    var audioCtx:js.html.audio.AudioContext;

    /**
     * Initializes the AudioManager singleton and establishes the browser Web Audio context.
     * Gracefully falls back if Web Audio is unsupported or restricted by browser autoplay policy.
     */
    public function new() {
        inst = this;
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
     * Uses exponential gain ramping to prevent audio popping and clipping artifacts.
     *
     * @param freq Oscillator frequency in Hertz (Hz). Default is 440Hz (A4 tone).
     * @param duration Playback duration of tone in seconds before ramping to zero. Default is 0.06s.
     */
    public function playMenuBeep(freq:Float = 440.0, duration:Float = 0.06) {
        #if js
        if (audioCtx == null) return;
        try {
            // Resume suspended context if browser policy required user gesture
            if (audioCtx.state == js.html.audio.AudioContextState.SUSPENDED) {
                audioCtx.resume();
            }
            var osc = audioCtx.createOscillator();
            var gain = audioCtx.createGain();

            osc.type = js.html.audio.OscillatorType.SINE;
            osc.frequency.setValueAtTime(freq, audioCtx.currentTime);

            // Compute composite attenuation volume
            var finalVol = masterVolume * sfxVolume * 0.15;
            gain.gain.setValueAtTime(finalVol, audioCtx.currentTime);
            gain.gain.exponentialRampToValueAtTime(0.0001, audioCtx.currentTime + duration);

            osc.connect(gain);
            gain.connect(audioCtx.destination);

            osc.start();
            osc.stop(audioCtx.currentTime + duration);
        } catch (e:haxe.Exception) {}
        #end
    }
}