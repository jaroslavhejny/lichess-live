# Sledování šachové partie

Skript sleduje živý Lichess Broadcast stream. Oznámí začátek partie i každý nový tah; po výsledku se ukončí. Výchozí kolo je [první partie MS 2026](https://lichess.org/broadcast/fide-world-chess-championship-2026/game-1/xLgOJ6cb).

```sh
npm install
npm start
```

Nech terminál a Mac běžet; uspání počítače sledování pozastaví. Ukončení ručně: Ctrl+C. Pro oznámení povol v macOS Script Editor i v režimu Soustředění. `npm run test` postupně zobrazí všechny typy oznámení. Jednotlivé typy lze vyzkoušet například pomocí `npm run test -- souhrn`; dostupné jsou `start`, `zacatek`, `tah`, `souhrn`, `zmena`, `blunder` a `konec`.

Další kolo vyber podle osmiznakového ID v URL přenosu:

```sh
LICHESS_ROUND=xxxxxxxx npm start
```

Volitelně nastav `ANALYSIS_SECONDS` (doba lokální analýzy pozice, výchozí 3 sekundy, rozsah 0,1–60) nebo `LICHESS_TOKEN` (osobní token s oprávněním `study:read`). Neověřené požadavky na broadcasty mohou být výrazně omezené.

Hodnocení počítá lokálně Stockfish z npm balíčku, jedním vláknem a odděleně od streamu tahů. Při novém tahu se výpočet starší pozice přeruší. Skript upozorní na možný blunder při zhoršení alespoň o 1,00 pěšce mezi dvěma bezprostředně sousedními pozicemi. Dále upozorní při změně o více než 0,50 pěšce vůči poslednímu oznámenému hodnocení; jinak po 10., 20., 30. a dalších desátých celých tazích, pokud od posledního upozornění na hodnocení uběhlo alespoň 10 tahů. Souhrn obsahuje tah, hodnocení a poslední známé časy bílého a černého; `?` znamená nedostupný čas. Časy jsou z PGN a mezi aktualizacemi neodpočítávají.

Pokud mezi dokončenými hodnoceními proběhne více tahů, nelze blunder spolehlivě připsat jednomu hráči, ale souhrnná změna se přesto sleduje. Výsledky i tahy závisejí na aktualizacích přenosu; po výpadku se stream znovu připojí. Při HTTP 429 skript čeká alespoň minutu.

## Výběr živého přenosu

```sh
npm run vyber
```

Vyber číslo živého broadcastu a následně číslo partie. Skript spustí sledování zvolené partie; ukončíš ho pomocí Ctrl+C. Seznam vychází z aktuálně aktivních přenosů Lichess, takže nabídka závisí na tom, co právě běží. Pokud partie skončí během výběru, sledování skončí po načtení jejího výsledku.

Při HTTP 429 výběr počká minutu a zkusí požadavek znovu. Při omezení streamu sledování počká minutu před dalším připojením.
