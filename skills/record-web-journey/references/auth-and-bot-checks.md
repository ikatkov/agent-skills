# Signed-in journeys and bot checks

## Reusing a profile

`--profile <dir>` points the recording at a Chrome user-data directory that survives between
runs, so a provider sign-in completed once is still valid later. Use a dedicated profile on
the browser host, close its Chrome process between runs, and keep its cookies and tokens
protected and out of git. The sign-in and recordings then share one host-local browser state.

## When a bot check blocks the sign-in itself

`--chrome` plus the blink flag provide branded `userAgentData`, `navigator.webdriver` false,
and a browser without the automation infobar. A Cloudflare interstitial such as "Just a
moment..." or "Performing security verification" may still detect the CDP session Playwright
needs. Measured on claude.ai from a Mac, that challenge looped with a fresh Ray ID each time,
while the same site loaded directly from a Vercel sandbox. Try the recording first, then use
the interactive sign-in path when the interstitial persists.

Sign in once in plain Chrome before Playwright attaches, using the same profile directory:

```bash
node "$RECORDER" https://claude.ai/ --profile .context/chrome-profile --sign-in
```

That opens plain Chrome for the interactive check and sign-in. Quit Chrome entirely afterward
(Cmd+Q on macOS) so it writes current cookies to disk, then record against the same profile.

`CHROME_PATH` overrides the Chrome binary when it is not at the platform default.

## On a shared desktop (cloud sandbox with Xvnc)

The recorder's window shows on the desktop, so a human can complete a sign-in in the recorded
session itself while the agent waits, then tell the agent to continue. The sign-in steps
become part of the host-local recording, including its screenshots. Choose an output directory
whose access matches the sensitivity of the visible session.

Bot checks may also use TLS and HTTP/2 fingerprints, IP reputation, and behavioural signals.
An interactive same-host sign-in provides the reliable handoff when those checks persist.
