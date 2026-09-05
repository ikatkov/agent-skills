#!/usr/bin/env node
// Records a browser journey: a WebM video, a screenshot after every click and page load with a
// red marker at the click point, and a steps.md log. Two drivers share one code path:
//   human: a person uses the window; the recording ends on Enter in the terminal.
//   agent: `--cdp <port>` exposes the same Chrome so an agent drives it with
//          `agent-browser --cdp <port>`; the recording ends when <recordingDir>/STOP appears.
// Clicks dispatched over CDP are trusted events, so the in-page listener sees both the same way.

import { spawn } from 'node:child_process';
import { access, appendFile, mkdir, readdir, writeFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const scriptDir = dirname(fileURLToPath(import.meta.url));
const require = createRequire(import.meta.url);
let chromium;
try {
  ({ chromium } = require('playwright'));
} catch {
  console.error(`playwright is not installed next to this script. Run:\n  ${resolve(scriptDir, 'setup.sh')}`);
  process.exit(1);
}

const usage = `Usage:
  node record-flow.mjs <url> [-name "Recording name"] [--chrome] [--profile dir] [--out dir]
                       [--cdp port] [--headless] [--viewport WxH]
  node record-flow.mjs <url> --profile dir --sign-in

Options:
  -name, --name, -n   Prefix the output folder with a human-readable name
  --chrome            Use the installed Google Chrome instead of Playwright's Chromium
  --profile, -p       Reuse a browser profile directory across recordings, keeping logins
  --out               Parent directory for recordings (default: .context/flow-recordings)
  --cdp <port>        Expose a CDP port so an agent can drive the browser (agent-browser --cdp)
  --headless          No window (for hosts without a display); video and screenshots still work
  --viewport WxH      Viewport and video size (default: 1440x900)
  --sign-in           Open the profile in a plain Chrome to sign in past a bot check, then exit
  -h, --help          Show this help

Ending a recording: press Enter in this terminal, close the browser, send SIGTERM, or
create the file <recordingDir>/STOP (agents use this).`;

const opts = parseCliArgs(process.argv.slice(2));
const parsedUrl = new URL(opts.requestedUrl);

if (opts.signInOnly) {
  if (!opts.profileDir) throw new Error(`--sign-in needs --profile: a sign-in only survives in a reused profile.\n\n${usage}`);
  await runSignIn(opts.profileDir, parsedUrl.toString());
  process.exit(0);
}

const timestamp = new Date().toISOString().replaceAll(':', '-').replaceAll('.', '-');
const folder = opts.recordingName ? `${safeFolderPrefix(opts.recordingName)}-${timestamp}` : timestamp;
const recordingDir = resolve(opts.outDir, folder);
const screenshotDir = resolve(recordingDir, 'screenshots');
const videoDir = resolve(recordingDir, 'videos');
const stepsPath = resolve(recordingDir, 'steps.md');
const stopPath = resolve(recordingDir, 'STOP');

await Promise.all([mkdir(screenshotDir, { recursive: true }), mkdir(videoDir, { recursive: true })]);
await writeFile(
  stepsPath,
  [
    `# ${opts.recordingName ? `${opts.recordingName} — ` : ''}User-flow recording`,
    '',
    ...(opts.recordingName ? [`- Name: ${opts.recordingName}`] : []),
    `- Started: ${new Date().toISOString()}`,
    `- Start URL: ${redactUrl(parsedUrl.toString())}`,
    `- Browser: ${opts.useRealChrome ? 'installed Google Chrome' : "Playwright's Chromium"}${opts.headless ? ' (headless)' : ''}`,
    `- Driver: ${opts.cdpPort ? `agent over CDP port ${opts.cdpPort}` : 'human'}`,
    `- Profile: ${opts.profileDir ? `reused (${opts.profileDir})` : 'ephemeral'}`,
    '',
    'The screenshots show the viewport shortly after each click or page load.',
    'Typed field values are intentionally omitted from this log.',
    '',
    '## Steps',
    '',
  ].join('\n'),
);

let step = 0;
let captureQueue = Promise.resolve();

function parseCliArgs(args) {
  const out = {
    requestedUrl: 'http://localhost:3000',
    recordingName: undefined,
    useRealChrome: false,
    profileDir: undefined,
    outDir: resolve('.context', 'flow-recordings'),
    cdpPort: undefined,
    headless: false,
    viewport: { width: 1440, height: 900 },
    signInOnly: false,
  };
  let hasUrl = false;
  const value = (flag, i) => {
    const v = args[i + 1];
    if (!v || v.startsWith('-')) throw new Error(`${flag} requires a value.\n\n${usage}`);
    return v;
  };
  for (let i = 0; i < args.length; i += 1) {
    const a = args[i];
    if (a === '-h' || a === '--help') { console.log(usage); process.exit(0); }
    if (a === '-name' || a === '--name' || a === '-n') { out.recordingName = value(a, i).trim(); i += 1; continue; }
    if (a.startsWith('--name=')) { out.recordingName = a.slice(7).trim(); continue; }
    if (a === '--chrome') { out.useRealChrome = true; continue; }
    if (a === '--headless') { out.headless = true; continue; }
    if (a === '--sign-in') { out.signInOnly = true; continue; }
    if (a === '--profile' || a === '-p') { out.profileDir = resolve(value(a, i)); i += 1; continue; }
    if (a.startsWith('--profile=')) { out.profileDir = resolve(a.slice(10)); continue; }
    if (a === '--out') { out.outDir = resolve(value(a, i)); i += 1; continue; }
    if (a === '--cdp') { out.cdpPort = Number(value(a, i)); i += 1; continue; }
    if (a === '--viewport') {
      const [w, h] = value(a, i).split('x').map(Number);
      if (!w || !h) throw new Error(`--viewport expects WxH.\n\n${usage}`);
      out.viewport = { width: w, height: h }; i += 1; continue;
    }
    if (a.startsWith('-')) throw new Error(`Unknown option: ${a}\n\n${usage}`);
    if (hasUrl) throw new Error(`Unexpected argument: ${a}\n\n${usage}`);
    out.requestedUrl = a; hasUrl = true;
  }
  if (out.recordingName !== undefined && !out.recordingName) throw new Error(`Recording name cannot be empty.\n\n${usage}`);
  if (out.cdpPort !== undefined && !Number.isInteger(out.cdpPort)) throw new Error(`--cdp expects a port number.\n\n${usage}`);
  return out;
}

function defaultChromePath() {
  if (process.env.CHROME_PATH) return process.env.CHROME_PATH;
  if (process.platform === 'darwin') return '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
  if (process.platform === 'linux') return '/usr/bin/google-chrome';
  throw new Error('Set CHROME_PATH to the Google Chrome binary.');
}

// Cloudflare-style interstitials detect the CDP session Playwright needs, not the browser
// build, so no launch flag clears them. Passing the check in a Chrome that Playwright never
// touches leaves cf_clearance and the login cookie in the profile, and the recording reuses
// them. Chrome only flushes its cookie database on exit, so this waits for a full quit.
async function runSignIn(userDataDir, url) {
  const executable = defaultChromePath();
  try { await access(executable); } catch {
    throw new Error(`Google Chrome not found at ${executable}. Set CHROME_PATH to its binary.`);
  }
  console.log(`\nOpening Google Chrome with no automation attached.\nProfile: ${userDataDir}\n`);
  console.log('Sign in and clear any bot check, then quit Chrome entirely (Cmd+Q on macOS).');
  console.log('Closing only the window loses the session: Chrome writes its cookies on exit.\n');
  const chrome = spawn(executable, [`--user-data-dir=${userDataDir}`, '--no-first-run', '--no-default-browser-check', url], { stdio: 'ignore' });
  const [code, signal] = await new Promise((done) => chrome.once('exit', (c, s) => done([c, s])));
  if (code !== 0) {
    throw new Error(`Chrome exited ${signal ? `on ${signal}` : `with code ${code}`}, so it never flushed its cookies. The profile may hold no usable session.`);
  }
  console.log('Chrome quit. Re-run the same command without --sign-in to record.');
}

function safeFolderPrefix(value) {
  const prefix = value.replaceAll(/[^a-zA-Z0-9._-]+/g, '-').replaceAll(/^-+|-+$/g, '').slice(0, 80);
  if (!prefix) throw new Error('Recording name must contain at least one letter or number.');
  return prefix;
}
function safeSlug(value) {
  const slug = value.toLowerCase().replaceAll(/[^a-z0-9]+/g, '-').replaceAll(/^-|-$/g, '').slice(0, 50);
  return slug || 'page';
}
function redactUrl(value) {
  try { const u = new URL(value); return `${u.origin}${u.pathname}`; } catch { return '[URL unavailable]'; }
}

function queueCapture(page, kind, label) {
  captureQueue = captureQueue.then(async () => {
    if (page.isClosed()) return;
    await page.waitForTimeout(250);
    if (page.isClosed()) return;
    step += 1;
    const fileName = `${String(step).padStart(3, '0')}-${kind}-${safeSlug(label)}.png`;
    try {
      await page.screenshot({ path: resolve(screenshotDir, fileName), fullPage: false });
      await appendFile(
        stepsPath,
        [`${step}. **${kind}** — ${label}`, `   - URL: ${redactUrl(page.url())}`, `   - Screenshot: [${fileName}](screenshots/${fileName})`, ''].join('\n'),
      );
    } catch (error) {
      await appendFile(stepsPath, `${step}. **${kind}** — ${label} (screenshot unavailable: ${String(error)})\n\n`);
    }
  });
  return captureQueue;
}

// An empty user-data directory gives an ephemeral profile, so OAuth cookies are not saved
// beside the artifacts; --profile trades that away for surviving logins. The blink flag
// clears navigator.webdriver, dropping --enable-automation removes the infobar, and
// --remote-debugging-port makes Playwright use that port instead of its pipe, which is what
// lets agent-browser attach to the same Chrome.
const context = await chromium.launchPersistentContext(opts.profileDir ?? '', {
  headless: opts.headless,
  ...(opts.useRealChrome ? { channel: 'chrome' } : {}),
  ignoreDefaultArgs: ['--enable-automation'],
  args: [
    '--disable-blink-features=AutomationControlled',
    '--window-position=0,0',
    ...(opts.cdpPort ? [`--remote-debugging-port=${opts.cdpPort}`] : []),
  ],
  recordVideo: { dir: videoDir, size: opts.viewport },
  viewport: opts.viewport,
});

await context.exposeBinding('__recordManualClick', async ({ page, frame }, event) => {
  if (frame !== page.mainFrame()) return;
  const label = typeof event?.label === 'string' ? event.label : 'unlabelled element';
  await queueCapture(page, 'click', label);
});

await context.addInitScript(() => {
  document.addEventListener(
    'click',
    (event) => {
      const element =
        event.target instanceof Element
          ? event.target.closest('button, a, input, textarea, select, [role], [aria-label], [title]') ?? event.target
          : null;
      if (!element) return;
      // A click on a visually hidden 1x1 input lands on <html>; name the element under the
      // pointer instead of dumping the document's text.
      const named =
        element === document.documentElement || element === document.body
          ? document.elementFromPoint(event.clientX, event.clientY) ?? element
          : element;

      const marker = document.createElement('div');
      Object.assign(marker.style, {
        position: 'fixed', left: `${event.clientX - 12}px`, top: `${event.clientY - 12}px`,
        width: '24px', height: '24px', border: '3px solid #ef4444', borderRadius: '9999px',
        background: 'rgb(239 68 68 / 20%)', boxSizing: 'border-box', pointerEvents: 'none',
        zIndex: '2147483647',
      });
      document.documentElement.append(marker);
      setTimeout(() => marker.remove(), 800);

      const label =
        named.getAttribute('aria-label') || named.getAttribute('title') ||
        (named !== document.documentElement && named !== document.body
          ? named.textContent?.trim().replaceAll(/\s+/g, ' ').slice(0, 100)
          : '') || `${named.tagName.toLowerCase()} (no visible target)`;
      void window.__recordManualClick({ label });
    },
    true,
  );
});

function observePage(page) {
  page.on('load', () => {
    void page.title().catch(() => 'page loaded').then((t) => queueCapture(page, 'load', t || 'page loaded'));
  });
}
context.on('page', observePage);
for (const page of context.pages()) observePage(page);

const page = context.pages()[0] ?? (await context.newPage());
await page.goto(parsedUrl.toString());

console.log(`\nRecording to:\n${recordingDir}\n`);
if (opts.cdpPort) {
  await writeFile(resolve(recordingDir, 'cdp-port'), String(opts.cdpPort));
  console.log(`CDP port: ${opts.cdpPort}`);
  console.log(`Drive it with:  agent-browser --session <unique> --cdp ${opts.cdpPort} ...`);
}
console.log(`Finish with:    touch ${stopPath}${process.stdin.isTTY ? '  (or press Enter here)' : ''}`);
console.log('Closing the browser also ends the recording.\n');

const finishers = [
  new Promise((done) => { const t = setInterval(() => access(stopPath).then(() => { clearInterval(t); done('stop-file'); }, () => {}), 500); }),
  new Promise((done) => context.once('close', () => done('browser'))),
  new Promise((done) => { for (const s of ['SIGINT', 'SIGTERM']) process.once(s, () => done(s)); }),
];
if (process.stdin.isTTY) {
  process.stdin.resume();
  process.stdin.setEncoding('utf8');
  finishers.push(new Promise((done) => process.stdin.once('data', () => done('enter'))));
}
const finishReason = await Promise.race(finishers);
console.log(`Finishing (${finishReason})...`);
await captureQueue;
if (finishReason !== 'browser') await context.close();

const videos = (await readdir(videoDir)).filter((n) => n.endsWith('.webm')).sort();
await appendFile(
  stepsPath,
  ['## Video files', '', ...(videos.length ? videos.map((n) => `- [${n}](videos/${n})`) : ['- No video file was produced. End the next session with Enter or STOP so Playwright can finalize it.']), ''].join('\n'),
);
console.log(`\nSaved ${step} visual steps and ${videos.length} video file(s).\n${recordingDir}\n`);
process.exit(0);
