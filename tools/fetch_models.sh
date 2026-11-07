#!/bin/sh
# Download the free (CC0) model packs used by tools/blender/convert_characters.py and art/library/kenney.
# Usage: sh tools/fetch_models.sh /tmp/models
set -e
D=${1:-/tmp/kitchen-rat-models}
mkdir -p "$D" && cd "$D"
get() {  # repo, sparse paths…
  dir=$(echo "$1" | tr / _); shift_repo=$1; shift
  [ -d "$dir" ] || git clone -q --depth 1 --filter=blob:none --no-checkout "https://github.com/$shift_repo" "$dir"
  git -C "$dir" sparse-checkout set --no-cone "$@" && git -C "$dir" checkout -q
}
get trebeljahr/quaternius-showcase 'public/glb/animals_pack/*' 'public/glb/easy_enemies_pack/*'
get shorepine/kenney '3d/furniture/*' '3d/food/*' '3d/cube-pets/*' 'LICENSE*'
get beep2bleep/FreeAssetsByKenneyNLandQuaternius 'FreeModels by Quaternius*/Characters and Animals/Animal Pack Vol.2*/*' \
  'FreeModels by Quaternius*/Characters and Animals/Animated Men*/*' 'FreeModels by Quaternius*/Characters and Animals/Animated Women*/*'
echo "models in $D"
