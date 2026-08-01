const pino = require('pino');

const level = process.env.LOG_LEVEL || 'info';
const isProd = process.env.NODE_ENV === 'production';

const PRETTY_OPTIONS = {
  colorize: true,
  translateTime: 'SYS:standard',
  ignore: 'pid,hostname',
};

// Расширенный список для предотвращения утечек чувствительных данных в логи
const REDACT_PATHS = [
  'req.headers.cookie',
  'req.headers.authorization',
  'password',
  'accessToken',
  'refreshToken',
  '*.password',
  '*.accessToken',
  '*.refreshToken',
  // Защита от утечек токенов через объекты ошибок Axios
  'err.config.headers.Authorization',
  'err.config.headers.authorization',
  'err.response.request._header',
  'err.config.data', // тело запроса Axios — там тоже бывают пароли и токены
];

function prettyTransportAvailable() {
  try {
    require.resolve('pino-pretty');
    return true;
  } catch (err) {
    return false;
  }
}

function createFallbackLogger(bindings = {}) {
  const prefix = Object.keys(bindings).length ? `${JSON.stringify(bindings)} ` : '';
  const write = (stream) => (...args) => {
    const parts = args.map((a) => {
      if (a instanceof Error) return a.stack || a.message;
      return typeof a === 'object' ? JSON.stringify(a) : String(a);
    });
    stream.write(`${prefix}${parts.join(' ')}\n`);
  };
  return {
    trace: write(process.stdout),
    debug: write(process.stdout),
    info: write(process.stdout),
    warn: write(process.stderr),
    error: write(process.stderr),
    fatal: write(process.stderr),
    child: (childBindings) => createFallbackLogger({ ...bindings, ...childBindings }),
  };
}

let logger;

try {
  const usePretty = !isProd && prettyTransportAvailable();

  logger = usePretty
    ? pino({
        level,
        redact: { paths: REDACT_PATHS, censor: '[REDACTED]' },
        transport: { target: 'pino-pretty', options: PRETTY_OPTIONS },
      })
    : pino({
        level,
        redact: { paths: REDACT_PATHS, censor: '[REDACTED]' },
      });

  if (!isProd && !usePretty) {
    logger.warn('pino-pretty is not installed, falling back to standard JSON logs');
  }
} catch (err) {
  logger = createFallbackLogger();
  logger.error('Failed to initialize Pino logger, falling back to console:', err);
}

module.exports = logger;