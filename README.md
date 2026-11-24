# Chess Broadcast Watcher

Watch live Lichess broadcasts and receive notifications for new moves, evaluation changes, and game results. The watcher stops when the selected game ends.

```sh
npm install
npm run broadcast
```

Choose a live broadcast and then a game from the numbered lists. The available broadcasts depend on what is live on Lichess. If the game finishes while you are choosing, the watcher exits after receiving its result. Press Ctrl+C to stop watching.

Keep the terminal and computer running; sleep pauses monitoring. Notifications currently require macOS: allow Script Editor notifications, including in Focus mode. On other systems, messages appear in the terminal.

To watch the default broadcast round, use `npm start`. Its default is [game 1 of the 2026 World Chess Championship](https://lichess.org/broadcast/fide-world-chess-championship-2026/game-1/xLgOJ6cb); it does not automatically select the latest round. To specify another round by its eight-character ID:

```sh
LICHESS_ROUND=xxxxxxxx npm start
```

`ANALYSIS_SECONDS` sets the local analysis time per position (default 3 seconds, range 0.1–60). `LICHESS_TOKEN` optionally provides a personal token with `study:read` permission. Unauthenticated broadcast requests may be heavily rate limited.

Stockfish runs locally from the npm package using one thread, separately from the move stream. A new move interrupts analysis of the previous position. The watcher reports a possible blunder when the evaluation worsens by at least one pawn between two consecutive evaluated positions. It also reports changes of more than half a pawn from the last reported evaluation, or otherwise provides an update every ten full moves when at least ten moves have elapsed since the last evaluation notification. Updates include the move, evaluation, and last known clock values; `?` means a clock is unavailable. Clocks come from the PGN and do not count down between updates.

When multiple moves occur between completed evaluations, a blunder cannot be reliably attributed to one player, but the overall change is still tracked. Moves and results depend on broadcast updates. The stream reconnects after disconnection. On HTTP 429, requests wait at least one minute before retrying.

To test notifications, run `npm test` to display all examples, or `npm test -- update` for one. Available types are `start`, `game_start`, `move`, `update`, `change`, `blunder`, and `finish`.
