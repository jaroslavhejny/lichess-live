# Mac App Store submission draft

Draft for review before submission. The app name is provisional. Confirm all claims against a signed distribution build, and replace the placeholders before publishing.

## Product page

**Name:** Chess Broadcast Widget

**Subtitle:** Live chess on your desktop

**Promotional text:**

Follow live chess broadcasts, keep the board on your desktop, and get move updates with local Stockfish analysis.

**Description:**

Follow live chess broadcasts from Lichess without losing sight of your work. Choose a broadcast and a game, then add a chessboard widget to your Mac desktop.

• Follow a live game and see its current position in the desktop widget.
• Receive optional notifications about moves, game results, evaluation changes, and possible blunders.
• See position evaluations calculated locally with Stockfish.
• View estimated player clocks and move time in the app.
• Connect an optional Lichess personal access token to see followed players who are online or playing, and receive status notifications.

The app requires an internet connection and macOS 14 or later. For live monitoring and notifications, keep the app window open and your Mac awake. Widget refreshes are scheduled by macOS, so the displayed position may lag behind the broadcast. Clock values are estimates.

Chess Broadcast Widget is an independent app and is not affiliated with Lichess or Stockfish.

**Keywords:** chess,broadcast,live,widget,board,lichess,stockfish,tournament,analysis,notifications

**Support URL:** https://jaroslavhejny.github.io/lichess-live/

**Privacy policy URL:** https://jaroslavhejny.github.io/lichess-live/privacy.html

## Screenshot plan

Provide at least one Mac screenshot; use 1280 × 800, 1440 × 900, 2560 × 1600, or 2880 × 1800 pixels. Capture the real, current interface and make sure most images show the app in use.

1. **Follow live chess broadcasts** — app with a selected tournament and game.
2. **Keep the board on your desktop** — actual desktop widget alongside the app.
3. **Get updates as games unfold** — a real move or evaluation notification with the app visible.
4. **Analyze positions with Stockfish** — the selected game and its evaluation.
5. **See when followed players are online** — followed-players panel, using information approved for public display.

Avoid including a token, private account information, unrelated notifications, or personal files in captures. Apple controls widget refresh timing; don't imply instantaneous updates.

## Privacy policy draft

Replace the placeholders and review this draft against the final build, support setup, distribution, and applicable law before publishing. The privacy disclosures in App Store Connect must also match the final app and any third-party services.

### Privacy Policy for Chess Broadcast Widget

Last updated: November 26, 2026

Jaroslav Hejný operates Chess Broadcast Widget. Contact: jaroslavhejny(at)email.cz.

**Lichess requests.** The app connects to Lichess to retrieve broadcasts, game positions, and related information. If you use followed-player features, the app also requests your following list and player statuses. These requests are made to Lichess and are subject to its privacy policy: https://lichess.org/privacy. Like other internet services, Lichess may receive network information such as your IP address.

**Optional access token.** You may add a Lichess personal access token in Settings. The app stores the token in macOS Keychain and sends it to Lichess when making authenticated requests, including when checking the token. You can remove the saved token in Settings and revoke it through your Lichess account. The widget may make anonymous requests to Lichess when fetching a stale position independently.

**Information on your Mac.** The app stores settings, your selected game, and game position information locally. The app and its widget share the information needed to display the selected game through a macOS App Group. Stockfish position analysis runs locally on your Mac.

**Notifications.** If you enable notifications and grant macOS permission, the app can display notifications about games and followed-player status. You can turn these off in the app or in macOS System Settings.

**Contact.** For questions about this policy, contact jaroslavhejny(at)email.cz.

## Before submission

- [ ] Confirm the app name, subtitle, countries, pricing, and support contact.
- [ ] Publish the reviewed privacy policy and a support page with contact details; add an easily accessible privacy policy link in the app.
- [ ] Complete App Privacy answers, age rating, export compliance, and any applicable trader information in App Store Connect.
- [ ] Review Lichess API and branding terms and all third-party licenses, including Stockfish, ChessKit, and the chess pieces; verify distribution compatibility.
- [ ] Configure signing, bundle IDs and App Group for both targets; archive and test a signed distribution build, including the embedded Stockfish executable and widget.
- [ ] Capture and upload Mac screenshots from the final UI. Check notification permissions and live broadcast behavior.
- [ ] Add App Review instructions explaining how to select a live broadcast, add the widget, and enable optional notifications and token-based features. Note that available broadcasts change.
- [ ] Upload the build, complete metadata, select a release option, and submit for review.
