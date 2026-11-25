import { createInterface } from 'node:readline/promises';
import { stdin, stdout } from 'node:process';
import { spawn } from 'node:child_process';

const headers = process.env.LICHESS_TOKEN ? { Authorization: `Bearer ${process.env.LICHESS_TOKEN}` } : {};
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
async function getJson(url) {
  for (;;) {
    const response = await fetch(url, { headers, signal: AbortSignal.timeout(20000) });
    if (response.status === 429) {
      console.error('Lichess rate limited the request; waiting 60 seconds.');
      await sleep(60000);
      continue;
    }
    if (!response.ok) throw new Error(`Lichess returned HTTP ${response.status}.`);
    return response.json();
  }
}
async function choose(rl, items, prompt) {
  for (;;) {
    const answer = (await rl.question(prompt)).trim();
    if (!answer || answer.toLowerCase() === 'q') return null;
    if (/^\d+$/.test(answer)) {
      const index = Number(answer) - 1;
      if (index >= 0 && index < items.length) return items[index];
    }
    console.log('Enter a number from the list, or q to quit.');
  }
}
const rl = createInterface({ input: stdin, output: stdout });
try {
  console.log('Loading live broadcasts…');
  const data = await getJson('https://lichess.org/api/broadcast/top');
  const broadcasts = (data.active || []).filter(item => item.round?.ongoing && item.round?.id);
  if (!broadcasts.length) throw new Error('There are currently no live broadcasts available.');
  broadcasts.forEach((item, index) => console.log(`${index + 1}. ${item.tour?.name || 'Broadcast'} – ${item.round.name}${item.tour?.info?.tc ? ` (${item.tour.info.tc})` : ''}`));
  const broadcast = await choose(rl, broadcasts, 'Choose a broadcast (number, q = quit): ');
  if (broadcast) {
    const round = broadcast.round.id;
    const detail = await getJson(`https://lichess.org/api/broadcast/-/-/${round}`);
    const games = detail.games || [];
    if (!games.length) throw new Error('There are no games available in this round yet.');
    games.forEach((game, index) => {
      const players = game.players;
      const name = players?.length === 2 && players.every(player => player?.name)
        ? players.map(player => `${player.name}${player.rating ? ` (${player.rating})` : ''}`).join(' - ')
        : game.name || game.id;
      console.log(`${index + 1}. ${name}${game.status && game.status !== '*' ? ` (${game.status})` : ''}`);
    });
    const game = await choose(rl, games, 'Choose a game (number, q = quit): ');
    if (game) {
      if (!/^[a-zA-Z0-9]{8}$/.test(game.id)) throw new Error('The game does not have a valid ID.');
      console.log(`Watching ${game.name || game.id}.`);
      rl.close();
      const child = spawn(process.execPath, ['watch.js'], { stdio: 'inherit', env: { ...process.env, LICHESS_ROUND: round, LICHESS_GAME_ID: game.id } });
      child.on('error', error => { console.error(`Could not start the watcher: ${error.message}`); process.exitCode = 1; });
      child.on('exit', (code, signal) => { if (code) process.exitCode = code; else if (signal && signal !== 'SIGINT') process.exitCode = 1; });
    }
  }
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
} finally {
  rl.close();
}
