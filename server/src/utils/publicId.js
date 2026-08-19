const crypto = require('crypto');

const ALPHABET = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
const LENGTH = 8;

function generatePublicId() {
  const bytes = crypto.randomBytes(LENGTH);
  let result = '';
  for (let i = 0; i < LENGTH; i++) {
    result += ALPHABET[bytes[i] % ALPHABET.length];
  }
  return result;
}

function normalizePublicId(input) {
  if (typeof input !== 'string') return null;

  const cleaned = input
    .toUpperCase()
    .replace(/[\s\-_]/g, '')
    .replace(/O/g, '0')
    .replace(/[IL]/g, '1');

  if (cleaned.length !== LENGTH) return null;
  if (![...cleaned].every((ch) => ALPHABET.includes(ch))) return null;

  return cleaned;
}

function looksLikePublicId(input) {
  return normalizePublicId(input) !== null;
}

async function generateUniquePublicId(prisma, attempts = 5) {
  for (let i = 0; i < attempts; i++) {
    const candidate = generatePublicId();
    const taken = await prisma.user.findUnique({
      where: { publicId: candidate },
      select: { id: true },
    });
    if (!taken) return candidate;
  }
  throw new Error('Не удалось подобрать свободный публичный идентификатор');
}

module.exports = {
  ALPHABET,
  LENGTH,
  generatePublicId,
  normalizePublicId,
  looksLikePublicId,
  generateUniquePublicId,
};