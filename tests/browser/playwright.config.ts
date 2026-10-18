import { defineConfig } from '@playwright/test';

const baseURL = process.env.GXA_SYSTEM_BASE?.replace(/\/$/, '');

export default defineConfig({
  testDir: './scenarios',
  fullyParallel: false,
  workers: 1,
  timeout: 180_000,
  reporter: [
    ['html', { outputFolder: '../../reports/playwright-report', open: 'never' }],
    ['junit', { outputFile: '../../reports/browser-junit.xml' }],
  ],
  outputDir: '../../reports/playwright-output',
  use: {
    baseURL,
    browserName: 'chromium',
    trace: 'on',
    screenshot: 'on',
    navigationTimeout: 120_000,
    actionTimeout: 30_000,
  },
});
