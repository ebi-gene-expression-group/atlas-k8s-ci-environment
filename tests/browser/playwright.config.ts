import path from 'path';
import dotenv from 'dotenv';
import { defineConfig } from '@playwright/test';

dotenv.config({ path: path.resolve(__dirname, '../../.env'), quiet: true });

const baseURL = process.env.GXA_SYSTEM_BASE?.replace(/\/$/, '');

const systemBaseLabel = `GXA_SYSTEM_BASE: ${baseURL || '(unset)'}`;

export default defineConfig({
  testDir: './scenarios',
  testMatch: '**/*.spec.ts',
  fullyParallel: false,
  workers: 1,
  timeout: 180_000,
  reporter: [
    ['html', { outputFolder: '../../reports/playwright-report', open: 'never', title: systemBaseLabel }],
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
