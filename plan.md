# Background macOS app plan

## Goal

Keep the selected broadcast, Stockfish analysis, followed-player status checks, notifications, and widget data running after the main window is closed. The user can reopen the window or explicitly quit from the macOS menu bar. Do not add login-at-startup or prevent system sleep unless requested separately.

## Implementation

1. Move ownership of the selected game, broadcast stream, reconnect/backoff state, Stockfish process, followed-player refresh, and notifications out of SwiftUI view `.task` handlers into a single app-lifetime model. Keep one stream and one engine instance; preserve existing saved selection, token, notification preferences, clocks, and widget data.
2. Add a menu bar item showing a compact connection state and the selected game. Provide actions to open the main window and quit the app; make any pause or stop behavior explicit. Ensure selecting a different game cancels the old stream and analysis cleanly.
3. Keep the process and monitoring alive when the user closes the last window. Reopening the window must reuse the existing model rather than create a second watcher, engine, or followed-player polling loop. Explicit Quit must cancel network tasks and stop Stockfish.
4. Handle network loss and Mac sleep/wake: close or recover stale connections, reconnect with existing rate-limit backoff, restore the latest game state, and avoid duplicate notifications. Do not emit a burst of historical move or friend-status notifications when reconnecting.
5. Continue sending widget updates and silent notifications while the app is running without a window. WidgetKit may delay refreshes; show an accurate connection or stale-data status where appropriate. Background operation ends when the app is quit or the Mac sleeps.

## Verification

- Build a signed standalone app with its widget and embedded Stockfish. Launch it from Applications without Xcode and verify Keychain access and widget registration.
- Select a live broadcast, close the window, and verify new moves, engine analysis, widget updates, friend-status checks, and silent notifications continue. Reopen the window and confirm the existing selection and status are displayed.
- Verify switching games, repeatedly opening and closing the window, and quitting do not leave duplicate streams or Stockfish processes.
- Exercise offline/reconnect, rate limits, sleep/wake, and completed games. Confirm no duplicate or historical alerts and record any remaining macOS-controlled widget delay.

## Progress — 2026-11-25

### Implemented

- Replaced the menu bar symbol with the same white bishop asset used on the board, rendered to an 22-point image with 85% opacity and added a notification toggle; connection status remains in the menu. Signed Release build succeeded and was installed; interactive menu behavior has not yet been verified.
- Configured the app as a menu bar agent so it does not appear in the Dock. The signed Release build was installed and launched; System Events reports background-only true.
- Moved the broadcast watcher, Stockfish, notifications and followed-player polling into app-lifetime models shared by the window and menu bar. Added open and quit actions and prevented termination when the last window closes.
- Added sleep/wake handling and notification baselines on reconnect or failed player refresh. Game changes cancel the old monitor before starting the next one.
- Widget displays the age of the last position; clock changes also refresh the saved widget data.

### Verification and remaining work

- Debug build without signing succeeded. Release build with signing succeeded; `codesign --verify --deep --strict` passed outside the sandbox and verified the widget and embedded Stockfish. The latest sleep/reconnect changes also passed a signed Release build.
- Installed and launched `/Applications/ChessWidget.app`; the application and one embedded Stockfish process were observed. PluginKit lists the widget identifier, but lists multiple registrations, so the active widget instance is not confirmed.
- The existing app started with a saved selection and Stockfish, but Keychain access was not independently verified. An attempt to inspect the application window via System Events returned no window names; close/reopen behavior was not verified.
- Still required: verify live moves, analysis, widget updates, friend checks and notifications with the window closed; reopen; switch games and check for duplicate streams/processes; exercise offline, rate limiting, sleep/wake and completed games; verify no historical alerts and record WidgetKit delays. The latest Release build is installed; the live scenarios above still need verification.

### Distribution metadata — 2026-11-25

- Added the Games application category and the Chess Position widget display name. A new signed archive was created at `/tmp/lichess-distribution-check.xcarchive`; both values were checked in its bundled Info.plist files.
- The official Stockfish executable contains no debug information for either architecture (`dsymutil` reports no debug symbols). App Store Connect may still show the missing dSYM warning; meaningful symbols require a matching upstream dSYM or a new engine build with debug information. Distribution validation and upload have not been rerun.
