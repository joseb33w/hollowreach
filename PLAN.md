# Goal

Fix the player (and all character) model facing being rotated 180° from the
direction of travel: moving forward shows the character's back leading / face
toward the camera. Movement direction itself is correct — only the visual
yaw of the rig is inverted.

# Root cause

KayKit characters are glTF assets. glTF defines **+Z** as an asset's front,
which is the opposite of Godot's **-Z** forward convention, and Godot does not
auto-flip glTF meshes on import — so the KayKit Knight/Skeleton/etc. face +Z at
`rotation.y = 0`.

Every character computes `_face_yaw = atan2(dir.x, dir.z)` (the world yaw whose
+Z points along travel `dir`) and then sets `rig.rotation.y = _face_yaw +
MODEL_YAW_OFFSET` with `MODEL_YAW_OFFSET = PI`. For a +Z-forward model the
correct offset is `0`: `rotation.y = _face_yaw` already aligns the mesh's +Z
front with `dir`. Adding PI points the mesh at `-dir` — exactly backward.

# Files to touch

- `scripts/player.gd` — `MODEL_YAW_OFFSET` PI -> 0.0
- `scripts/remote_player.gd` — `MODEL_YAW_OFFSET` PI -> 0.0
- `scripts/enemy.gd` — `MODEL_YAW_OFFSET` PI -> 0.0
- `scripts/npc.gd` — `MODEL_YAW_OFFSET` PI -> 0.0 (NPCs face the player; same inversion)

Melee aim uses `_face_yaw` directly (independent of the offset) and is already
correct, so it is unchanged.

# Verification approach

- Export the nothreads Web build with Godot 4.6.3.
- Run the smoke verifier (engine boots, canvas present, console clean, frames).
- Drive forward (W) movement in headless Chromium and capture frames; confirm
  the Knight faces its travel direction (back to the follow-camera while running
  away from it) instead of moon-walking with its face to the camera.

# Out of scope

- Any gameplay, networking, art, or camera changes beyond the facing fix.
