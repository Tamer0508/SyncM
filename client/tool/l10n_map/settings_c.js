const fs = require('fs');
const path = require('path');

const entries = {
  hiddenList: {
    ru: 'Скрыто: {items}',
    en: 'Hidden: {items}',
    placeholders: { items: { type: 'String' } },
  },
  sessionsActiveCount: {
    ru: 'Активные сессии · {count}',
    en: 'Active sessions · {count}',
    placeholders: { count: { type: 'int' } },
  },
  invitesCount: {
    ru: 'Приглашения · {count}',
    en: 'Invitations · {count}',
    placeholders: { count: { type: 'int' } },
  },
  invitesWaiting: {
    ru: '{count, plural, one{Одно приглашение ждёт ответа} few{{count} приглашения ждут ответа} many{{count} приглашений ждут ответа} other{{count} приглашения ждут ответа}}',
    en: '{count, plural, one{One invitation is waiting} other{{count} invitations are waiting}}',
    placeholders: { count: { type: 'int' } },
  },
  sessionEndMessage: {
    ru: '«{name}» закроется у всех участников.',
    en: '“{name}” will close for everyone.',
    placeholders: { name: { type: 'String' } },
  },
  notificationsOffOne: {
    ru: 'Выключено: {what}',
    en: 'Disabled: {what}',
    placeholders: { what: { type: 'String' } },
  },
  notificationsHint: {
    ru: 'Настройки общие для всех ваших устройств. Сами заявки и приглашения продолжают приходить — выключается только карточка поверх экрана.',
    en: 'These settings apply to all your devices. Requests and invitations still arrive — only the card on top of the screen goes away.',
  },
  securitySignOutEverywhereMessage: {
    ru: 'Все сеансы завершатся, включая этот. Так стоит поступить, если в списке есть чужое устройство.',
    en: 'Every session will end, including this one. Do this if you see a device that isn’t yours.',
  },
  cacheFriendsCount: {
    ru: 'друзей: {count}',
    en: 'friends: {count}',
    placeholders: { count: { type: 'int' } },
  },
  cacheSessionsCount: {
    ru: 'сессий: {count}',
    en: 'sessions: {count}',
    placeholders: { count: { type: 'int' } },
  },
  updatedMinutesAgo: {
    ru: 'обновлено {count, plural, one{{count} минуту} few{{count} минуты} many{{count} минут} other{{count} минуты}} назад',
    en: 'updated {count, plural, one{{count} minute} other{{count} minutes}} ago',
    placeholders: { count: { type: 'int' } },
  },
  updatedHoursAgo: {
    ru: 'обновлено {count, plural, one{{count} час} few{{count} часа} many{{count} часов} other{{count} часа}} назад',
    en: 'updated {count, plural, one{{count} hour} other{{count} hours}} ago',
    placeholders: { count: { type: 'int' } },
  },
  updatedDaysAgo: {
    ru: 'обновлено {count, plural, one{{count} день} few{{count} дня} many{{count} дней} other{{count} дня}} назад',
    en: 'updated {count, plural, one{{count} day} other{{count} days}} ago',
    placeholders: { count: { type: 'int' } },
  },
  aboutVersion: {
    ru: 'Версия {version}',
    en: 'Version {version}',
    placeholders: { version: { type: 'String' } },
  },
  clockSummary: {
    ru: 'Часы: {offset} мс · пинг: {ping} мс',
    en: 'Clock: {offset} ms · ping: {ping} ms',
    placeholders: { offset: { type: 'String' }, ping: { type: 'int' } },
  },
  deleteAccountMessage: {
    ru: 'Профиль, друзья и история сессий будут удалены безвозвратно. Это действие нельзя отменить.',
    en: 'Your profile, friends and session history will be deleted for good. This cannot be undone.',
  },
  exportSaved: {
    ru: 'Файл сохранён: {path}',
    en: 'File saved: {path}',
    placeholders: { path: { type: 'String' } },
  },
  sizeMegabytes: {
    ru: '{value} МБ',
    en: '{value} MB',
    placeholders: { value: { type: 'String' } },
  },
  sizeKilobytes: {
    ru: '{value} КБ',
    en: '{value} KB',
    placeholders: { value: { type: 'int' } },
  },
  sizeBytes: {
    ru: '{value} Б',
    en: '{value} B',
    placeholders: { value: { type: 'int' } },
  },
  cacheInMemory: {
    ru: 'В памяти: {size}',
    en: 'In memory: {size}',
    placeholders: { size: { type: 'String' } },
  },
  cacheOnDisk: {
    ru: 'На диске: {disk} · в памяти: {memory}',
    en: 'On disk: {disk} · in memory: {memory}',
    placeholders: { disk: { type: 'String' }, memory: { type: 'String' } },
  },
  spotifyConnectedAs: {
    ru: 'Подключён · {name}',
    en: 'Connected · {name}',
    placeholders: { name: { type: 'String' } },
  },
  nameDialogTooShort: {
    ru: 'Минимум {count, plural, one{{count} символ} few{{count} символа} many{{count} символов} other{{count} символа}}',
    en: 'At least {count, plural, one{{count} character} other{{count} characters}}',
    placeholders: { count: { type: 'int' } },
  },
  nameDialogTooLong: {
    ru: 'Не более {count, plural, one{{count} символа} few{{count} символов} many{{count} символов} other{{count} символов}}',
    en: 'No more than {count, plural, one{{count} character} other{{count} characters}}',
    placeholders: { count: { type: 'int' } },
  },
  privacyHiddenWarning: {
    ru: 'При полностью скрытом профиле друзьям сложнее понять, когда вас звать слушать вместе.',
    en: 'With a fully hidden profile it’s harder for friends to tell when to invite you to listen together.',
  },
  blockedPeopleCount: {
    ru: '{count, plural, one{{count} человек} few{{count} человека} many{{count} человек} other{{count} человека}}',
    en: '{count, plural, one{{count} person} other{{count} people}}',
    placeholders: { count: { type: 'int' } },
  },
};

const root = path.resolve(__dirname, '..', '..');

for (const locale of ['ru', 'en']) {
  const arbPath = path.join(root, 'lib', 'l10n', `app_${locale}.arb`);
  const arb = JSON.parse(fs.readFileSync(arbPath, 'utf8'));

  for (const [key, value] of Object.entries(entries)) {
    arb[key] = value[locale];
    if (value.placeholders) {
      arb[`@${key}`] = { placeholders: value.placeholders };
    }
  }

  const sorted = Object.fromEntries(
    Object.entries(arb).sort(([a], [b]) =>
      a.replace('@', '').localeCompare(b.replace('@', ''))
    )
  );

  fs.writeFileSync(arbPath, `${JSON.stringify(sorted, null, 2)}\n`);
}

console.log(`Добавлено ключей с подстановками: ${Object.keys(entries).length}`);
