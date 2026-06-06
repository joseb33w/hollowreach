# Goal

Build **Hollowreach** — a Godot 4.6.3 multiplayer 3D exploration RPG exported to web
(nothreads HTML5, Compatibility/WebGL2) and playable in a phone's default browser
(Safari/Chrome, iOS & Android). KayKit chunky-adventure style.

- **World**: low-poly overworld — a village ringed by forest + rocky paths + a dungeon
  entrance. MultiMesh-scattered trees/rocks/grass, lit `WorldEnvironment` (sun, soft
  shadows, light fog, ACES tonemap), `SpringArm3D` follow-camera.
- **Player**: KayKit Knight. Idle/Walk/Run blended by speed via `AnimationTree`
  (`BlendSpace1D`), one-shot melee attack, emote, hit/death. Health bar. Touch joystick +
  drag-look + attack/emote buttons (mobile); WASD + mouse (desktop).
- **LLM NPCs**: villagers (a nervous blacksmith, a cryptic hermit), each a real LLM persona
  via `https://npc.myapping.com/chat`, remembering the conversation. Walk up -> Talk -> chat
  box with a "…" while thinking.
- **Combat (PvE + PvP), synced**: skeletons patrol -> chase -> attack; melee drops their HP
  -> death. Players can attack each other (HP drop, respawn). Positions/health/hits synced
  over Supabase Realtime broadcast so a 2-player room stays consistent.
- **Multiplayer**: same-room players share the live world (Knights with name tags + emote).
  Room code in the URL — open a second tab or send a friend the link.

# Files to touch

- `project.godot` — Compatibility renderer, Net autoload, input map, mobile display.
- `export_presets.cfg` — Web/nothreads preset, head_include with Supabase SDK CDN + bridge.js.
- `web/bridge.js` — Supabase Realtime broadcast bridge (creds filled in).
- `net.gd` — serverless multiplayer autoload (from the mp module).
- `main.gd` + `main.tscn` — orchestrator: world, player, HUD, net routing, host election.
- `scripts/world.gd` — overworld builder (env, ground, village, forest/rock scatter, dungeon).
- `scripts/character.gd` — KayKit character + AnimationTree factory (player/remote/enemy/npc).
- `scripts/player.gd` — local Knight controller (movement, camera, attack, health, melee).
- `scripts/remote_player.gd` — networked remote Knight (interpolation, name tag, health).
- `scripts/enemy.gd` — skeleton AI (patrol/chase/attack/die), host-authoritative sync.
- `scripts/npc.gd` — LLM villager (persona, Talk prompt, HTTPRequest to npc.myapping.com).
- `scripts/hud.gd` — touch joystick, look drag, buttons, health bar, room code, chat panel.
- `models/`, `textures/` — staged KayKit characters + Kenney/KayKit props + seamless textures.

# Verification approach

- `godot --headless --import` then `--export-release "Web"` -> `out/` (index.html/js/wasm/pck).
- Run the vetted Godot web smoke-verifier (Playwright, software-GL Chromium): engine boots,
  canvas present, console clean, frames captured; inspect screenshots against KayKit style.
- 2-client Node test against real Supabase Realtime (one broadcasts -> the other receives) to
  prove multiplayer sync without the in-container wss artifact.
- Direct check of the NPC LLM endpoint (persona reply).

# Out of scope

- No persistence/leaderboard/accounts (the request is a live shared world) -> no Supabase
  tables; multiplayer is ephemeral Realtime broadcast, LLM NPCs use the hosted brain.
- Authoritative anti-cheat server (this is casual client-authoritative friends-play).
- Terrain elevation (flat ground; rocky paths conveyed via rock scatter + textures).
