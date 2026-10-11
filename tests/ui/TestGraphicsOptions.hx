package tests.ui;

import utest.Test;
import utest.Assert;
import ui.FontManager;
import ui.views.options.GraphicsOptionsPanel;
import save.SaveSystem;

/**
 * Unit test suite validating dependent option disabling, grayed out states,
 * and cycle locking in GraphicsOptionsPanel.
 */
class TestGraphicsOptions extends Test {
    var panel:GraphicsOptionsPanel;

    public function setup() {
        FontManager.init();
        new audio.AudioManager();
        var s = SaveSystem.getDefaultGraphics();
        panel = new GraphicsOptionsPanel(s, null);
    }

    public function testShadowBufferDependency() {
        // By default, shadowLevel is "Normal", so shadowRes (idx 2) is enabled
        Assert.isFalse(panel.isOptionDisabled(2), "Shadow Buffer should be enabled when shadows are Normal");

        // Turn shadows Off
        panel.settings.shadowLevel = "Off";
        Assert.isTrue(panel.isOptionDisabled(2), "Shadow Buffer should be disabled when Shadow Quality is Off");

        // Attempting to cycle option 2 should be rejected
        var oldRes = panel.settings.shadowRes;
        panel.cycleOption(2, 1);
        Assert.equals(oldRes, panel.settings.shadowRes, "Disabled Shadow Buffer must not cycle");

        // Turn shadows back on
        panel.settings.shadowLevel = "High";
        Assert.isFalse(panel.isOptionDisabled(2), "Shadow Buffer should re-enable when shadows are High");
        panel.cycleOption(2, 1);
        Assert.isTrue(panel.settings.shadowRes != oldRes, "Enabled Shadow Buffer can cycle");
    }

    public function testAnisotropyMipmappingDependency() {
        // By default, mipmapping is true, so anisotropic (idx 6) is enabled
        Assert.isFalse(panel.isOptionDisabled(6));

        // Disable mipmapping
        panel.settings.mipmapping = false;
        Assert.isTrue(panel.isOptionDisabled(6), "Anisotropy must be disabled when Mipmapping is off");

        var oldAniso = panel.settings.anisotropic;
        panel.cycleOption(6, 1);
        Assert.equals(oldAniso, panel.settings.anisotropic, "Disabled Anisotropy must not cycle");

        panel.settings.mipmapping = true;
        Assert.isFalse(panel.isOptionDisabled(6));
    }

    public function testAAMultiplierDependency() {
        // By default, aaType is "FXAA", so aaLevel (idx 8) is enabled
        Assert.isFalse(panel.isOptionDisabled(8));

        panel.settings.aaType = "None";
        Assert.isTrue(panel.isOptionDisabled(8), "AA Multiplier must be disabled when Anti-Aliasing is None");

        var oldAALevel = panel.settings.aaLevel;
        panel.cycleOption(8, 1);
        Assert.equals(oldAALevel, panel.settings.aaLevel, "Disabled AA Multiplier must not cycle");

        panel.settings.aaType = "MSAA";
        Assert.isFalse(panel.isOptionDisabled(8));
    }

    public function testReflectionLevelDependency() {
        // By default, modelReflections is true, so reflectionLevel (idx 11) is enabled
        Assert.isFalse(panel.isOptionDisabled(11));

        panel.settings.modelReflections = false;
        Assert.isTrue(panel.isOptionDisabled(11), "Reflection Updates must be disabled when Screen Reflections are disabled");

        var oldRefl = panel.settings.reflectionLevel;
        panel.cycleOption(11, 1);
        Assert.equals(oldRefl, panel.settings.reflectionLevel, "Disabled Reflection Updates must not cycle");

        panel.settings.modelReflections = true;
        Assert.isFalse(panel.isOptionDisabled(11));
    }

    public function testUpdateStylesReflectsDisabledState() {
        panel.settings.shadowLevel = "Off";
        panel.settings.mipmapping = false;
        panel.settings.aaType = "None";
        panel.settings.modelReflections = false;

        panel.updateStyles();

        // Check text label contains "[DISABLED]"
        Assert.isTrue(panel.items[2].text.indexOf("[DISABLED]") > 0, "Row 2 text must indicate [DISABLED]");
        Assert.isTrue(panel.items[6].text.indexOf("[DISABLED]") > 0, "Row 6 text must indicate [DISABLED]");
        Assert.isTrue(panel.items[8].text.indexOf("[DISABLED]") > 0, "Row 8 text must indicate [DISABLED]");
        Assert.isTrue(panel.items[11].text.indexOf("[DISABLED]") > 0, "Row 11 text must indicate [DISABLED]");
    }
}

