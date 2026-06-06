# Goal (this round — bug fixes)

Fix the three reported problems so Hollowreach is fully playable in a phone browser:

1. **Character is frozen / can't move.**
2. **It "keeps saying connect"** (room status stuck on "Connecting...").
3. **Pressing multiple buttons at once causes issues** (one input stealing another).

## Root cause (1 + 2 — same bug)

`main.gd._show_tap_to_start()` created the tap-to-start `CanvasLayer` and added the
title/sub/tip + `gui_input` handler to it, but **never called `add_child(layer)`**. The
overlay was an orphan node that never entered the scene tree, so its tap handler never
fired. That handler is the ONLY place that sets `started = true` /
`player.input_enabled = true` (→ character frozen) and calls `Net.connect_room()`
(→ "Connecting..." forever). One missing line broke both.

## Root cause (3 — multitouch)

The action buttons (ATK / WAVE / Talk) were plain `Button`s driven by the emulated mouse
(`emulate_mouse_from_touch`), which is a SINGLE pointer. While a finger held the joystick
(or another button), a second finger's button tap generated no mouse event, so it was
dropped — you couldn't attack while moving, or press two buttons together.

# Files to touch

- `main.gd` — add `add_child(layer)`; move the dismiss logic into a named
  `_on_tap_to_start` handler; wire `Net.disconnected` → friendly "Offline" status + a
  light reconnect so the label never sticks on "Connecting..." if the socket drops.
- `scripts/hud.gd` — replace the single-pointer button/joystick/look wiring with one
  index-keyed **multitouch router** (`_unhandled_input`): every finger is tracked by its
  touch index and routed independently to joystick / look / a button, so move + look +
  buttons all work simultaneously. Action buttons become router-driven (hit-tested by
  rect, with a press-flash tween) instead of relying on emulated-mouse `pressed`.
- `scripts/joystick.gd` — make the joystick a pure visual driven by the router
  (`begin/drag/end`); drop its own `_gui_input`; remove antialiased `_draw` (software-GL safe).

# Verification approach

- `godot --headless --import` + `--export-release "Web"` → `out/` (clean parse, all of
  index.html/js/wasm/pck present).
- Vetted Godot web smoke-verifier (Playwright, software-GL Chromium): boots, canvas, clean console.
- Custom gameplay verifier: tap-to-start, then HOLD W and measure the rendered delta
  (idle ≈ 1.0 vs moving ≈ 24.5 → character is NOT frozen); then drive a joystick drag with
  a second finger holding ATK (CDP multitouch) and confirm motion continues.
- Multi-button verifier: mash ATK + WAVE together, then confirm input is still responsive
  afterwards (no stuck-input deadlock) and the console is clean.
- 2-client Node test against the real Supabase Realtime channel (one broadcasts → the other
  receives) to prove the multiplayer transport works (the in-browser "Connecting..." seen in
  the GPU-less container is the sandbox CDN-cert/wss artifact, not a device bug).

# Out of scope

- No gameplay/content changes — combat, NPCs, world, art and the networking protocol are
  unchanged; this round is strictly the movement + connection + multitouch fixes.
- No persistence/accounts (ephemeral Realtime broadcast world, as before).
