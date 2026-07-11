const crypto = require('crypto');
const logger = require('../infrastructure/logger');

function generateHex(bytes) {
  if (typeof crypto.randomUUID === 'function') {
    return crypto.randomUUID().replace(/-/g, '');
  }
  return crypto.randomBytes(bytes).toString('hex');
}

function parseTraceParent(header) {
  if (!header) return null;
  const parts = header.split('-');
  if (parts.length !== 4) return null;
  const [version, traceId, spanId] = parts;
  if (version !== '00') return null; // Пока поддерживаем только версию 00
  if (traceId.length !== 32 || spanId.length !== 16) return null;
  if (!/^[0-9a-fA-F]+$/.test(traceId) || !/^[0-9a-fA-F]+$/.test(spanId)) return null;
  return { traceId, spanId };
}

/**
 * Генерация нового trace-id (32 hex) и span-id (16 hex)
 */
function generateTraceContext() {
  return {
    traceId: generateHex(16), // 32 символа hex
    spanId: generateHex(8),   // 16 символов hex
  };
}

module.exports = function requestId(req, res, next) {
  // 1. Попытка извлечь W3C Trace Context
  const traceparentHeader = req.headers['traceparent'];
  let traceCtx = parseTraceParent(traceparentHeader);

  // 2. Если traceparent нет — генерируем новый контекст
  if (!traceCtx) {
    traceCtx = generateTraceContext();
  }

  // 3. Добавляем в запрос
  req.traceId = traceCtx.traceId;
  req.spanId = traceCtx.spanId;
  req.requestId = req.traceId; // Основной идентификатор запроса
  req.id = req.requestId;      // Для обратной совместимости с req.id

  // 4. Устанавливаем заголовок traceparent в ответе (если res.setHeader доступен)
  if (typeof res.setHeader === 'function') {
    // Формируем traceparent ответа: версия 00, traceId без изменений, spanId может быть тот же или новый
    res.setHeader('traceparent', `00-${traceCtx.traceId}-${traceCtx.spanId}-01`);
    // Для обратной совместимости с X-Request-Id
    res.setHeader('X-Request-Id', req.requestId);
  }

  // 5. Создаём дочерний логгер с контекстом
  req.log = logger.child({ traceId: req.traceId, requestId: req.requestId });

  next();
};