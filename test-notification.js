import { execFile } from 'node:child_process';
import { promisify } from 'node:util';

const examples = {
  start: ['Chess watcher', 'Hello world!'],
  game_start: ['Game started', 'Gukesh D – Sindarov'],
  move: ['New move', 'Sindarov: 43...Nf6'],
  update: ['Game update', 'Move 20, +0.40, 0:58:00 – 0:41:00'],
  change: ['Significant evaluation change', '+0.20 → Move 16, +0.80, 0:58:00 – 0:41:00'],
  blunder: ['Possible blunder', 'Sindarov: 43...Nf6; +0.30 → +1.55; 0:58:00 – 0:41:00'],
  finish: ['Game finished', 'Gukesh D – Sindarov: 1-0'],
};
const selected = process.argv[2];
if (selected && !Object.hasOwn(examples, selected)) {
  console.error(`Unknown type. Choose: ${Object.keys(examples).join(', ')}.`);
  process.exit(1);
}
const entries = selected ? [[selected, examples[selected]]] : Object.entries(examples);
for (const [index, [key, [title, message]]] of entries.entries()) {
  if (index > 0) await new Promise(resolve => setTimeout(resolve, 4000));
  console.log(`${key}: ${title} — ${message}`);
  if (process.platform === 'darwin') {
    try {
      await promisify(execFile)('osascript', ['-e', 'on run argv\ndisplay notification (item 2 of argv) with title (item 1 of argv)\nend run', title, message]);
    } catch (error) {
      console.error(`Could not display notification: ${error.message}`);
      process.exitCode = 1;
    }
  }
}
