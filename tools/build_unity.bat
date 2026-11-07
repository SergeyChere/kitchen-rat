@echo off
rem Build the Unity game for Windows on this computer and zip it.
rem Double-click it, or run:  tools\build_unity.bat
rem Optional: tools\build_unity.bat v0.9.0   also uploads the zip to that GitHub release (needs the gh CLI).
setlocal enabledelayedexpansion
cd /d "%~dp0.."

set "UNITY="
for /d %%D in ("C:\Program Files\Unity\Hub\Editor\6000*") do if exist "%%D\Editor\Unity.exe" set "UNITY=%%D\Editor\Unity.exe"
if not defined UNITY (
  echo Unity 6 was not found in C:\Program Files\Unity\Hub\Editor. Install it with Unity Hub.
  pause & exit /b 1
)
echo Using %UNITY%
echo Building... this takes a few minutes the first time. Close the project in Unity first.

if exist build\unity-windows rmdir /s /q build\unity-windows
"%UNITY%" -batchmode -quit -projectPath "%cd%\unity" -buildTarget Win64 ^
  -executeMethod KitchenRat.EditorTools.CIBuild.Build -customBuildPath "%cd%\build\unity-windows\KitchenRat.exe" ^
  -logFile "%cd%\build\unity-build.log"
if errorlevel 1 (
  echo Build failed. Send build\unity-build.log to Claude.
  pause & exit /b 1
)

if exist build\KitchenRat-Unity-Windows.zip del build\KitchenRat-Unity-Windows.zip
powershell -NoProfile -Command "Compress-Archive -Path 'build\unity-windows\*' -DestinationPath 'build\KitchenRat-Unity-Windows.zip'"
echo Done: build\KitchenRat-Unity-Windows.zip

if not "%~1"=="" (
  gh release upload %1 build\KitchenRat-Unity-Windows.zip --clobber && echo Uploaded to release %1
)
pause
