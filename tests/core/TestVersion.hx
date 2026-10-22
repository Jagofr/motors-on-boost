package tests.core;

import utest.Test;
import utest.Assert;
import Version;

/**
 * Unit test suite validating semantic versioning, build counters, and display strings.
 */
class TestVersion extends Test {
    public function testVersionComponents() {
        Assert.equals("0.4.1", Version.NUMBER);
        Assert.isTrue(Version.BUILD >= 1);
        Assert.equals("0007", Version.BUILD_STRING);
        Assert.equals("Alpha", Version.CHANNEL);
        Assert.isTrue(Version.BUILD_DATE.length > 0);
    }

    public function testDisplayString() {
        Assert.isTrue(Version.DISPLAY.indexOf("v0.4.1") == 0);
        Assert.isTrue(Version.DISPLAY.indexOf("Build 0007") > 0);
    }

    public function testShortString() {
        Assert.equals("v0.4.1", Version.SHORT);
    }
}

