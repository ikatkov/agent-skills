# Signed-in journeys and bot checks

## Reusing a profile

`--profile <dir>` points the recording at a Chrome user-data directory that survives between
runs, so a provider sign-in completed once is still valid later. Do not point it at your
everyday Chrome profile: Chrome refuses a profile directory another running Chrome holds.
The directory keeps cookies and tokens on disk until you delete it; keep it out of git.

Moving a profile between machines works (copy the whole directory), but it moves the login
with it. Ask before copying someone's profile onto a shared host.

## When a bot check blocks the sign-in itself

`--chrome` plus the blink flag change the browser fingerprint (branded `userAgentData`,
`navigator.webdriver` false, no automation infobar). They do not clear a Cloudflare
interstitial ("Just a moment...", "Performing security verification"), which detects the CDP
session Playwright needs rather than the browser build. Measured on claude.ai from a Mac: the
challenge loops forever with a fresh Ray ID each time. The same site loaded without a
challenge from a Vercel sandbox, so try first and only fall back when blocked.

Sign in once in a Chrome that Playwright never touches, into the same profile directory:

```bash
node scripts/record-flow.mjs https://claude.ai/ --profile .context/chrome-profile --sign-in
```

That opens a plain Chrome, records nothing, and waits. Clear the check, sign in, then quit
Chrome entirely (Cmd+Q on macOS). Quitting matters: Chrome holds cookies in memory and writes
them on exit. Then record against the same profile.

`CHROME_PATH` overrides the Chrome binary when it is not at the platform default.

## On a shared desktop (cloud sandbox with Xvnc)

The recorder's window shows on the desktop, so a human can complete a sign-in in the recorded
session itself while the agent waits, then tell the agent to continue. The sign-in steps
become part of the log; delete those screenshots afterwards if they must not be shared.

Neither flag defeats a determined bot check. TLS and HTTP/2 fingerprints, IP reputation, and
behavioural signals are untouched.
