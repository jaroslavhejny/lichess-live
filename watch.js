import { Chess } from 'chess.js';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';

const run = promisify(execFile);
const round = process.env.LICHESS_ROUND || 'xLgOJ6cb';
const token = process.env.LICHESS_TOKEN;
const interval = Number(process.env.INTERVAL_SECONDS || 30);
if (!/^[a-zA-Z0-9]{8}$/.test(round) || !Number.isFinite(interval) || interval < 10) {
  console.error('LICHESS_ROUND musí mít 8 znaků a INTERVAL_SECONDS alespoň 10.');
  process.exit(1);
}
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
const headers = token ? { Authorization: `Bearer ${token}` } : {};
let notices = Promise.resolve();
function notify(title, message) {
  console.log(`[${new Date().toLocaleString('cs-CZ')}] ${title}: ${message}`);
  notices = notices.then(async () => {
    if (process.platform !== 'darwin') return;
    try { await run('osascript', ['-e', 'on run argv\ndisplay notification (item 2 of argv) with title (item 1 of argv) sound name "Glass"\nend run', title, message]); }
    catch (error) { console.error(`Oznámení se nepodařilo zobrazit: ${error.message}`); }
  });
}
const formatEval = e => e.mate != null ? `mat ${e.mate > 0 ? '+' : ''}${e.mate}` : `${e.cp >= 0 ? '+' : ''}${(e.cp / 100).toFixed(2)}`;
const score = e => e.mate != null ? Math.sign(e.mate) * 10000 : e.cp;
const moveLabel = (move, index) => `${Math.floor(index / 2) + 1}${move.color === 'w' ? '.' : '...'}${move.san}`;
let current = null;
let previousEval = null;
let baseline = null;
let lastEvaluatedSignature = null;
let lastNoticePly = 0;
let lastMilestone = 0;
let finished = false;
let retryAfter = 0;
let gameUrl = null;
let startNotified = false;

