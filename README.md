# Shipment FPP (Godot 4.3)

First-person arena shooter ported from the Three.js version. Everything (arena, bots,
viewmodel, HUD, sounds) is built in code, so the scene file is tiny.

## Run it
1. Install **Godot 4.3** (standard build, not .NET).
2. Project Manager -> Import -> pick `project.godot` -> Run (F5).
   Desktop controls: WASD move, Shift sprint, Space jump, C slide, R reload,
   arrow keys look, click the on-screen buttons (mouse acts as touch).

## Features
- 3 bots (patrol / chase / strafe + shoot), ammo pickups dropped on kills
- Empty radar (no enemy blips), hitmarkers, HP + regen + damage vignette, death / respawn
- Sprint lock (push the stick past the ring), slide, crouch, ADS
- Holding fire blocks sprint, clears sprint lock, keeps ADS; sprint works again on release
- HUD layout editor: EDIT HUD (in game) or CUSTOMIZE HUD LAYOUT (menu). Drag any outlined
  button/element, resize with the slider, RESET DEFAULT, DONE / SAVE. Game pauses while editing.
  Saved to `user://hud_layout.cfg` and loaded at startup.
- Performance: GL Compatibility renderer, 2048 directional shadow map, only large structures
  and bots cast shadows, change-checked HUD writes, reused raycast query, pooled tracers.

## Android APK via GitHub Actions
1. Push this folder to a GitHub repo (branch `main`).
2. The workflow `.github/workflows/android.yml` builds a **debug APK** and uploads it as the
   artifact `ShipmentFPP-debug-apk` (Actions tab -> latest run -> Artifacts).
3. Change `package/unique_name` in `export_presets.cfg` to your own id (e.g. `com.yourname.shipment`).

## Not verified
Written without running Godot. If the editor shows a script error on first open or the first
Actions run fails, paste the message and it is usually a one-line fix.

## Multiplayer (free for all, up to 4 players)
- Menu -> MULTIPLAYER. One phone taps HOST, the others tap JOIN.
- **Bluetooth (Android):** pair the phones first in Android Bluetooth settings. The host taps
  HOST BLUETOOTH, the others tap JOIN BLUETOOTH and pick the host from the list. Range is about 10 m.
- **LAN (desktop or same Wi-Fi):** the host taps HOST LAN and shares the IP shown on screen. Joiners
  type it into the box and tap JOIN LAN. Port 7788. Two windows on one PC work with 127.0.0.1.
- Host taps START MATCH. Bots are removed in multiplayer. First to 15 kills wins, then the score resets.
- The host is authoritative for HP, kills and respawns. Clients send their own position and hit claims.
- The Bluetooth plugin lives in `android-plugin/` (Kotlin). The workflow builds it into an AAR and
  installs it in `android/plugins/` before exporting the APK. Restart the app to go back to offline bots.

Known limits: Bluetooth Classic is slow and short range, so it suits 2-4 phones in one room.
Remote gunshots and tracers are not rendered yet, and clients are trusted for their own position,
so this is for friends, not competitive play.
