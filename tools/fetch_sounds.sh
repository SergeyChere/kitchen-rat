#!/bin/sh
# Download the free (CC0) sound packs that tools/import_sounds.py takes recordings from.
#   sh tools/fetch_sounds.sh /tmp/sounds && python3 tools/import_sounds.py /tmp/sounds
set -e
dir=${1:-/tmp/kitchen-rat-sounds}
mkdir -p "$dir" && cd "$dir"
[ -d kenney-impact-sounds-for-godot ] || git clone -q --depth 1 https://github.com/Boyquotes/kenney-impact-sounds-for-godot.git
[ -d kenney-interface-sounds ] || git clone -q --depth 1 https://github.com/Calinou/kenney-interface-sounds.git
[ -d sfx-kit ] || git clone -q --depth 1 https://github.com/wyzowl/sfx-kit.git
if [ ! -d lavenderdotpet_CC0-Public-Domain-Sounds ]; then
  git clone -q --depth 1 --filter=blob:none --no-checkout https://github.com/lavenderdotpet/CC0-Public-Domain-Sounds.git lavenderdotpet_CC0-Public-Domain-Sounds
  cd lavenderdotpet_CC0-Public-Domain-Sounds
  git sparse-checkout init --no-cone
  git sparse-checkout set "/LICENSE" "/Micro Pack - Cat Meows/" "/80-CC0-creature-SFX/" "/80-CC0-creature-sfx-2/" "/100-CC0-SFX/" "/100-CC0-wood-metal-SFX/" "/100-cc0-sfx-2/" "/30-cc0-sfx-loops/"
  git checkout -q HEAD
fi
echo "sound packs in $dir"
