# Chess Broadcast Watcher

Watch live Lichess broadcasts and receive notifications for new moves, evaluation changes, and game results. The watcher stops when the selected game ends.

```sh
npm install
npm run broadcast
```

Choose a live broadcast and then a game from the numbered lists. The available broadcasts depend on what is live on Lichess. If the game finishes while you are choosing, the watcher exits after receiving its result. Press Ctrl+C to stop watching.

Run `npm run broadcast:inspect` to print the API data for the first live broadcast and its round, including the first game. This is useful for inspecting which tournament details Lichess provides.

Keep the terminal and computer running; sleep pauses monitoring. Notifications currently require macOS: allow Script Editor notifications, including in Focus mode. On other systems, messages appear in the terminal.

To watch the default broadcast round, use `npm start`. Its default is [game 1 of the 2026 World Chess Championship](https://lichess.org/broadcast/fide-world-chess-championship-2026/game-1/xLgOJ6cb); it does not automatically select the latest round. To specify another round by its eight-character ID:

```sh
LICHESS_ROUND=xxxxxxxx npm start
```

`ANALYSIS_SECONDS` sets the local analysis time per position (default 3 seconds, range 0.1–60). `LICHESS_TOKEN` optionally provides a personal token with `study:read` permission. Unauthenticated broadcast requests may be heavily rate limited.

Stockfish runs locally from the npm package using one thread, separately from the move stream. A new move interrupts analysis of the previous position. The watcher reports a possible blunder when the evaluation worsens by at least one pawn between two consecutive evaluated positions. It also reports changes of more than half a pawn from the last reported evaluation, or otherwise provides an update every ten full moves when at least ten moves have elapsed since the last evaluation notification. Updates include the move, evaluation, and last known clock values; `?` means a clock is unavailable. Clocks come from the PGN and do not count down between updates.

When multiple moves occur between completed evaluations, a blunder cannot be reliably attributed to one player, but the overall change is still tracked. Moves and results depend on broadcast updates. The stream reconnects after disconnection. On HTTP 429, requests wait at least one minute before retrying.

To test notifications, run `npm test` to display all examples, or `npm test -- update` for one. Available types are `start`, `game_start`, `move`, `update`, `change`, `blunder`, and `finish`.

## macOS position widget (prototype)

Open `macos/ChessWidget.xcodeproj` in Xcode and select the same development team for both targets in Signing & Capabilities. The macOS App Group identifier uses that team ID and is shared by both targets. Run the `ChessWidget` app, select a live broadcast and game, then add **Chess Position & Game** from the macOS widget gallery. Remove any older **Chess Position** or **Chess Position Board** widget. The app and widget require macOS 14 or later and network access.

In **Settings**, you can optionally save a Lichess personal access token with the `study:read` permission. The app stores it in macOS Keychain and uses it for its Lichess API and broadcast stream requests; remove it in Settings to return to anonymous access. The widget uses the position shared by the app. If it independently fetches a stale position while the app is closed, that request is anonymous.

With `follow:read` on the same token, **Followed players** shows who is online or playing and provides links to profiles and current games on Lichess. The app checks player statuses every 90 seconds while its window is open. If both **Notifications** and **Friend status notifications** are enabled, it reports changes after the initial status snapshot; brief changes between checks may be missed. Use the refresh button to reload the follow list as well. The links open on Lichess; selecting those games for the app's broadcast watcher is not yet supported.

While the app window is open, it streams the selected broadcast, calculates the position from the moves, saves it for the widget, and asks the system to refresh when a move arrives. The widget can also fetch a position from Lichess when no recent saved position is available. Enable **Notifications** in the app to receive move, result, and evaluation notifications; macOS will ask for permission. If several moves arrive together, one notification reports their count. The app estimates the active player's countdown and move time from the latest broadcast update; the first estimate after connecting may already be behind the real clock. Notification clocks are the last values provided by the broadcast. The app must remain open and the computer awake. macOS controls the actual widget refresh time, so the board can lag behind the stream.

The macOS app analyzes positions with Stockfish 19 (one thread, three seconds per position). The first Xcode build downloads the official universal macOS archive (about 79 MB), verifies its SHA-256 checksum, and embeds the executable and its source and license in the app. The finished app does not need Node.js or a separate Stockfish installation. Rebuilding after clearing derived data downloads the archive again. The widget overlays the evaluation from White's perspective when available for its current position. Move notifications are sent immediately and include an evaluation only if one is already available for the new position. Evaluation change and possible blunder notifications compare consecutive positions that completed analysis; rapid moves may skip intermediate evaluations. Building without signing verifies compilation but does not verify sandboxed engine execution, widget registration, or shared App Group access.

Chess pieces: Cburnett by Colin M. L. Burnett, sourced from the Lichess piece set and distributed under GPL-2.0-or-later. See `macos/Shared/Pieces.xcassets/LICENSE`.

Position calculation uses ChessKit, Copyright 2023 ChessKit, under the MIT license; see `macos/Vendor/ChessKit/LICENSE`.
