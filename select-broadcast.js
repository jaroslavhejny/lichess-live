import { createInterface } from 'node:readline/promises';
import { stdin, stdout } from 'node:process';
import { spawn } from 'node:child_process';

const headers = process.env.LICHESS_TOKEN ? { Authorization: `Bearer ${process.env.LICHESS_TOKEN}` } : {};
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
async function getJson(url) {
  for (;;) {
    const response = await fetch(url, { headers, signal: AbortSignal.timeout(20000) });
    if (response.status === 429) {
      console.error('Lichess omezuje požadavky, čekám 60 sekund.');
      await sleep(60000);
      continue;
    }
    if (!response.ok) throw new Error(`Lichess vrátil HTTP ${response.status}.`);
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
    console.log('Zadej číslo z nabídky, nebo q pro ukončení.');
  }
}
const rl = createInterface({ input: stdin, output: stdout });
try {
  console.log('Načítám živé broadcasty…');
  const data = await getJson('https://lichess.org/api/broadcast/top');
  const broadcasts = (data.active || []).filter(item => item.round?.ongoing && item.round?.id);
  if (!broadcasts.length) throw new Error('Momentálně nejsou k dispozici žádné živé broadcasty.');
  broadcasts.forEach((item, index) => console.log(`${index + 1}. ${item.tour?.name || 'Broadcast'} – ${item.round.name}`));
  const broadcast = await choose(rl, broadcasts, 'Vyber broadcast (číslo, q = konec): ');
  if (broadcast) {
    const round = broadcast.round.id;
    const detail = await getJson(`https://lichess.org/api/broadcast/-/-/${round}`);
    const games = detail.games || [];
    if (!games.length) throw new Error('V tomto kole zatím nejsou dostupné žádné partie.');
    games.forEach((game, index) => console.log(`${index + 1}. ${game.name || game.id} ${game.status && game.status !== '*' ? `(${game.status})` : ''}`));
    const game = await choose(rl, games, 'Vyber partii (číslo, q = konec): ');
    if (game) {
      if (!/^[a-zA-Z0-9]{8}$/.test(game.id)) throw new Error('Partie nemá platné ID.');
      console.log(`Sleduji ${game.name || game.id}.`);
      rl.close();
      const child = spawn(process.execPath, ['watch.js'], { stdio: 'inherit', env: { ...process.env, LICHESS_ROUND: round, LICHESS_GAME_ID: game.id } });
      child.on('error', error => { console.error(`Sledování se nepodařilo spustit: ${error.message}`); process.exitCode = 1; });
      child.on('exit', (code, signal) => { if (code) process.exitCode = code; else if (signal && signal !== 'SIGINT') process.exitCode = 1; });
    }
  }
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
} finally {
  rl.close();
}
