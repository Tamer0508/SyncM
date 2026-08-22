'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const {
  collectAllPages,
  withPaging,
} = require('../src/infrastructure/spotify/paging');

/** Поддельный Spotify: отдаёт страницы и считает, как его звали. */
function makeApi(total, { withTotal = true, delayMs = 0 } = {}) {
  const stats = { calls: 0, offsets: [], inFlight: 0, maxInFlight: 0 };

  const fetchPage = async (offset, limit) => {
    stats.calls++;
    stats.offsets.push(offset);
    stats.inFlight++;
    stats.maxInFlight = Math.max(stats.maxInFlight, stats.inFlight);

    if (delayMs) await new Promise((r) => setTimeout(r, delayMs));

    const items = [];
    for (let i = offset; i < Math.min(offset + limit, total); i++) {
      items.push({ id: `item-${i}` });
    }

    stats.inFlight--;
    return {
      items,
      ...(withTotal ? { total } : {}),
      next: offset + limit < total ? `next?offset=${offset + limit}` : null,
    };
  };

  return { fetchPage, stats };
}

test('одна страница — один запрос', async () => {
  const { fetchPage, stats } = makeApi(30);
  const items = await collectAllPages(fetchPage, { pageSize: 50 });

  assert.equal(items.length, 30);
  assert.equal(stats.calls, 1);
});

test('порядок элементов сохраняется при параллельной выборке', async () => {
  const { fetchPage, stats } = makeApi(457, { delayMs: 5 });
  const items = await collectAllPages(fetchPage, { pageSize: 50, concurrency: 4 });

  assert.equal(items.length, 457);
  assert.equal(items[0].id, 'item-0');
  assert.equal(items[456].id, 'item-456');
  // Порядок строго возрастающий — страницы собраны по индексу, а не по
  // тому, какая ответила первой.
  items.forEach((item, i) => assert.equal(item.id, `item-${i}`));
  assert.equal(stats.calls, 10);
});

test('страницы идут одновременно, но не больше лимита', async () => {
  const { fetchPage, stats } = makeApi(1000, { delayMs: 10 });
  await collectAllPages(fetchPage, { pageSize: 50, concurrency: 4 });

  assert.ok(stats.maxInFlight > 1, 'запросы должны идти параллельно');
  assert.ok(stats.maxInFlight <= 4, `превышен лимит параллельности: ${stats.maxInFlight}`);
});

test('maxItems ограничивает и выборку, и число запросов', async () => {
  const { fetchPage, stats } = makeApi(5000);
  const items = await collectAllPages(fetchPage, { pageSize: 50, maxItems: 200 });

  assert.equal(items.length, 200);
  assert.equal(stats.calls, 4);
});

test('без total остаётся последовательный обход по next', async () => {
  const { fetchPage, stats } = makeApi(120, { withTotal: false });
  const items = await collectAllPages(fetchPage, { pageSize: 50 });

  assert.equal(items.length, 120);
  assert.equal(stats.calls, 3);
  assert.equal(stats.maxInFlight, 1);
});

test('пустой плейлист не роняет выборку', async () => {
  const { fetchPage } = makeApi(0);
  const items = await collectAllPages(fetchPage, { pageSize: 50 });

  assert.deepEqual(items, []);
});

test('withPaging подставляет limit и offset, не теряя остальное', () => {
  const url = withPaging('https://api.spotify.com/v1/playlists/x/items?market=RU', 100, 50);

  assert.match(url, /market=RU/);
  assert.match(url, /limit=50/);
  assert.match(url, /offset=100/);
});
