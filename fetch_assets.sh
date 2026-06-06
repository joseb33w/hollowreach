#!/usr/bin/env bash
# Hollowreach — fetch the CC0 art (KayKit / Kenney characters + props, hand-painted
# textures) into models/ and textures/. These binaries are NOT committed to git; run
# this once, then open the project in Godot 4.6.3 (it will import them automatically).
#
#   ./fetch_assets.sh
#
# Assets are CC0 (Kenney, KayKit/Kay Lousberg, Quaternius). Mirror: preview.myapping.com.
set -euo pipefail

ASSETS="https://preview.myapping.com/godot-assets"
TEX="https://preview.myapping.com/godot-textures"
cd "$(dirname "$0")"
mkdir -p models textures

# id<TAB>relative-path-under-godot-assets
CHARACTERS_AND_PROPS=$(cat <<'EOF'
characters/kk_Knight.glb
characters/kk_Barbarian.glb
characters/kk_Mage.glb
characters/kk_Skeleton_Warrior.glb
characters/kk_Skeleton_Minion.glb
nature/tree_blocks.glb
nature/tree_blocks_dark.glb
nature/tree_cone.glb
nature/tree_cone_dark.glb
nature/rock_largeA.glb
nature/rock_largeC.glb
nature/stone_largeB.glb
nature/path_stone.glb
nature/log_large.glb
props/kk_nature/Grass_1_A_Color1.glb
props/kk_hex/building_blacksmith_blue.glb
props/kk_hex/building_tavern_blue.glb
props/kk_hex/building_well_blue.glb
props/kk_hex/building_home_B_blue.glb
props/kk_hex/building_church_blue.glb
props/kk_hex/building_market_blue.glb
props/kk_halloween/arch_gate.glb
props/kk_halloween/grave_B.glb
props/kk_halloween/bone_A.glb
props/kk_dungeon/banner_patternA_red.glb
EOF
)

TEXTURES="grass dirt_ground stone_floor rock_cliff tree_bark"

echo "Fetching models..."
while IFS= read -r rel; do
  [ -z "$rel" ] && continue
  out="models/$(basename "$rel")"
  curl -sfL "$ASSETS/$rel" -o "$out" && echo "  $out"
done <<< "$CHARACTERS_AND_PROPS"

echo "Fetching textures..."
for t in $TEXTURES; do
  curl -sfL "$TEX/$t.png" -o "textures/$t.png" && echo "  textures/$t.png"
done

echo "Done. Open the project in Godot 4.6.3 to import, or run build.sh to export for web."