function clocks(game, moves) {
  const comments = new Map(game.getComments().map(({ fen, comment }) => [fen, comment]));
  const replay = new Chess();
  const values = { w: null, b: null };
  for (const move of moves) {
    replay.move(move.san);
    const match = comments.get(replay.fen())?.match(/\[%clk\s+([^\]]+)\]/);
    if (match) values[move.color] = match[1].trim();
  }
  return `${values.w || '?'} – ${values.b || '?'}`;
}
function processPgn(pgn) {
  const game = new Chess();
  game.loadPgn(pgn);
  const tags = game.getHeaders();
  if (gameUrl && tags.GameURL && tags.GameURL !== gameUrl) return;
  gameUrl ||= tags.GameURL || null;
  const moves = game.history({ verbose: true });
  const signature = moves.map(m => m.san).join(' ');
  const old = current;
  const follows = old && moves.length >= old.moves.length && (old.signature === '' || signature === old.signature || signature.startsWith(old.signature + ' '));
  if (old && !follows) { console.log('Přenos opravil partii, začínám nové porovnávání hodnocení.'); previousEval = baseline = null; lastEvaluatedSignature = null; lastNoticePly = lastMilestone = 0; }
  current = { game, tags, moves, signature, fen: game.fen(), clocks: clocks(game, moves) };
  if (!startNotified && moves.length > 0 && !['1-0', '0-1', '1/2-1/2'].includes(tags.Result)) {
    notify('Partie začala', `${tags.White || 'Bílý'} – ${tags.Black || 'Černý'}${old ? '' : ' (už probíhá)'}`);
    startNotified = true;
  }
  if (!old) console.log(`${tags.White || 'Bílý'} – ${tags.Black || 'Černý'}: ${moves.length} půltahů.`);
  else if (follows) for (let i = old.moves.length; i < moves.length; i++) {
    const move = moves[i];
    notify('Nový tah', `${move.color === 'w' ? tags.White || 'Bílý' : tags.Black || 'Černý'}: ${moveLabel(move, i)}`);
  }
  if (['1-0', '0-1', '1/2-1/2'].includes(tags.Result)) {
    notify('Partie skončila', `${tags.White || 'Bílý'} – ${tags.Black || 'Černý'}: ${tags.Result}`);
    finished = true;
  }
}
async function evaluateLoop() {
  while (!finished) {
    const snapshot = current;
    if (snapshot && snapshot.signature !== lastEvaluatedSignature && Date.now() >= retryAfter) {
      try {
        const response = await fetch(`https://lichess.org/api/cloud-eval?fen=${encodeURIComponent(snapshot.fen)}`, { headers, signal: AbortSignal.timeout(20000) });
        if (response.status === 429) { retryAfter = Date.now() + 60000; console.error('Lichess omezuje požadavky, další hodnocení nejdříve za minutu.'); }
        else if (response.status === 404) console.log('Cloudové hodnocení zatím není dostupné.');
        else if (!response.ok) throw new Error(`HTTP ${response.status}`);
        else {
          const data = await response.json();
          const value = data.pvs?.[0];
          if (value && (value.cp != null || value.mate != null) && current?.signature === snapshot.signature) {
            const item = { eval: value, count: snapshot.moves.length, signature: snapshot.signature };
            const fullMove = Math.ceil(item.count / 2);
            const context = `${fullMove}. tah, ${formatEval(value)}, ${snapshot.clocks}`;
            if (!baseline) { baseline = item; lastMilestone = Math.floor(item.count / 20); lastNoticePly = lastMilestone * 20; console.log(`Výchozí hodnocení: ${context}.`); }
            else {
              const direct = previousEval && item.count === previousEval.count + 1 && (previousEval.signature === '' || item.signature.startsWith(previousEval.signature + ' '));
              const last = snapshot.moves.at(-1);
              const loss = direct ? (score(previousEval.eval) - score(value)) * (last.color === 'w' ? 1 : -1) : 0;
              if (loss >= 100) {
                notify('Možný blunder', `${last.color === 'w' ? snapshot.tags.White : snapshot.tags.Black}: ${moveLabel(last, item.count - 1)}; ${formatEval(previousEval.eval)} → ${formatEval(value)}; ${snapshot.clocks}`);
                baseline = item; lastNoticePly = item.count;
              } else if (Math.abs(score(value) - score(baseline.eval)) > 50) {
                notify('Výrazná změna hodnocení', `${formatEval(baseline.eval)} → ${context}`);
                baseline = item; lastNoticePly = item.count;
              } else if (Math.floor(item.count / 20) > lastMilestone && item.count - lastNoticePly >= 20) {
                notify('Průběh partie', context);
                baseline = item; lastNoticePly = item.count;
              }
              lastMilestone = Math.floor(item.count / 20);
            }
            previousEval = item;
            lastEvaluatedSignature = item.signature;
          }
        }
      } catch (error) { console.error(`Hodnocení selhalo: ${error.message}`); }
    }
    await sleep(interval * 1000);
  }
}
async function stream() {
  while (!finished) {
    try {
      const response = await fetch(`https://lichess.org/api/stream/broadcast/round/${round}.pgn?clocks=true`, { headers });
      if (response.status === 429) { console.error('Stream omezen, čekám 60 sekund.'); await sleep(60000); continue; }
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      console.log('Stream připojen.');
      let buffer = '';
      const decoder = new TextDecoder();
      for await (const chunk of response.body) {
        buffer += decoder.decode(chunk, { stream: true });
        let match;
        while ((match = /\r?\n\r?\n\r?\n/.exec(buffer))) {
          const pgn = buffer.slice(0, match.index).trim();
          buffer = buffer.slice(match.index + match[0].length);
          if (pgn) { try { processPgn(pgn); } catch (error) { console.error(`PGN se nepodařilo načíst: ${error.message}`); } }
          if (finished) break;
        }
        if (finished) break;
        if (buffer.length > 1000000) throw new Error('Příliš dlouhý PGN stream bez oddělovače');
      }
      if (!finished) console.log('Stream se odpojil, připojuji znovu.');
    } catch (error) { console.error(`Stream selhal: ${error.message}`); }
    if (!finished) await sleep(5000);
  }
}
console.log(`Sleduji kolo ${round}. Ctrl+C ukončí sledování.`);
notify('Sledování šachu', 'Hello world!');
void evaluateLoop();
await stream();
await notices;
process.exit(0);
