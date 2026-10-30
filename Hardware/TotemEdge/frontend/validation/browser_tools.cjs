/* Shared tooling for the existing browser smokes. No product dependency. */
const path = require('node:path');
const fs = require('node:fs');
const repo = path.resolve(__dirname, '../../../..');
const { chromium } = require(process.env.PLAYWRIGHT_MODULE ||
  path.join(repo, 'Software/apps/admin_web/node_modules/playwright'));
const edge = 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe';
const executablePath = process.env.BROWSER_EXECUTABLE ||
  (process.platform === 'win32' && fs.existsSync(edge) ? edge : undefined);
module.exports = { chromium, launchOptions: { headless: true, ...(executablePath ? { executablePath } : {}) } };
