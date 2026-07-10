# ClaudeShot delivery & accessibility audit (July 2026)

A three-angle audit of the capture → deliver → paste pipeline, run as three
independent reviews (AX/injection, capture/concurrency, UI/UX + architecture)
whose findings were then cross-checked against each other. This document
records the root causes of the two reported bugs, the consensus verdicts,
what was fixed, and what remains recommended.

## The two reported bugs — root causes

### Bug 1: shot goes only to the clipboard when Claude already has 5 images

Claude Desktop accepts at most 5 images per message. When the composer is
full, the synthesized ⌘V is silently ignored by Claude's renderer — but
ClaudeShot played the capture sound and the "Sent to Claude" animation
anyway. Delivery was unconditional (`AppshotController` called
`injector.deliver(...)` fire-and-forget, returning `Void`), the
`AppSettings.maxImages = 5` constant was dead code, and the old
`warn.limit` string revealed an abandoned *local counter* design — which
would have desynced the moment the user removed an attachment or sent the
message by hand.

### Bug 2: image doesn't attach when Claude's input box isn't focused

Three compounding failure modes in `ClaudeInjector`:

1. **"Pasting anyway":** when composer focus could not be acquired, the code
   logged `couldn't focus a text input; pasting anyway` and posted ⌘V
   regardless. In Electron, ⌘V with no focused editable element is a no-op —
   the exact reported symptom.
2. **`CGEvent.postToPid` fallback:** when macOS refused to bring Claude
   frontmost, ⌘V was posted directly to the pid. Chromium's key pipeline
   expects events via the window server to its key window; pid-posted key
   events into a background Electron process are dropped silently most of
   the time. A second invisible-failure path presented as a safety net.
3. **Fragile click fallback:** the synthetic click at the composer's
   coordinates was not hit-tested (it could land on a window covering that
   point) and the cursor was warped back *immediately* after posting the
   up-event, which Chromium can interpret as a cancelled press.

Both bugs share one structural cause: **no verification and no feedback**.
The app never observed whether an attachment actually appeared, so every
failure looked identical to success.

## Verdict on the "old accessibility API" question

The `AXUIElement` C API is still *the* (and the only) public API for
cross-app control on macOS — the API choice was not outdated. What was
dated or missing in its usage:

- **No `AXUIElementSetMessagingTimeout`** — every AX call carries a ~6 s
  default timeout; a busy Claude renderer could stall the (up to 2500-call)
  tree walk on the main actor for a very long time. Now capped at 0.25 s.
- **`AXEnhancedUserInterface`** — the legacy Electron wake-up flag, with
  known side effects on Chromium window geometry (breaks window
  moves/resizes by window managers). Removed; the modern
  `AXManualAccessibility` flag is kept.
- Carbon `RegisterEventHotKey` (hotkey path) looks old but remains the
  sanctioned, non-deprecated API for global hotkeys — left as is.
- Missing `AXObserver`-based waiting (polling with fixed sleeps instead) —
  polls are now bounded and adaptive; observers remain a future refinement.

## Delivery-architecture debate (devil's advocate round)

Alternatives argued and rejected:

- **AppleScript / System Events keystrokes** — same CGEvent machinery
  underneath plus an extra Automation TCC prompt; strictly worse.
- **Synthesized drag-and-drop** of the PNG — cannot synthesize a real
  cross-app drag session reliably; wildly fragile pointer choreography.
- **`claude://` deep link / MCP** — no documented deep link attaches an
  image to the composer; MCP is a pull model (an MCP server can't push an
  attachment). Worth re-checking each Claude Desktop release.

Consensus: **clipboard + ⌘V stays as the primary mechanism**, but the
contract changes from *fire-and-forget* to *attempt → verify → loud
fallback*. When any step can't be confirmed, the paste is skipped, the shot
stays on the clipboard, and the user is told so ("press ⌘V") — converting
both bugs from silent failures into a single manual keystroke.

One proposal was rejected during cross-review: retrying an unverified ⌘V
through Claude's Edit ▸ Paste menu. If the ⌘V actually landed but
verification missed it, the retry would duplicate the attachment. The menu
path is therefore used *only* when Claude never became frontmost (where ⌘V
was never posted at all).

## Fixed in this change

**ClaudeInjector (rewritten):**
- `deliver()` now returns a `DeliveryOutcome`
  (`pasted / limitReached / clipboardOnly / appUnavailable / superseded`).
- Deliveries are **serialized**: a new capture cancels the in-flight one and
  writes the clipboard only when it's its turn. Previously two quick shots
  raced: the clipboard was overwritten before the first ⌘V fired, pasting
  the newer shot twice and losing the older one.
