const { defineConfig } = require('@playwright/test');
const path = require('path');

const LAUNCH_OPTIONS = {
  args: [
    ...(process.platform === 'win32' ? ['--use-webgpu-adapter=d3d11'] : ['--use-gl=angle']),
    '--enable-unsafe-webgpu'
  ]
};

const customUrl = process.env.MOB_TEST_URL;

module.exports = defineConfig({
  testDir: path.join(__dirname, 'specs'),
  outputDir: path.join(__dirname, 'test-results'),
  timeout: 60000,
  fullyParallel: false,
  workers: 1,
  reporter: [['list']],
  use: {
    viewport: { width: 1280, height: 720 },
    headless: true,
    channel: 'msedge',
    launchOptions: LAUNCH_OPTIONS
  },
  projects: customUrl
    ? [
        {
          name: 'custom',
          use: { baseURL: customUrl }
        }
      ]
    : [
        {
          name: 'iis',
          use: { baseURL: 'http://127.0.0.1:7725/' }
        },
        {
          name: 'gh-pages',
          use: { baseURL: 'http://127.0.0.1:7726/motors-on-boost/' }
        }
      ],
  webServer: customUrl
    ? undefined
    : [
        {
          command: 'node server.js --mode=iis --port=7725',
          url: 'http://127.0.0.1:7725/mob-env.js',
          cwd: __dirname,
          reuseExistingServer: false,
          timeout: 15000
        },
        {
          command: 'node server.js --mode=gh-pages --port=7726 --base-path=/motors-on-boost',
          url: 'http://127.0.0.1:7726/motors-on-boost/mob-env.js',
          cwd: __dirname,
          reuseExistingServer: false,
          timeout: 15000
        }
      ]
});
