const test = require('node:test');
const assert = require('node:assert');

const { t, languageOf } = require('../src/infrastructure/i18n');

const req = (acceptLanguage) => ({
  headers: acceptLanguage ? { 'accept-language': acceptLanguage } : {},
});

test('без заголовка отвечаем по-русски', () => {
  assert.strictEqual(languageOf(req(null)), 'ru');
  assert.strictEqual(t(req(null), 'notFriends'), 'Вы не друзья с этим пользователем');
});

test('язык берётся из Accept-Language с учётом весов', () => {
  assert.strictEqual(languageOf(req('en-US,en;q=0.9')), 'en');
  assert.strictEqual(languageOf(req('ru;q=0.3, en;q=0.9')), 'en');
  assert.strictEqual(languageOf(req('en;q=0.2, ru;q=0.8')), 'ru');
});

test('неизвестный язык не ломает ответ', () => {
  assert.strictEqual(languageOf(req('fr-FR,fr;q=0.9')), 'ru');
  assert.strictEqual(t(req('fr'), 'sessionNotFound'), 'Сессия не найдена');
});

test('подстановки работают на обоих языках', () => {
  assert.strictEqual(
    t(req('en'), 'invitesDisabled', { name: 'Alex' }),
    'Alex has turned session invitations off'
  );
  assert.strictEqual(
    t(req(null), 'invitesDisabled', { name: 'Аня' }),
    'Аня отключил приглашения в сессии'
  );
});

test('неизвестный ключ виден как ключ, а не как пустая строка', () => {
  assert.strictEqual(t(req(null), 'noSuchKey'), 'noSuchKey');
});