- **Never pastes blind.** If composer focus can't be verified, the outcome
  is `clipboardOnly` and the user is told to press ⌘V.
- **5-image limit detection** (Bug 1): before pasting, image attachments in
  the composer's AX container are counted; at ≥ `maxImages` the paste is
  skipped and the user gets a limit-specific message.
- **Paste verification** (Bugs 1+2): after ⌘V, the composer area is polled
  (~1.5 s) for a new image / grown subtree; unverified pastes report
  `clipboardOnly` instead of celebrating.
- `postToPid` ⌘V removed; background paste now drives the **Edit ▸ Paste
  menu item via AX** (locale-independent, matched by ⌘V command char).
- Click fallback hardened: system-wide **hit-test** confirms the point
  belongs to Claude before clicking; 30 ms between down/up; cursor restore
  deferred 120 ms so Chromium registers the click.
- Composer search prefers the **main window** (focused window can be
  Settings/Quick Entry), filters out narrow/top inputs (search fields),
  drops `AXComboBox` (model/style pickers), keeps the bottom-most wide
  text area.
- `AXUIElementSetMessagingTimeout(0.25s)` on all app elements;
  `AXEnhancedUserInterface` no longer set.
- Pasteboard now carries **one** item (PNG + TIFF representations) — the
  previous two-item write could read as two attachments.

**AppshotController:**
- Awaits the delivery outcome and shows an overlay message on every
  non-success (`warn.limit`, `toast.copied`, `warn.noTarget`).
- 6 s **timeout on ScreenCaptureKit** — a hung capture used to leave the
  phase machine stuck in `.flash`, bricking the hotkey until restart.
- Display captures **exclude ClaudeShot's own windows** (the flash overlay
  used to wash out full-screen fallback shots).
- Window targets carry the pointer's display as fallback, so a vanished
  window no longer falls back to an arbitrary display (render scale for
  window captures still uses the densest screen).
- Accessibility alert shown **once per launch** instead of on every capture.
- `permissionMessage` auto-dismiss race fixed (timer cancelled on change,
  not string-compared).
- Temp captures older than one day are swept; PNG is encoded once in memory
  instead of being written and re-read.

**Localization:** `warn.limit` reworded (old text referenced the abandoned
"reset the image count" design), `toast.copied` reworded as an explicit
fallback instruction, `warn.noTarget` added, dead `menu.resetCount`
removed. EN/JA parity maintained.

## Known heuristics and their failure modes

- Attachment counting assumes thumbnails expose as `AXImage` inside the
  composer's container (2–3 ancestors above the text area, stopping at
  `AXWebArea`/window). Verification therefore also accepts *any* growth of
  the container subtree. If Claude's DOM changes such that neither signal
  fires, a successful paste may be reported as "copied — press ⌘V" (a
  harmless false negative; the old behavior was the opposite: false
  success).
- Limit pre-flight only blocks when ≥ 5 images are *detected*; undercounts
  fall through to paste + verification, so detection failures degrade to
  the verified-paste path rather than blocking valid pastes.

## Recommended next steps (not in this change)

1. **Drive the menu-bar icon from the phase machine** — the per-phase
   `AppshotCapturePhase.systemImage`/`statusTitle` already exist unused;
   an icon state is the cheapest non-focus-stealing failure indicator.
2. **"Copy only (no auto-paste)" delivery mode** — zero AX fragility,
   honest default for terminal targets, reuses the existing settings row.
3. **Hotkey hardening** — the recorder accepts bare-⌘ combos (a user can
   hijack ⌘C system-wide) and `RegisterEventHotKey` conflicts fail silently;
   surface both in Preferences.
4. **PermissionCard dismiss button is dead UI** — the overlay panel has
   `ignoresMouseEvents = true`, so the ✕ can never be clicked; either remove
   it or make the panel selectively hit-testable while a card is shown.
5. **Move the AX tree walk off the main actor** (dedicated serial actor) —
   with the 0.25 s messaging timeout this is now bounded, but a busy
   renderer can still add fractions of a second of main-thread work.
6. **Multi-display**: overlay presents on the pointer's screen while the
   captured window may be on another; consider presenting the overlay on
   the captured window's display.
7. **Clipboard restore** (opt-in only): restore the user's previous
   clipboard after a *verified* paste, skipping transient types
   (`org.nspasteboard.TransientType`) — now feasible because paste success
   is finally observable.
8. Re-check each Claude Desktop release for an official attachment API
   (deep link); it would replace this entire AX pipeline.
