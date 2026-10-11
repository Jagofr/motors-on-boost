package;

import utest.Runner;
import utest.ITest;
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
 * Compatible with CLI execution, Headless Node.js, and VSCode Haxe Test Explorer plugin.
 * Supports filtering by module name (e.g. 'physics', 'camera') or specific test class name.
 */
class TestMain {
    /**
     * Entry point for test compilation target.
     * Sets up headless WebGL texture stubs, parses filtering flags, and runs selected suites.
     */
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

        var filters:Array<String> = [];
        var runner = new Runner();

        #if js
        if (untyped js.Syntax.code("typeof process !== 'undefined' && process.env && process.env.TEST_FILTER")) {
            var envFilter:String = untyped js.Syntax.code("process.env.TEST_FILTER");
            for (p in envFilter.split(",")) {
                var trimmed = StringTools.trim(p).toLowerCase();
                if (trimmed.length > 0) filters.push(trimmed);
            }
        }

        if (untyped js.Syntax.code("typeof process !== 'undefined' && process.argv")) {
            var rawArgs:Array<String> = untyped js.Syntax.code("process.argv.slice(2)");
            for (arg in rawArgs) {
                if (arg != null && !StringTools.startsWith(arg, "-")) {
                    for (p in arg.split(",")) {
                        var trimmed = StringTools.trim(p).toLowerCase();
                        if (trimmed.length > 0) filters.push(trimmed);
                    }
                }
            }
        }
        #end

        function shouldRun(moduleName:String, className:String):Bool {
            if (filters.length == 0 || filters.indexOf("all") != -1) return true;
            var modLower = moduleName.toLowerCase();
            var classLower = className.toLowerCase();
            for (f in filters) {
                if (classLower.indexOf(f) != -1) return true;
                if (modLower == f || modLower.indexOf(f) != -1) return true;
            }
            return false;
        }

        var cases:Array<{mod:String, name:String, testCase:utest.ITest}> = [
            { mod: "core", name: "TestVersion", testCase: new TestVersion() },
            { mod: "physics", name: "TestSplineMath", testCase: new TestSplineMath() },
            { mod: "physics", name: "TestCarConfig", testCase: new TestCarConfig() },
            { mod: "physics", name: "TestCarPhysics", testCase: new TestCarPhysics() },
            { mod: "save", name: "TestSaveSystem", testCase: new TestSaveSystem() },
            { mod: "input", name: "TestInputController", testCase: new TestInputController() },
            { mod: "world", name: "TestTrack", testCase: new TestTrack() },
            { mod: "entities", name: "TestTrafficSystem", testCase: new TestTrafficSystem() },
            { mod: "camera", name: "TestChaseCamera", testCase: new TestChaseCamera() },
            { mod: "ui", name: "TestGraphicsOptions", testCase: new TestGraphicsOptions() },
            { mod: "ui", name: "TestTouchControls", testCase: new TestTouchControls() },
            { mod: "audio", name: "TestAudioManager", testCase: new TestAudioManager() }
        ];

        var countAdded = 0;
        for (c in cases) {
            if (shouldRun(c.mod, c.name)) {
                runner.addCase(c.testCase);
                countAdded++;
            }
        }

        if (countAdded == 0) {
            #if js
            untyped console.log('[TestMain] No test suites matched filter: [' + filters.join(", ") + ']. Available modules: core, physics, save, input, world, entities, camera, ui, audio.');
            if (untyped js.Syntax.code("typeof process !== 'undefined' && process.exit")) {
                untyped js.Syntax.code("process.exit(0)");
            }
            #end
            return;
        } else if (filters.length > 0) {
            #if js
            untyped console.log('[TestMain] Running ' + countAdded + ' test suite(s) matching filter: [' + filters.join(", ") + ']');
            #end
        }

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
