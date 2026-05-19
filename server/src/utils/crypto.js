const crypto = require('crypto');

// Алгоритм AES-256-GCM (с аутентификацией)
const ALGORITHM = 'aes-256-gcm';
const IV_LENGTH = 12;   // GCM рекомендует 12 байт
const TAG_LENGTH = 16;  // Длина auth tag
const KEY_LENGTH = 32;  // 256 бит

// Получаем ключ из переменной окружения
function getKey() {
  const secret = process.env.ENCRYPTION_KEY;
  if (!secret) {
    throw new Error('ENCRYPTION_KEY не задан в .env');
  }
  // Превращаем любую строку в 32-байтный ключ через SHA-256
  return crypto.createHash('sha256').update(secret).digest();
}

/**
 * Шифрует строку. Возвращает base64(iv + authTag + encrypted)
 */
function encrypt(plaintext) {
  if (!plaintext) return null;
  
  const key = getKey();
  const iv = crypto.randomBytes(IV_LENGTH);
  const cipher = crypto.createCipheriv(ALGORITHM, key, iv);

  const encrypted = Buffer.concat([
    cipher.update(plaintext, 'utf8'),
    cipher.final()
  ]);

  const authTag = cipher.getAuthTag();

  // Склеиваем iv + authTag + encrypted и кодируем в base64
  return Buffer.concat([iv, authTag, encrypted]).toString('base64');
}

/**
 * Расшифровывает base64-строку обратно в plaintext
 */
function decrypt(payload) {
  if (!payload) return null;

  try {
    const key = getKey();
    const data = Buffer.from(payload, 'base64');

    const iv = data.subarray(0, IV_LENGTH);
    const authTag = data.subarray(IV_LENGTH, IV_LENGTH + TAG_LENGTH);
    const encrypted = data.subarray(IV_LENGTH + TAG_LENGTH);

    const decipher = crypto.createDecipheriv(ALGORITHM, key, iv);
    decipher.setAuthTag(authTag);

    const decrypted = Buffer.concat([
      decipher.update(encrypted),
      decipher.final()
    ]);

    return decrypted.toString('utf8');
  } catch (error) {
    console.error('Decrypt error:', error.message);
    return null;
  }
}

module.exports = { encrypt, decrypt };
