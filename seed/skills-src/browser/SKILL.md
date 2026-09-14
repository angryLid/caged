---
name: browser
description: Drive a browser from pi — read JS-heavy pages, screenshot, fill forms, test local dev servers. Uses Playwright scripts against a lazily-started headless Chromium in the container (default) or the host's Chrome over CDP (host mode). Use for any task needing a real browser beyond plain HTTP fetching.
---

# Browser

caged ships a Playwright-based browser layer (see `docs/BROWSER.md` for the
design). There is no browser MCP server and no per-action tool round-trips:
**the browser is a library, and you drive it by writing and running
scripts.** One script can perform a dozen browser actions for the cost of one
model turn, and its output — not the page's whole state — is what enters the
conversation.

## Two modes

| | `local` (default) | `host` (`BROWSER_MODE=host`) |
|---|---|---|
| Browser | disposable headless Chromium in the container, started lazily by `browserd` | the host's Chrome, attached over CDP via `devtools-forward.js` |
| State | profile under `/tmp/caged-browser` — persists while the container runs, **dies with the container** | the host Chrome's throwaway profile (`.caged-chrome-devtools`) |
| Reaches | the internet, `/workspace` files | host `localhost` dev servers, VPN/intranet |

Use local mode unless the target only exists on the host network. If host
mode fails because no debug Chrome is listening, ask the user to run
`cg browser start` on the host — do not stay stuck retrying.

Note: the browser layer exists only in the pi / pi-web-ui images. On the dsh
or Command Code images these commands fail with a missing `playwright` module
— that is expected, not a bug.

## Quick helpers

`seed/.pi/agent/scripts/browser` covers the common one-shot cases (run from
`/workspace`, output files land in the project):

```sh
browser open  https://example.com                 # title + final URL + readable text
browser open  https://example.com --chars=3000    # cap the text length
browser shot  https://example.com shot.png        # viewport screenshot (1280x720)
browser shot  https://example.com full.png --full # full-page screenshot
browser pdf   https://example.com page.pdf        # render to PDF (local mode only)
browser eval  https://example.com 'document.querySelectorAll("h2").length'
browser cdp                                      # print the CDP endpoint only
```

All commands accept `--timeout=ms`. Host mode: prefix with
`BROWSER_MODE=host browser ...`.

## Custom scripts (the real interface)

For anything multi-step — logins, forms, waiting on a selector, extracting
structured data — write a Node script and run it with bash. Template:

```js
const { chromium } = require("playwright");

async function main() {
  // local (default): attach to the lazily-started headless Chromium
  const endpoint = require("child_process")
    .execFileSync(process.execPath, [`${process.env.HOME}/.pi/agent/scripts/browserd`, "ensure"])
    .toString().trim();
  // host mode instead: const endpoint = "http://127.0.0.1:19222";
  const browser = await chromium.connectOverCDP(endpoint);
  const context = browser.contexts()[0] || (await browser.newContext());
  const page = await context.newPage();

  await page.goto("https://example.com", { waitUntil: "load" });
  await page.getByRole("searchbox").fill("caged");
  await page.keyboard.press("Enter");
  await page.waitForSelector(".results");
  console.log(await page.locator(".results").allInnerTexts());

  await page.close(); // close your tab; the browser itself stays up
}
  // the CDP connection keeps Node's event loop alive — exit explicitly when done
  main().then(() => process.exit(0)).catch((err) => { console.error(err.message); process.exit(1); });
```

Rules that keep this cheap and reliable:

- `require("playwright")` works from any cwd (`NODE_PATH` is set in the image).
- Attach via `connectOverCDP`; never `chromium.launch()` a second browser —
  the persistent one holds your cookies and login state.
- Attach once per script, `page.close()` per tab. The browser process stays
  alive between scripts and between turns. End custom scripts with an explicit
  `process.exit(0)` — the open CDP connection keeps the event loop alive and
  the script would otherwise hang after printing its output.
- Print only what matters: extracted values, assertions, final state. Never
  dump `page.content()` wholesale — that is the context overflow the MCP path
  suffered from.
- Prefer locators with auto-waiting (`getByRole`, `getByText`,
  `waitForSelector`) over blind sleeps.
- Iterate like any code: run, read the error, fix, rerun. If a selector
  fails, `browser eval <url> 'document.body.innerHTML.slice(0, 2000)'` beats
  guessing.

## Managing the browser

```sh
~/.pi/agent/scripts/browserd status   # running? endpoint? pid?
~/.pi/agent/scripts/browserd stop     # kill it (next use starts fresh — state is disposable)
cat /tmp/caged-browser/chromium.log   # chromium's own stderr
```

If pages render oddly, stopping and letting `browserd` respawn usually fixes
it. If the container runs out of memory under heavy browsing, ask the user to
restart with `CAGED_MEMORY=4g cg pi start`.

## Host mode setup (user-side, on the host)

```sh
cg browser start    # debug Chrome (throwaway profile) + CDP bridge
cg browser status   # check reachability
cg browser stop     # stop bridge and debug Chrome
```

`cg browser start` launches Chrome with `--remote-debugging-port=9222` and
bridges it to the vmnet gateway (192.168.64.1) so the container can attach.
Chrome 136+ refuses remote debugging on the default profile, hence the
throwaway `--user-data-dir` — host mode never sees your real logins either.
