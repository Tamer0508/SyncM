const test = require('node:test');
const assert = require('node:assert');

const { describeDevice, deviceIdFor } = require('../src/utils/device');

const req = (userAgent) => ({ headers: userAgent ? { 'user-agent': userAgent } : {} });

test('браузеры узнаются вместе с системой', () => {
  const chrome = describeDevice(
    req('Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36')
  );
  assert.strictEqual(chrome.name, 'Chrome · Windows');
  assert.strictEqual(chrome.kind, 'browser');

  const edge = describeDevice(
    req('Mozilla/5.0 (Windows NT 10.0) AppleWebKit/537.36 Chrome/120.0 Safari/537.36 Edg/120.0')
  );
  assert.strictEqual(edge.name, 'Edge · Windows');

  const chromeMac = describeDevice(
    req('Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/120.0 Safari/537.36')
  );
  assert.strictEqual(chromeMac.name, 'Chrome · macOS');
});

test('клиент приложения отличается от браузера', () => {
  const app = describeDevice(req('Dart/3.7 (dart:io)'));
  assert.strictEqual(app.kind, 'app');
  assert.strictEqual(app.name, 'Приложение SyncM');

  const android = describeDevice(req('Dart/3.7 (dart:io); Android 14'));
  assert.strictEqual(android.platform, 'Android');
  assert.strictEqual(android.name, 'Приложение SyncM · Android');
});

test('без User-Agent устройство остаётся неизвестным', () => {
  const unknown = describeDevice(req(null));
  assert.strictEqual(unknown.kind, 'unknown');
  assert.strictEqual(unknown.platform, null);
});

test('идентификатор сеанса не раскрывает сам секрет', () => {
  const token = 'a'.repeat(64);
  const id = deviceIdFor(token);

  assert.strictEqual(id.length, 16);
  assert.ok(/^[a-f0-9]{16}$/.test(id));
  assert.ok(!token.includes(id));
  assert.strictEqual(id, deviceIdFor(token));
  assert.notStrictEqual(id, deviceIdFor('b'.repeat(64)));
});
