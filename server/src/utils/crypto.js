const crypto = require('crypto');
const { promisify } = require('util');
const logger = require('../infrastructure/logger');

const scrypt = promisify(crypto.scrypt);
const randomBytes = promisify(crypto.randomBytes);

const ALGORITHM = 'aes-256-gcm';
const IV_LENGTH = 12;
const TAG_LENGTH = 16;
const PREFIX = 'enc:v2:'; // Новая версия схемы шифрования с поддержкой KDF и AAD
const KEY_LENGTH = 32;

const SCRYPT_OPTIONS = {
  N: 16384, // CPU/Memory cost
  r: 8,     // Block size
  p: 1      // Parallelization
};

let cachedKeyPromise = null;

function getSalt() {
  const salt = process.env.ENCRYPTION_SALT;
  if (!salt) {
    throw new Error('КРИТИЧЕСКАЯ ОШИБКА: ENCRYPTION_SALT не задан в .env');
  }
  if (salt.length < 16) {
    logger.warn('ENCRYPTION_SALT слишком короткий (менее 16 символов) — это снижает стойкость scrypt');
  }
  return Buffer.from(salt, 'utf-8');
}

function getEncryptionKey() {
  if (cachedKeyPromise) return cachedKeyPromise;

  cachedKeyPromise = (async () => {
    const secret = process.env.ENCRYPTION_KEY;
    if (!secret) {
      throw new Error('КРИТИЧЕСКАЯ ОШИБКА: ENCRYPTION_KEY не задан в .env');
    }

    if (/^[0-9a-f]{64}$/i.test(secret)) {
      return Buffer.from(secret, 'hex');
    }

    try {
      const salt = getSalt();
      return await scrypt(secret, salt, KEY_LENGTH, SCRYPT_OPTIONS);
    } catch (error) {
      logger.error({ err: error }, 'Ошибка деривации ключа через scrypt');
      throw new Error('Внутренняя ошибка инициализации криптографии');
    }
  })();

  cachedKeyPromise.catch(() => {
    cachedKeyPromise = null;
  });

  return cachedKeyPromise;
}

async function encrypt(plaintext, options = {}) {
  if (typeof plaintext !== 'string') {
    throw new TypeError(`Ожидалась строка для шифрования, получен тип: ${typeof plaintext}`);
  }
  if (plaintext.length === 0) {
    throw new Error('Попытка зашифровать пустую строку');
  }

  const { aad } = options;

  try {
    const key = await getEncryptionKey();
    const iv = await randomBytes(IV_LENGTH);
    const cipher = crypto.createCipheriv(ALGORITHM, key, iv);

    if (aad) {
      cipher.setAAD(Buffer.from(aad, 'utf8'));
    }

    const encrypted = Buffer.concat([
      cipher.update(plaintext, 'utf8'),
      cipher.final()
    ]);

    const authTag = cipher.getAuthTag();
    const payload = Buffer.concat([iv, authTag, encrypted]).toString('base64');

    return `${PREFIX}${payload}`;
  } catch (error) {
    logger.error({ err: error }, 'Encrypt error');
    throw new Error('Ошибка шифрования данных');
  }
}

async function decrypt(payload, options = {}) {
  if (typeof payload !== 'string') {
    throw new TypeError(`Ожидалась строка для расшифровки, получен тип: ${typeof payload}`);
  }

  const { strict = true, aad } = options;

  const isEncrypted = payload.startsWith(PREFIX);

  if (!isEncrypted) {
    if (strict) {
      throw new Error('Недопустимый формат данных: отсутствует префикс шифрования');
    }
    return payload; // legacy mode — только при явном strict: false
  }

  try {
    const key = await getEncryptionKey();
    const b64Data = payload.slice(PREFIX.length);
    const data = Buffer.from(b64Data, 'base64');

    if (data.length < IV_LENGTH + TAG_LENGTH) {
      throw new Error('Слишком короткий payload, данные повреждены');
    }

    const iv = data.subarray(0, IV_LENGTH);
    const authTag = data.subarray(IV_LENGTH, IV_LENGTH + TAG_LENGTH);
    const encrypted = data.subarray(IV_LENGTH + TAG_LENGTH);

    const decipher = crypto.createDecipheriv(ALGORITHM, key, iv);
    decipher.setAuthTag(authTag);

    if (aad) {
      decipher.setAAD(Buffer.from(aad, 'utf8'));
    }

    const decrypted = Buffer.concat([
      decipher.update(encrypted),
      decipher.final()
    ]);

    return decrypted.toString('utf8');
  } catch (error) {
    logger.error({ err: error }, 'Decrypt error');
    throw new Error('Ошибка расшифровки данных (неверный ключ, контекст AAD или данные повреждены)');
  }
}

module.exports = { encrypt, decrypt };