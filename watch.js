import { Chess } from 'chess.js';
import { execFile, spawn } from 'node:child_process';
import { createRequire } from 'node:module';
import { createInterface } from 'node:readline';
import { promisify } from 'node:util';

const run = promisify(execFile);
const round = process.env.LICHESS_ROUND || 'xLgOJ6cb';
const token = process.env.LICHESS_TOKEN;
const selectedGame = process.env.LICHESS_GAME_ID;
const analysisMs = Number(process.env.ANALYSIS_SECONDS || 3) * 1000;
if (!/^[a-zA-Z0-9]{8}$/.test(round) || !Number.isFinite(analysisMs) || analysisMs < 100 || analysisMs > 60000) {
  console.error('LICHESS_ROUND must contain 8 characters and ANALYSIS_SECONDS must be between 0.1 and 60.');
  process.exit(1);
}
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
const headers = token ? { Authorization: `Bearer ${token}` } : {};
let notices = Promise.resolve();
function notify(title, message) {
  console.log(`[${new Date().toLocaleString('en-US')}] ${title}: ${message}`);
  notices = notices.then(async () => {
    if (process.platform !== 'darwin') return;
    try { await run('osascript', ['-e', 'on run argv\ndisplay notification (item 2 of argv) with title (item 1 of argv) sound name "Glass"\nend run', title, message]); }
    catch (error) { console.error(`Could not display notification: ${error.message}`); }
  });
}
const formatEval = e => e.mate != null ? `mate ${e.mate > 0 ? '+' : ''}${e.mate}` : `${e.cp >= 0 ? '+' : ''}${(e.cp / 100).toFixed(2)}`;
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
const enginePath = createRequire(import.meta.url)('stockfish').findEngine('lite-single');
const engine = spawn(process.execPath, [enginePath], { stdio: ['pipe', 'pipe', 'inherit'] });
let pendingAnalysis = null;
let engineFailure = null;
createInterface({ input: engine.stdout }).on('line', line => {
  if (!pendingAnalysis) return;
  const match = line.match(/\bscore (cp|mate) (-?\d+)/);
  if (match && !/\b(?:lowerbound|upperbound)\b/.test(line)) {
    const value = Number(match[2]) * pendingAnalysis.perspective;
    pendingAnalysis.value = { [match[1]]: value };
  }
  if (line.startsWith('bestmove ')) {
    const pending = pendingAnalysis;
    pendingAnalysis = null;
    pending.resolve(pending.value);
  }
});
function failEngine(error) {
  engineFailure = error;
  if (pendingAnalysis) { const pending = pendingAnalysis; pendingAnalysis = null; pending.reject(error); }
}
engine.on('error', failEngine);
engine.on('exit', code => { if (!finished) failEngine(new Error(`Stockfish exited (code ${code}).`)); });
function analyse(fen) {
  if (engineFailure) return Promise.reject(engineFailure);
  return new Promise((resolve, reject) => {
    pendingAnalysis = { resolve, reject, value: null, perspective: fen.split(' ')[1] === 'w' ? 1 : -1 };
    engine.stdin.write(`position fen ${fen}\ngo movetime ${analysisMs}\n`);
  });
}


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
  if (selectedGame && (tags.GameURL || tags.Site || '').split('/').filter(Boolean).at(-1) !== selectedGame) return;
  if (gameUrl && tags.GameURL && tags.GameURL !== gameUrl) return;
  gameUrl ||= tags.GameURL || null;
  const moves = game.history({ verbose: true });
  const signature = moves.map(m => m.san).join(' ');
  const old = current;
  const follows = old && moves.length >= old.moves.length && (old.signature === '' || signature === old.signature || signature.startsWith(old.signature + ' '));
  if (old && !follows) { console.log('The broadcast corrected the game; resetting evaluation comparisons.'); previousEval = baseline = null; lastEvaluatedSignature = null; lastNoticePly = lastMilestone = 0; }
  if (pendingAnalysis && old && old.signature !== signature) engine.stdin.write('stop\n');
  current = { game, tags, moves, signature, fen: game.fen(), clocks: clocks(game, moves) };
  if (!startNotified && moves.length > 0 && !['1-0', '0-1', '1/2-1/2'].includes(tags.Result)) {
    notify('Game started', `${tags.White || 'White'} – ${tags.Black || 'Black'}${old ? '' : ' (already in progress)'}`);
    startNotified = true;
  }
  if (!old) {
    console.log(`${tags.White || 'White'} – ${tags.Black || 'Black'}: ${moves.length} half-moves.`);
    if (tags.GameURL || tags.Site) console.log(`Game link: ${tags.GameURL || tags.Site}`);
  }
  else if (follows) for (let i = old.moves.length; i < moves.length; i++) {
    const move = moves[i];
    notify('New move', `${move.color === 'w' ? tags.White || 'White' : tags.Black || 'Black'}: ${moveLabel(move, i)}`);
  }
  if (['1-0', '0-1', '1/2-1/2'].includes(tags.Result)) {
    notify('Game finished', `${tags.White || 'White'} – ${tags.Black || 'Black'}: ${tags.Result}`);
    finished = true;
  }
}
async function evaluateLoop() {
  while (!finished) {
    const snapshot = current;
    if (snapshot && snapshot.signature !== lastEvaluatedSignature) {
      try {
        const value = await analyse(snapshot.fen);
        if (value && current?.signature === snapshot.signature && !finished) {
            const item = { eval: value, count: snapshot.moves.length, signature: snapshot.signature };
            const fullMove = Math.ceil(item.count / 2);
            const context = `Move ${fullMove}, ${formatEval(value)}, ${snapshot.clocks}`;
            if (!baseline) { baseline = item; lastMilestone = Math.floor(item.count / 20); lastNoticePly = lastMilestone * 20; console.log(`Initial evaluation: ${context}.`); }
            else {
              const direct = previousEval && item.count === previousEval.count + 1 && (previousEval.signature === '' || item.signature.startsWith(previousEval.signature + ' '));
              const last = snapshot.moves.at(-1);
              const loss = direct ? (score(previousEval.eval) - score(value)) * (last.color === 'w' ? 1 : -1) : 0;
              if (loss >= 100) {
                notify('Possible blunder', `${last.color === 'w' ? snapshot.tags.White : snapshot.tags.Black}: ${moveLabel(last, item.count - 1)}; ${formatEval(previousEval.eval)} → ${formatEval(value)}; ${snapshot.clocks}`);
                if (snapshot.tags.GameURL || snapshot.tags.Site) console.log(`Game link: ${snapshot.tags.GameURL || snapshot.tags.Site}`);
                baseline = item; lastNoticePly = item.count;
              } else if (Math.abs(score(value) - score(baseline.eval)) > 50) {
                notify('Significant evaluation change', `${formatEval(baseline.eval)} → ${context}`);
                baseline = item; lastNoticePly = item.count;
              } else if (Math.floor(item.count / 20) > lastMilestone && item.count - lastNoticePly >= 20) {
                notify('Game update', context);
                baseline = item; lastNoticePly = item.count;
              }
              lastMilestone = Math.floor(item.count / 20);
            }
            previousEval = item;
            lastEvaluatedSignature = item.signature;
        }
      } catch (error) { console.error(`Evaluation failed: ${error.message}`); return; }
    }
    await sleep(250);
  }
}
async function stream() {
  while (!finished) {
    if (Date.now() < retryAfter) await sleep(retryAfter - Date.now());
    try {
      const response = await fetch(`https://lichess.org/api/stream/broadcast/round/${round}.pgn?clocks=true`, { headers });
      if (response.status === 429) { retryAfter = Math.max(retryAfter, Date.now() + 60000); console.error('Stream rate limited; waiting 60 seconds.'); continue; }
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      console.log('Stream connected.');
      let buffer = '';
      const decoder = new TextDecoder();
      for await (const chunk of response.body) {
        buffer += decoder.decode(chunk, { stream: true });
        let match;
        while ((match = /\r?\n\r?\n\r?\n/.exec(buffer))) {
          const pgn = buffer.slice(0, match.index).trim();
          buffer = buffer.slice(match.index + match[0].length);
          if (pgn) { try { processPgn(pgn); } catch (error) { console.error(`Could not parse PGN: ${error.message}`); } }
          if (finished) break;
        }
        if (finished) break;
        if (buffer.length > 1000000) throw new Error('PGN stream exceeded the maximum length without a separator');
      }
      if (!finished) console.log('Stream disconnected; reconnecting.');
    } catch (error) { console.error(`Stream failed: ${error.message}`); }
    if (!finished) await sleep(5000);
  }
}
console.log(`Watching round ${round}. Press Ctrl+C to stop.`);
notify('Chess watcher', 'Hello world!');
void evaluateLoop();
await stream();
await notices;
engine.kill();
process.exit(0);
