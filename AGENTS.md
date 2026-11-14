# AGENTS.md — Sticky Notes SSH Sync App (Android / Flutter)

## Project Identity
Build a complete, offline-first Android Sticky Notes app in Flutter that stores pure plain-text `.md` files on a Linux laptop (`~/sticky-notes/*.md`) over SSH/SFTP, auto-versions every edit via Git on the laptop, resolves two-sided offline conflicts cleanly, and triggers background sync + Android notifications automatically when the laptop connects—even while the app is closed or the device is in sleep mode.

## Hard Technical Constraints
1. **Target Platform:** Android (`minSdk 24`, `targetSdk 34`). Configure `AndroidManifest.xml` with permissions: `INTERNET`, `ACCESS_NETWORK_STATE`, `ACCESS_WIFI_STATE`, `POST_NOTIFICATIONS`, `RECEIVE_BOOT_COMPLETED`, `WAKE_LOCK`, `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_DATA_SYNC`.
2. **Laptop File Format (Strict Pure Markdown):**
   - Files on the laptop (`remoteDir/*.md`) MUST be pure plain-text Markdown with **zero YAML frontmatter**.
   - Mobile-only metadata (`colorHex`, `isPinned`, `tagsJson`, `syncStatus`, `conflictRemoteContent`, `lastSyncedAt`) MUST be stored locally in SQLite (`sqflite`) alongside local working `.md` files (`appDocDir/notes/`) and base snapshot files (`appDocDir/.sync_base/`).
3. **SSH & Remote Git Execution (`dartssh2`):**
   - Never bundle native `libgit2`. Perform file transfers over SFTP (`sftp.listdir`, `sftp.open`, `readBytes`, `writeBytes`) and execute `git` commands directly on the Linux host via `SSHClient.run(...)`.
   - Run all SSH/SFTP and 3-way diff operations inside `compute()` / background isolates so the UI never drops frames.
   - Store private keys and profile credentials in `flutter_secure_storage`.
4. **Multi-Profile SSH & Auto-Discovery:**
   - Support multiple prioritized SSH profiles (e.g., Android Hotspot IP, Home LAN IP, Tailscale IP) with configurable port (`22` or custom like `8022`), username, remote path, and Ed25519 private key PEM.
   - Probe reachable profiles in parallel using fast TCP `Socket.connect(host, port, timeout: Duration(milliseconds: 1500))` and pick the first responsive endpoint.
5. **Zero-App-Open Background Sync & Notifications:**
   - Register a `Workmanager` periodic task (15-min interval, `NetworkType.connected`) + an Android `ConnectivityManager.NetworkCallback` / foreground wake listener (`flutter_foreground_task` + UDP port `41234` listener) that immediately triggers sync when network connectivity changes or the laptop comes online.
   - If no SSH profile is reachable on TCP probe, abort silently in less than 2 seconds (no notification).
   - When a laptop connection succeeds and sync runs in the background, post a local Android notification (`flutter_local_notifications`) summarizing synced changes (e.g., `"Laptop Connected: Pulled 1, Pushed 2"`) or alerting on a merge conflict—without requiring the user to open the app.
6. **Two-Sided Conflict Management (3-Way Merge + Diff UI):**
   - Maintain `.sync_base/<filename>.md` representing the last mutually agreed file content.
   - When both `local != base` and `remote != base` and `local != remote`:
     1. Attempt a line-level 3-way merge (`diff_match_patch` / LCS). Non-overlapping edits (such as toggling different checklist items or appending paragraphs) MUST auto-merge cleanly, push to laptop, `git commit`, update `.sync_base`, and notify.
     2. Overlapping line collisions MUST NEVER overwrite data: save a backup `<filename>.conflict-<timestamp>.md` on the laptop, mark the local note `syncStatus = 'conflict'`, store `conflictRemoteContent` in SQLite, fire a high-priority notification, and show a **"Conflict" badge + Side-by-Side Diff Modal** ("Keep Phone", "Keep Laptop", "Keep Both", or "Edit Merged").

## Verification Gate
Before finishing, you MUST run and pass:
1. `flutter pub get`
2. `dart analyze --fatal-infos`
3. `flutter test` (including unit tests for the 3-way merge & conflict engine and pure Markdown checklist parser)
4. `flutter build apk --debug`
