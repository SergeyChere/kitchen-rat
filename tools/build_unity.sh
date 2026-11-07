#!/bin/sh
# Build the Unity game for Mac on this computer and zip it.
#   sh tools/build_unity.sh            build
#   sh tools/build_unity.sh v0.9.0     build and upload the zip to that GitHub release (needs the gh CLI)
set -e
cd "$(dirname "$0")/.."
UNITY=$(ls -d /Applications/Unity/Hub/Editor/6000*/Unity.app/Contents/MacOS/Unity 2>/dev/null | tail -1)
[ -n "$UNITY" ] || { echo "Unity 6 not found in /Applications/Unity/Hub/Editor. Install it with Unity Hub."; exit 1; }
echo "Using $UNITY — close the project in Unity first. The first build takes a few minutes."
rm -rf build/unity-mac
"$UNITY" -batchmode -quit -projectPath "$PWD/unity" -buildTarget OSXUniversal \
  -executeMethod KitchenRat.EditorTools.CIBuild.Build -customBuildPath "$PWD/build/unity-mac/KitchenRat.app" \
  -logFile "$PWD/build/unity-build.log" || { echo "Build failed. Send build/unity-build.log to Claude."; exit 1; }
(cd build/unity-mac && rm -f ../KitchenRat-Unity-Mac.zip && zip -qry ../KitchenRat-Unity-Mac.zip KitchenRat.app)
echo "Done: build/KitchenRat-Unity-Mac.zip"
[ -z "$1" ] || gh release upload "$1" build/KitchenRat-Unity-Mac.zip --clobber
