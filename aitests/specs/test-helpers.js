const path = require('path');
const fs = require('fs');

function getScreenshotDir(testInfo) {
  const dir = testInfo && testInfo.project && testInfo.project.name === 'gh-pages'
    ? path.resolve(__dirname, '..', 'test-results', 'gh-pages-screenshots')
    : path.resolve(__dirname, '..', 'screenshots');
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
  }
  return dir;
}

/**
 * Navigates to the game entry URL (`./`) and safely waits across any automatic
 * one-time Service Worker Cross-Origin Isolation reload (used on static GitHub Pages).
 */
async function gotoGame(page, targetPath = './') {
  await page.goto(targetPath, { waitUntil: 'domcontentloaded' });
  for (let i = 0; i < 80; i++) {
    try {
      const snap = await page.evaluate(() => ({
        coi: Boolean(window.crossOriginIsolated),
        pendingReload: Boolean(window.__mobPendingCoiReload),
        hasBridge: Boolean(window.MOBWebBridge && window.MOBWebBridge.debug().lastStateSeq > 0)
      }));
      if (snap.coi && snap.hasBridge) {
        return;
      }
      if (snap.pendingReload) {
        await page.waitForLoadState('domcontentloaded').catch(() => {});
      }
    } catch (_) {
      // Expected transient error when the 1-time COI reload navigates the frame
    }
    await page.waitForTimeout(150);
  }
  await page.waitForFunction(
    () => Boolean(window.crossOriginIsolated && window.MOBWebBridge && window.MOBWebBridge.debug().lastStateSeq > 0),
    { timeout: 15000 }
  );
}

module.exports = {
  getScreenshotDir,
  gotoGame
};
