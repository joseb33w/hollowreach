# Hollowreach

A **Godot 4.6.3 multiplayer 3D exploration RPG**, exported to the web and fully playable in
a phone's default browser (Safari / Chrome, iOS & Android) — single-threaded HTML5,
Compatibility / WebGL2, touch controls, tap-to-start. KayKit chunky-adventure style.

Roam a low-poly overworld as the Knight: a village ringed by forest, rocky paths, and a
dungeon entrance. Chat with LLM-powered villagers, fight skeletons (PvE), duel other players
(PvP), and share the live world with friends over a room link.

## Play

Open the build, **tap to enter**, and you spawn in the village. Movement and combat sync to
everyone in your **room** (the `?room=CODE` in the URL) — open a second tab or send a friend
the link to play together.

### Controls (touch + keyboard)

| Action        | Phone                                   | Desktop                     |
| ------------- | --------------------------------------- | --------------------------- |
| Move          | Left half — drag to steer a joystick    | `WASD` / arrow keys         |
| Look          | Right half — drag to orbit the camera   | Drag with the left mouse    |
| Attack (melee)| **ATK** button                          | the **ATK** button          |
| Wave / emote  | **WAVE** button                         | the **WAVE** button         |
| Talk to NPC   | walk up, then the **Talk** button       | same                        |

## Features

- **World** — a lit `WorldEnvironment` (procedural sky, sun + soft shadows, light fog, ACES
  tonemap), a textured ground with a dirt path to the dungeon, `MultiMeshInstance3D`-scattered
  trees / rocks / grass, KayKit village buildings, and a banner-flanked dungeon arch.
- **Player** — the KayKit Knight driven by an `AnimationTree`: idle → walk → run blended by
  speed (`BlendSpace1D`), with one-shot melee attack, wave, hit and death. `SpringArm3D`
  collision-aware follow camera. Health bar.
- **LLM NPCs** — *Doran the Smith* (nervous) and *Sila the Hermit* (cryptic) are backed by a
  real LLM. Each has its own persona and **remembers your conversation**. Walk up → **Talk** →
  type (or tap a suggestion) and they reply in-character, with a `...` while they think.
- **Combat, synced over the room**
  - **PvE** — skeletons patrol → chase → attack. Your melee drops their health → death (they
    respawn at the dungeon). Enemy + player health is consistent for everyone watching.
  - **PvP** — you can attack other players; hits drop their health and death respawns them.
- **Multiplayer** — peers in the same room share the live world as Knights with floating name
  tags, see each other move / attack / wave, and stay in sync over **Supabase Realtime**.

## Architecture

- **Engine**: Godot 4.6.3, Compatibility renderer (mobile WebGL2), exported with the
  **nothreads** web template (no SharedArrayBuffer — works without COOP/COEP headers).
- **Multiplayer**: serverless and client-authoritative. Peers exchange state on a public
  Supabase Realtime **broadcast** channel (`game:<ROOM>`) via `web/bridge.js`, surfaced to
  GDScript by the `Net` autoload (`net.gd`). No game server; no database tables. Skeletons are
  **host-authoritative** — the peer with the lowest id simulates the AI and broadcasts state;
  others render replicas. Host re-elects automatically when peers join or leave.
- **NPC brain**: `https://npc.myapping.com/chat` (CORS-open), called straight from GDScript
  with an `HTTPRequest`. Each NPC keeps its own message history for memory.

### Code layout

```
main.gd                 Orchestrator: world, player, HUD, net routing, host election
net.gd                  Supabase Realtime autoload (Net)
web/bridge.js           JS broadcast transport (Supabase SDK)
scripts/world.gd        Overworld builder (environment, village, scatter, dungeon)
scripts/character.gd    KayKit character + AnimationTree factory
scripts/player.gd       Local Knight (movement, camera, melee, health)
scripts/remote_player.gd Networked peer Knight (interpolation, name tag, health)
scripts/enemy.gd        Skeleton AI (patrol/chase/attack/die), host-authoritative
scripts/npc.gd          LLM villager (persona + conversation memory)
scripts/hud.gd          Touch joystick, look pad, buttons, health, room info, chat
scripts/joystick.gd     Dynamic on-screen joystick
scripts/floating_tag.gd Billboarded name tag + health bar
```

## Build it yourself

The CC0 art (KayKit / Kenney models, hand-painted textures) is **not** committed to keep the
repo light — fetch it with one command, then build:

```bash
bash fetch_assets.sh                 # downloads models/ + textures/ (CC0)
GODOT=/path/to/godot bash build.sh   # imports + exports the web build into out/
python3 -m http.server -d out 8080   # then open http://localhost:8080
```

Requires Godot **4.6.3** with the **web (nothreads)** export templates installed. Serve the
build over HTTP (not `file://`) so the `.wasm` loads with the right MIME type.

Credits: art is CC0 by **Kenney**, **KayKit (Kay Lousberg)** and **Quaternius**.
