package;

import utest.Runner;
import utest.ui.text.PrintReport;
import tests.core.TestVersion;
import tests.physics.TestSplineMath;
import tests.physics.TestCarConfig;
import tests.physics.TestCarPhysics;
import tests.save.TestSaveSystem;
import tests.input.TestInputController;
import tests.world.TestTrack;
import tests.entities.TestTrafficSystem;
import tests.camera.TestChaseCamera;
import tests.ui.TestGraphicsOptions;
import tests.ui.TestTouchControls;
import tests.audio.TestAudioManager;

/**
 * Main test runner executing full test suite across all codebase modules.
 * Compatible with CLI execution and VSCode Haxe Test Explorer plugin.
 */
class TestMain {
    public static function main() {
        #if js
        // Headless texture stub for Node.js test execution
        var dummyTex:Dynamic = {
            flags: 0,
            width: 1,
            height: 1,
            clear: function(c, a) {},
            dispose: function() {},
            isDisposed: function() return false
        };
        untyped h3d.mat.Texture.fromColor = function(color, alpha) {
            return dummyTex;
        };
        #end

        new audio.AudioManager();

        var runner = new Runner();

        runner.addCase(new TestVersion());
        runner.addCase(new TestSplineMath());
        runner.addCase(new TestCarConfig());
        runner.addCase(new TestCarPhysics());
        runner.addCase(new TestSaveSystem());
        runner.addCase(new TestInputController());
        runner.addCase(new TestTrack());
        runner.addCase(new TestTrafficSystem());
        runner.addCase(new TestChaseCamera());
        runner.addCase(new TestGraphicsOptions());
        runner.addCase(new TestTouchControls());
        runner.addCase(new TestAudioManager());

        var report = new PrintReport(runner);
        var hasFailures = false;

        runner.onProgress.add(function(e) {
            for (assert in e.result.assertations) {
                switch (assert) {
                    case Success(_):
                    case Warning(_):
                    default:
                        hasFailures = true;
                }
            }
        });

        runner.onComplete.add(function(_) {
            #if js
            if (untyped js.Syntax.code("typeof process !== 'undefined' && process.exit")) {
                untyped js.Syntax.code("process.exit({0})", hasFailures ? 1 : 0);
            }
            #end
        });

        runner.run();
    }
}
