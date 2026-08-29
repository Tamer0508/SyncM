const crypto = require('crypto');
const logger = require('../infrastructure/logger');

const ALL_ZERO_TRACE_ID = '0'.repeat(32);
const ALL_ZERO_SPAN_ID = '0'.repeat(16);

const TRACE_ID_REGEX = /^[0-9a-f]{32}$/;
const SPAN_ID_REGEX = /^[0-9a-f]{16}$/;
const FLAGS_REGEX = /^[0-9a-f]{2}$/;

const DEFAULT_FLAGS = '01';

function generateHex(bytes) {
  return crypto.randomBytes(bytes).toString('hex');
}

function parseTraceParent(header) {
  if (!header || typeof header !== 'string') return null;

  const parts = header.trim().split('-');
  if (parts.length !== 4) return null;

  const [version, traceId, spanId, flags] = parts;

  if (version !== '00') return null;
  if (traceId === ALL_ZERO_TRACE_ID || !TRACE_ID_REGEX.test(traceId)) return null;
  if (spanId === ALL_ZERO_SPAN_ID || !SPAN_ID_REGEX.test(spanId)) return null;
  if (!FLAGS_REGEX.test(flags)) return null;

  return { traceId, spanId, flags };
}

module.exports = function requestIdMiddleware(req, res, next) {
  const parsed = parseTraceParent(req.headers['traceparent']);

  const traceId = parsed ? parsed.traceId : generateHex(16);
  const parentSpanId = parsed ? parsed.spanId : null;
  const spanId = generateHex(8);
  const flags = parsed ? parsed.flags : DEFAULT_FLAGS;

  req.traceId = traceId;
  req.spanId = spanId;
  req.parentSpanId = parentSpanId;
  req.requestId = traceId;
  req.id = traceId;
  req.traceFlags = flags;

  if (typeof res.setHeader === 'function') {
    res.setHeader('traceparent', `00-${traceId}-${spanId}-${flags}`);
    res.setHeader('X-Request-Id', traceId);
  }

  req.log = logger.child({
    traceId,
    spanId,
    ...(parentSpanId && { parentSpanId }),
    requestId: traceId,
  });

  next();
};