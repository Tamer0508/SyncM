const crypto = require('crypto');


const UNKNOWN = 'Неизвестное устройство';

const PLATFORMS = [
  [/windows nt/i, 'Windows'],
  [/android/i, 'Android'],
  [/(iphone|ipad|ipod)/i, 'iOS'],
  [/mac os x|macintosh/i, 'macOS'],
  [/cros/i, 'ChromeOS'],
  [/linux/i, 'Linux'],
];

const BROWSERS = [
  [/edg[ea]?\//i, 'Edge'],
  [/opr\/|opera/i, 'Opera'],
  [/yabrowser/i, 'Яндекс.Браузер'],
  [/firefox\//i, 'Firefox'],
  [/chrome\//i, 'Chrome'],
  [/safari\//i, 'Safari'],
];

const APP_UA = /dart|flutter|okhttp|cfnetwork/i;

function describeDevice(req) {
  const ua = String(req?.headers?.['user-agent'] || '').slice(0, 400);
  if (!ua) return { name: UNKNOWN, platform: null, kind: 'unknown' };

  const platform = PLATFORMS.find(([re]) => re.test(ua))?.[1] || null;

  if (APP_UA.test(ua)) {
    return {
      name: platform ? `Приложение SyncM · ${platform}` : 'Приложение SyncM',
      platform,
      kind: 'app',
    };
  }

  const browser = BROWSERS.find(([re]) => re.test(ua))?.[1] || null;
  if (!browser && !platform) return { name: UNKNOWN, platform: null, kind: 'unknown' };

  return {
    name: [browser, platform].filter(Boolean).join(' · ') || UNKNOWN,
    platform,
    kind: 'browser',
  };
}

function deviceIdFor(secret) {
  return crypto.createHash('sha256').update(String(secret)).digest('hex').slice(0, 16);
}

module.exports = { describeDevice, deviceIdFor };
