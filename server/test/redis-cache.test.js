'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

delete process.env.REDIS_URL;
const {
  parseVersionedReply,
  buildVersionedKey,
  READ_VERSIONED_SCRIPT,
} = require('../src/infrastructure/redis');

test('попадание: версия и значение из одного ответа', () => {
  const reply = ['3', JSON.stringify({ items: [1, 2] })];
  const { fullKey, value } = parseVersionedReply('db:friends-list:u1', 'page:0', reply);

  assert.equal(fullKey, buildVersionedKey('db:friends-list:u1', 3, 'page:0'));
  assert.deepEqual(value, { items: [1, 2] });
});

test('промах: ответ из одной версии', () => {
  const { fullKey, value } = parseVersionedReply('ns', 'k', ['7']);

  assert.equal(fullKey, buildVersionedKey('ns', 7, 'k'));
  assert.equal(value, null, 'промах обязан быть null — иначе getOrSet отдаст пустоту как результат');
});

test('версии ещё нет: считаем нулевой', () => {
  const { fullKey, value } = parseVersionedReply('ns', 'k', ['0']);

  assert.equal(fullKey, buildVersionedKey('ns', 0, 'k'));
  assert.equal(value, null);
});

test('пустой ответ не роняет разбор', () => {
  assert.deepEqual(parseVersionedReply('ns', 'k', []), {
    fullKey: buildVersionedKey('ns', 0, 'k'),
    value: null,
  });
  assert.deepEqual(parseVersionedReply('ns', 'k', null), {
    fullKey: buildVersionedKey('ns', 0, 'k'),
    value: null,
  });
});

test('повреждённое значение считается промахом, а не ошибкой', () => {
  const { value } = parseVersionedReply('ns', 'k', ['1', 'не json']);
  assert.equal(value, null);
});

test('скрипт собирает тот же ключ, что и buildVersionedKey', () => {
  const namespace = 'ns';
  const key = 'k';
  const version = 5;

  const fromScript = `cache:${namespace}:v` + version + `:${key}`;
  assert.equal(fromScript, buildVersionedKey(namespace, version, key));
  assert.match(READ_VERSIONED_SCRIPT, /ARGV\[1\] \.\. ver \.\. ARGV\[2\]/);
});
