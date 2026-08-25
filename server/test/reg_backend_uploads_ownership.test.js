'use strict';

// Regression-покрытие к BUG #001 / #002.
//
// Проверяет обе стороны исправления:
//   1) чужой файл удалить нельзя, с какого бы домена ни пришёл URL;
//   2) свой прежний файл по-прежнему подчищается — уборка не сломана.

const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');

const { resolveOwnedUploadPath, isOwnedUploadName } = require('../src/utils/uploads');

const AVATARS_DIR = path.resolve(__dirname, '../uploads/avatars');
const OPTS = { dir: AVATARS_DIR, pathPrefix: '/uploads/avatars/' };

const OWNER = 'owner-user-id';
const VICTIM = 'victim-user-id';

const ownFile = `${OWNER}_1700000000000_aaaaaaaaaaaa.png`;
const victimFile = `${VICTIM}_1700000000000_deadbeefcafe.png`;

test('свой прежний аватар по-прежнему удаляется', () => {
  const resolved = resolveOwnedUploadPath(
    `https://syncm.example/uploads/avatars/${ownFile}`,
    { ...OPTS, ownerId: OWNER, skipFileName: `${OWNER}_1700000001000_bbbbbbbbbbbb.png` }
  );

  assert.equal(
    resolved,
    path.join(AVATARS_DIR, ownFile),
    'штатная уборка предыдущего аватара не должна была пострадать от исправления'
  );
});

test('относительный URL своего файла тоже чистится', () => {
  const resolved = resolveOwnedUploadPath(`/uploads/avatars/${ownFile}`, {
    ...OPTS,
    ownerId: OWNER,
  });

  assert.equal(resolved, path.join(AVATARS_DIR, ownFile));
});

test('только что загруженный файл не удаляется сам собой', () => {
  const resolved = resolveOwnedUploadPath(
    `https://syncm.example/uploads/avatars/${ownFile}`,
    { ...OPTS, ownerId: OWNER, skipFileName: ownFile }
  );

  assert.equal(resolved, null, 'skipFileName обязан защищать свежий файл');
});

test('чужой файл не удаляется даже с нашего домена', () => {
  const resolved = resolveOwnedUploadPath(
    `https://syncm.example/uploads/avatars/${victimFile}`,
    { ...OPTS, ownerId: OWNER }
  );

  assert.equal(resolved, null);
});

test('чужой файл не удаляется через подставленный внешний домен', () => {
  for (const url of [
    `https://evil.tld/uploads/avatars/${victimFile}`,
    `http://evil.tld/uploads/avatars/${victimFile}`,
    `https://evil.tld:8443/uploads/avatars/${victimFile}`,
  ]) {
    assert.equal(
      resolveOwnedUploadPath(url, { ...OPTS, ownerId: OWNER }),
      null,
      `хост не должен влиять на решение: ${url}`
    );
  }
});

test('путь мимо каталога загрузок отбрасывается', () => {
  for (const url of [
    `https://syncm.example/uploads/covers/${ownFile}`,
    `https://syncm.example/etc/${ownFile}`,
    `https://syncm.example/${ownFile}`,
  ]) {
    assert.equal(resolveOwnedUploadPath(url, { ...OPTS, ownerId: OWNER }), null, url);
  }
});

test('попытка выйти из каталога не проходит', () => {
  for (const url of [
    'https://syncm.example/uploads/avatars/../../.env',
    'https://syncm.example/uploads/avatars/%2e%2e%2f%2e%2e%2f.env',
    'https://syncm.example/uploads/avatars/',
  ]) {
    assert.equal(resolveOwnedUploadPath(url, { ...OPTS, ownerId: OWNER }), null, url);
  }
});

test('мусор вместо URL не роняет проверку', () => {
  for (const url of [null, undefined, '', 'не url', 'javascript:alert(1)', 'data:text/plain,x']) {
    assert.equal(resolveOwnedUploadPath(url, { ...OPTS, ownerId: OWNER }), null, String(url));
  }
});

test('без владельца не удаляется ничего', () => {
  assert.equal(
    resolveOwnedUploadPath(`https://syncm.example/uploads/avatars/${ownFile}`, {
      ...OPTS,
      ownerId: null,
    }),
    null,
    'отсутствие ownerId должно запрещать удаление, а не разрешать его'
  );
});

test('признак владения смотрит на полный идентификатор, а не на префикс', () => {
  // 'owner-user' — префикс 'owner-user-id', но это другой пользователь.
  assert.equal(isOwnedUploadName(ownFile, 'owner-user'), false);
  assert.equal(isOwnedUploadName(ownFile, OWNER), true);
});
