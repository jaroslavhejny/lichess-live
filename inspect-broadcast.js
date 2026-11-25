const headers = process.env.LICHESS_TOKEN ? { Authorization: `Bearer ${process.env.LICHESS_TOKEN}` } : {};

async function getJson(url) {
  const response = await fetch(url, { headers, signal: AbortSignal.timeout(20000) });
  if (!response.ok) throw new Error(`Lichess returned HTTP ${response.status} for ${url}.`);
  return response.json();
}

try {
  const data = await getJson('https://lichess.org/api/broadcast/top');
  const broadcast = (data.active || []).find(item => item.round?.ongoing && item.round?.id);
  if (!broadcast) throw new Error('There are currently no live broadcasts available.');

  console.log('Broadcast from /api/broadcast/top:');
  console.log(JSON.stringify(broadcast, null, 2));

  const detail = await getJson(`https://lichess.org/api/broadcast/-/-/${broadcast.round.id}`);
  const { games, ...roundDetails } = detail;
  console.log('\nRound detail (with the first game only):');
  console.log(JSON.stringify({ ...roundDetails, games: games?.slice(0, 1) }, null, 2));
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
}
