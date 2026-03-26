#!/usr/bin/env node
/**
 * test-all.js -- Runs all test suites: unit, e2e, and build/codegen.
 *
 * Usage: npm run test:all
 *
 * - Unit tests: always run
 * - E2E tests: run if dev server is up on the derived port, skipped with warning otherwise
 * - Build/codegen tests: run if prerequisites are met, skipped with warning otherwise
 *
 * CONFIGURE: Replace the {{PLACEHOLDER}} values below with your project's commands.
 */
import { execSync, spawnSync } from 'node:child_process';
import { createConnection } from 'node:net';
import { getPort } from './port.js';

// ─── CONFIGURE: set your test commands ───────────────────────────────
const UNIT_TEST_CMD = '{{UNIT_TEST_CMD}}';
const E2E_TEST_CMD = '{{E2E_TEST_CMD}}';
const BUILD_TEST_CMD = '{{BUILD_TEST_CMD}}';

const BOLD = '\x1b[1m';
const GREEN = '\x1b[32m';
const YELLOW = '\x1b[33m';
const RED = '\x1b[31m';
const RESET = '\x1b[0m';

function header(label) {
  console.log(`\n${BOLD}${'='.repeat(60)}${RESET}`);
  console.log(`${BOLD}  ${label}${RESET}`);
  console.log(`${BOLD}${'='.repeat(60)}${RESET}\n`);
}

function run(label, cmd, opts = {}) {
  header(label);
  const result = spawnSync('sh', ['-c', cmd], {
    stdio: 'inherit',
    timeout: opts.timeout || 600_000,
  });
  return result.status === 0;
}

function checkPort(port) {
  return new Promise((resolve) => {
    const sock = createConnection({ port, host: '127.0.0.1' }, () => {
      sock.destroy();
      resolve(true);
    });
    sock.on('error', () => resolve(false));
    sock.setTimeout(1000, () => { sock.destroy(); resolve(false); });
  });
}

function hasBuildPrerequisite() {
  // CONFIGURE: check for your build test prerequisite (e.g., cargo --version)
  // Return true if the prerequisite is available, false otherwise.
  try {
    execSync('cargo --version', { stdio: 'ignore' });
    return true;
  } catch { return false; }
}

/**
 * Check if any changed files (staged + unstaged) are source files that
 * E2E tests would cover. Returns the list of matching files, or null.
 * This prevents agents from skipping E2E when they've changed source code.
 */
function hasChangedSourceFiles() {
  try {
    const staged = execSync('git diff --cached --name-only 2>/dev/null', { encoding: 'utf8' });
    const unstaged = execSync('git diff --name-only 2>/dev/null', { encoding: 'utf8' });
    const allChanged = [...new Set([...staged.split('\n'), ...unstaged.split('\n')])]
      .filter(f => f.length > 0);

    const sourceFiles = allChanged.filter(f =>
      (f.startsWith('src/') || f.startsWith('tests/e2e/')) &&
      (f.endsWith('.js') || f.endsWith('.css') || f.endsWith('.html'))
    );

    return sourceFiles.length > 0 ? sourceFiles : null;
  } catch {
    // Not in a git repo or git not available -- allow skip
    return null;
  }
}

// -- Main --

const results = [];

// 1. Unit + integration tests (always)
const unitOk = run(
  `Unit + Integration Tests (${UNIT_TEST_CMD})`,
  UNIT_TEST_CMD,
  { timeout: 300_000 }
);
results.push({ name: 'Unit/integration', ok: unitOk });

// 2. E2E tests (if dev server is up)
const port = getPort();
const serverUp = await checkPort(port);
if (serverUp) {
  const e2eOk = run(
    `E2E Tests (${E2E_TEST_CMD})`,
    E2E_TEST_CMD,
    { timeout: 600_000 }
  );
  results.push({ name: 'E2E', ok: e2eOk });
} else {
  header(`E2E Tests (${E2E_TEST_CMD})`);
  // Check if changed files would be covered by E2E tests
  const e2eRelevant = hasChangedSourceFiles();
  if (e2eRelevant) {
    console.log(`${RED}x FAILED -- dev server not running on port ${port}, but source files changed:${RESET}`);
    console.log(`  ${e2eRelevant.join(', ')}`);
    console.log(`\n  E2E tests cannot be skipped when src/ files are modified.`);
    console.log(`  Start the dev server and re-run tests.\n`);
    results.push({ name: 'E2E', ok: false });
  } else {
    console.log(`${YELLOW}! SKIPPED -- dev server not running on port ${port} (no source files changed)${RESET}`);
    console.log(`  Start the dev server to enable E2E tests.\n`);
    results.push({ name: 'E2E', ok: null, skipped: true });
  }
}

// 3. Build/codegen tests (if prerequisites are met)
if (hasBuildPrerequisite()) {
  const buildOk = run(
    `Build/Codegen Tests (${BUILD_TEST_CMD})`,
    BUILD_TEST_CMD,
    { timeout: 600_000 }
  );
  results.push({ name: 'Build/codegen', ok: buildOk });
} else {
  header(`Build/Codegen Tests (${BUILD_TEST_CMD})`);
  console.log(`${YELLOW}! SKIPPED -- build prerequisite not available${RESET}\n`);
  results.push({ name: 'Build/codegen', ok: null, skipped: true });
}

// -- Summary --

header('Summary');

let allPassed = true;
for (const r of results) {
  if (r.skipped) {
    console.log(`  ${YELLOW}! ${r.name}: SKIPPED${RESET}`);
  } else if (r.ok) {
    console.log(`  ${GREEN}v ${r.name}: PASSED${RESET}`);
  } else {
    console.log(`  ${RED}x ${r.name}: FAILED${RESET}`);
    allPassed = false;
  }
}

const skipped = results.filter(r => r.skipped);
if (skipped.length > 0) {
  console.log(`\n${YELLOW}  ${skipped.length} suite(s) skipped -- see above for how to enable them.${RESET}`);
}

console.log('');
process.exit(allPassed ? 0 : 1);
