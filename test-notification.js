import { execFile } from 'node:child_process';
import { promisify } from 'node:util';

const examples = {
  start: ['Sledování šachu', 'Hello world!'],
  zacatek: ['Partie začala', 'Gukesh D – Sindarov'],
  tah: ['Nový tah', 'Sindarov: 43...Nf6'],
  souhrn: ['Průběh partie', '20. tah, +0.40, 0:58:00 – 0:41:00'],
  zmena: ['Výrazná změna hodnocení', '+0.20 → 16. tah, +0.80, 0:58:00 – 0:41:00'],
  blunder: ['Možný blunder', 'Sindarov: 43...Nf6; +0.30 → +1.55; 0:58:00 – 0:41:00'],
  konec: ['Partie skončila', 'Gukesh D – Sindarov: 1-0'],
};
const selected = process.argv[2];
if (selected && !Object.hasOwn(examples, selected)) {
  console.error(`Neznámý typ. Vyber: ${Object.keys(examples).join(', ')}.`);
  process.exit(1);
}
const entries = selected ? [[selected, examples[selected]]] : Object.entries(examples);
for (const [index, [key, [title, message]]] of entries.entries()) {
  if (index > 0) await new Promise(resolve => setTimeout(resolve, 4000));
  console.log(`${key}: ${title} — ${message}`);
  if (process.platform === 'darwin') {
    try {
      await promisify(execFile)('osascript', ['-e', 'on run argv\ndisplay notification (item 2 of argv) with title (item 1 of argv) sound name "Glass"\nend run', title, message]);
    } catch (error) {
      console.error(`Oznámení se nepodařilo zobrazit: ${error.message}`);
      process.exitCode = 1;
    }
  }
}
