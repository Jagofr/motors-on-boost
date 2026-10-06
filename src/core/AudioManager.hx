package core;

class AudioManager {
    public static var inst:AudioManager;

    public var masterVolume:Float = 0.8;
    public var musicVolume:Float = 0.7;
    public var sfxVolume:Float = 0.9;

    var audioCtx:Dynamic;

    public function new() {
        inst = this;
        #if js
        try {
            var audioWindow:Dynamic = js.Browser.window;
            var AudioContextClass = audioWindow.AudioContext != null ? audioWindow.AudioContext : audioWindow.webkitAudioContext;
            if (AudioContextClass != null) {
                audioCtx = Type.createInstance(AudioContextClass, []);
            }
        } catch (e:Dynamic) {}
        #end
    }

    public function playMenuBeep(freq:Float = 440.0, duration:Float = 0.06) {
        #if js
        if (audioCtx == null) return;
        try {
            if (audioCtx.state == "suspended") {
                audioCtx.resume();
            }
            var osc = audioCtx.createOscillator();
            var gain = audioCtx.createGain();

            osc.type = "sine";
            osc.frequency.setValueAtTime(freq, audioCtx.currentTime);

            var finalVol = masterVolume * sfxVolume * 0.15;
            gain.gain.setValueAtTime(finalVol, audioCtx.currentTime);
            gain.gain.exponentialRampToValueAtTime(0.0001, audioCtx.currentTime + duration);

            osc.connect(gain);
            gain.connect(audioCtx.destination);

            osc.start();
            osc.stop(audioCtx.currentTime + duration);
        } catch (e:Dynamic) {}
        #end
    }
}