'use strict';


const DEFAULT_PAGE_SIZE = 50;
const DEFAULT_CONCURRENCY = 4;

async function collectAllPages(fetchPage, options = {}) {
  const pageSize = options.pageSize || DEFAULT_PAGE_SIZE;
  const maxItems = options.maxItems || Infinity;
  const concurrency = Math.max(1, options.concurrency || DEFAULT_CONCURRENCY);

  const first = await fetchPage(0, pageSize);
  const firstItems = first?.items || [];

  const collected = [firstItems];
  let count = firstItems.length;

  const total = Number.isInteger(first?.total) ? first.total : null;
  const target = Math.min(total ?? Infinity, maxItems);

  if (count >= target || !first?.next) {
    return flatten(collected, maxItems);
  }

  if (total === null) {
    return collectSequentially(fetchPage, collected, count, pageSize, maxItems);
  }

  const offsets = [];
  for (let offset = count; offset < target; offset += pageSize) {
    offsets.push(offset);
  }

  const pages = new Array(offsets.length);
  let next = 0;

  const worker = async () => {
    for (;;) {
      const index = next++;
      if (index >= offsets.length) return;
      const page = await fetchPage(offsets[index], pageSize);
      pages[index] = page?.items || [];
    }
  };

  await Promise.all(
    Array.from({ length: Math.min(concurrency, offsets.length) }, worker)
  );

  for (const page of pages) collected.push(page || []);
  return flatten(collected, maxItems);
}

async function collectSequentially(fetchPage, collected, count, pageSize, maxItems) {
  let offset = count;
  let hasMore = true;

  while (hasMore && count < maxItems) {
    const page = await fetchPage(offset, pageSize);
    const items = page?.items || [];
    collected.push(items);
    count += items.length;
    offset += pageSize;
    hasMore = Boolean(page?.next) && items.length > 0;
  }

  return flatten(collected, maxItems);
}

function flatten(pages, maxItems) {
  const out = [];
  for (const page of pages) {
    for (const item of page) {
      if (out.length >= maxItems) return out;
      out.push(item);
    }
  }
  return out;
}

function withPaging(url, offset, limit) {
  const parsed = new URL(url);
  parsed.searchParams.set('limit', String(limit));
  parsed.searchParams.set('offset', String(offset));
  return parsed.toString();
}

module.exports = { collectAllPages, withPaging, DEFAULT_PAGE_SIZE, DEFAULT_CONCURRENCY };
