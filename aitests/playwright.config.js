const { defineConfig } = require('@playwright/test');
const path = require('path');

module.exports = defineConfig({
  testDir: path.join(__dirname, 'specs'),
  outputDir: path.join(__dirname, 'test-results'),
  timeout: 60000,
  fullyParallel: false,
  workers: 1,
  reporter: [['list']],
  use: {
    baseURL: process.env.MOB_TEST_URL || 'http://127.0.0.1:7725',
    viewport: { width: 1280, height: 720 },
    headless: true,
    channel: 'msedge',
    launchOptions: {
      args: [
        ...(process.platform === 'win32' ? ['--use-webgpu-adapter=d3d11'] : ['--use-gl=angle']),
        '--enable-unsafe-webgpu'
      ]
    }
  },
  webServer: process.env.MOB_TEST_URL ? undefined : {
    command: 'node server.js',
    port: 7725,
    cwd: __dirname,
    reuseExistingServer: true,
    timeout: 15000
  }
});

