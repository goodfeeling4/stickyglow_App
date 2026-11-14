# PLAN.md — Execution Roadmap

## Phase 1: Project Scaffold & Dependencies
- Initialize Flutter project (`org.example.sticky_notes_ssh`) if not already initialized.
- Add dependencies to `pubspec.yaml`:
  - `dartssh2`
  - `sqflite`, `path`, `path_provider`
  - `flutter_secure_storage`
  - `flutter_markdown`, `markdown`
  - `flutter_local_notifications`
  - `workmanager`, `connectivity_plus`, `flutter_foreground_task`
  - `flutter_staggered_grid_view`
  - `diff_match_patch`
  - `intl`, `uuid`
- Configure Android `AndroidManifest.xml` and `android/app/build.gradle` (`minSdk = 24`, core library desugaring enabled for `flutter_local_notifications`).

## Phase 2: Data Layer & Pure Markdown Engine
- `lib/models/sticky_note.dart`: Model with `id`, `filename`, `title`, `content`, `colorIndex`, `isPinned`, `tags`, `updatedAt`, `syncStatus` (`synced`, `pending`, `conflict`), `conflictRemoteContent`.
- `lib/models/ssh_profile.dart`: Model with `id`, `name`, `host`, `port`, `username`, `remoteDir`, `priority`.
- `lib/services/local_db_service.dart`: SQLite persistence for sticky metadata + file I/O for `notes/<filename>.md` and `.sync_base/<filename>.md`.
- `lib/utils/markdown_checklist_helper.dart`: Parse and toggle `- [ ]` / `- [x]` lines directly by line index without altering surrounding Markdown formatting.

## Phase 3: Sticky Notes UI & Rich Editor
- `lib/theme/sticky_colors.dart`: Curated light/dark pastel sticky note palette (Amber, Mint, Sky, Lavender, Rose, Slate).
- `lib/screens/home_screen.dart`:
  - Google Keep-style 2-column masonry grid (`MasonryGridView.count`) split into **Pinned** and **Others** sections.
  - Top search bar + horizontal tag filter chips + live sync status pill (`Connected`, `Offline`, `Syncing`, `Conflict`).
  - Interactive checklist checkboxes directly tappable on each sticky card preview.
  - Conflict warning banner on cards with `syncStatus == conflict`.
- `lib/screens/note_editor_screen.dart`:
  - Auto-derives clean `.md` filename from first `# Heading` or title on creation, preserving existing filename on edits.
  - Rich Markdown toolbar (`H1`, `H2`, `Bold`, `Italic`, `Checklist`, `Bullet`, `Code Block`) + toggleable **Edit / Split / Live Preview** mode.
  - Bottom metadata bar: card color picker dots, pin toggle, tag editor chips, live word/character count, and `"Saved locally"` / `"Synced"` indicator.
  - 3-second debounced auto-save triggering background sync if a laptop profile is reachable.
- `lib/screens/conflict_diff_screen.dart`:
  - Side-by-side / unified line diff viewer comparing Phone vs. Laptop versions with one-tap resolution buttons (`Keep Phone`, `Keep Laptop`, `Keep Both`, `Save Manual Merge`).
- `lib/screens/git_history_sheet.dart`:
  - Bottom sheet displaying `git log` commits for the active note (`%h|%ad|%s`) with commit diff preview and one-tap restore via `git show <hash>:<filename>`.

## Phase 4: SSH/SFTP Sync & 3-Way Conflict Engine
- `lib/services/conflict_resolver.dart`:
  - Implements 3-way merge (`base`, `local`, `remote`) using `diff_match_patch` line-mode diffing.
  - Auto-merges non-overlapping edits; flags true line collisions with conflict backup generation.
- `lib/services/ssh_sync_service.dart`:
  - Parallel TCP reachability probe across sorted `SshProfile` entries.
  - Full bidirectional sync transaction:
    1. Ensure `remoteDir` exists and is a Git repo.
    2. Run `git status --porcelain` on laptop; if uncommitted edits exist, commit them first so Git history is clean.
    3. List remote `*.md` files and compare against local SQLite + `.sync_base`.
    4. Execute fast-forward pulls, fast-forward pushes, 3-way auto-merges, or conflict quarantine.
    5. Run `git add -A && git commit -m "Mobile sync (<timestamp>)"` on laptop when any remote file changed.

## Phase 5: Zero-App-Open Background Sync & Settings
- `lib/services/background_sync_manager.dart`:
  - Top-level `@pragma('vm:entry-point')` callback dispatcher for `Workmanager` + `FlutterForegroundTask` (optional persistent low-power laptop-watch service listening to network changes and UDP wake beacon on port `41234`).
  - Triggers `NotificationService.showLaptopSyncNotification(...)` automatically when background sync succeeds or detects a conflict.
- `lib/screens/ssh_settings_screen.dart`:
  - Manage multiple SSH profiles (Hotspot, LAN, Tailscale), paste/import Ed25519 private key, toggle `"Auto-Sync on Laptop Connect (Background)"`, and run a live **"Test SSH & Git Connection"** diagnostic check.

## Phase 6: Automated Testing & Build Verification
- Write `test/conflict_resolver_test.dart` covering:
  - Fast-forward pull, fast-forward push, non-overlapping checklist auto-merge, and overlapping line conflict detection.
- Write `test/markdown_checklist_test.dart` covering checkbox toggling on raw `.md` strings.
- Run `dart analyze --fatal-infos`, `flutter test`, and `flutter build apk --debug`.
