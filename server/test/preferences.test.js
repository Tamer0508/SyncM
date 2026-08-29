const test = require('node:test');
const assert = require('node:assert');

const {
  DEFAULTS,
  preferencesSchema,
  withDefaults,
  mergePreferences,
} = require('../src/utils/preferences');

test('withDefaults дополняет пустую запись значениями по умолчанию', () => {
  const prefs = withDefaults(null);

  assert.deepStrictEqual(prefs.notifications, { ...DEFAULTS.notifications });
  assert.strictEqual(prefs.appearance.themeMode, 'system');
  assert.strictEqual(prefs.updatedAt, 0);
});

test('withDefaults сохраняет то, что человек менял', () => {
  const prefs = withDefaults({
    notifications: { sessionInvites: false },
    appearance: { accent: 'plum' },
    updatedAt: 42,
  });

  assert.strictEqual(prefs.notifications.sessionInvites, false);
  assert.strictEqual(prefs.notifications.friendRequests, true);
  assert.strictEqual(prefs.appearance.accent, 'plum');
  assert.strictEqual(prefs.appearance.compact, false);
  assert.strictEqual(prefs.updatedAt, 42);
});

test('mergePreferences не стирает группу, которой нет в изменении', () => {
  const stored = {
    notifications: { sessionInvites: false },
    appearance: { accent: 'clay', compact: true },
    updatedAt: 1,
  };

  const merged = mergePreferences(stored, {
    appearance: { accent: 'indigo' },
    updatedAt: 2,
  });

  assert.strictEqual(merged.appearance.accent, 'indigo');
  assert.strictEqual(merged.appearance.compact, true);
  assert.strictEqual(merged.notifications.sessionInvites, false);
  assert.strictEqual(merged.updatedAt, 2);
});

test('mergePreferences ставит своё время, если клиент его не прислал', () => {
  const before = Date.now();
  const merged = mergePreferences({}, { appearance: { compact: true } });

  assert.ok(merged.updatedAt >= before);
});

test('схема отвергает неизвестные поля и значения вне допустимых', () => {
  assert.throws(() => preferencesSchema.parse({ appearance: { accent: 'neon' } }));
  assert.throws(() => preferencesSchema.parse({ appearance: { textScale: 3 } }));
  assert.throws(() => preferencesSchema.parse({ somethingElse: true }));
  assert.throws(() => preferencesSchema.parse({ notifications: { unknown: true } }));

  const parsed = preferencesSchema.parse({
    notifications: { friendRequests: false },
    updatedAt: 10,
  });
  assert.deepStrictEqual(parsed, {
    notifications: { friendRequests: false },
    updatedAt: 10,
  });
});
