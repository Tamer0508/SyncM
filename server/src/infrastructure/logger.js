const pino = require('pino');

const isProd = process.env.NODE_ENV === 'production';
const level = process.env.LOG_LEVEL || (isProd ? 'info' : 'debug');

let logger;
try {
  if (!isProd) {
    // try to use pretty transport when available
    try {
      const transport = pino.transport({
        target: 'pino-pretty',
        options: {
          colorize: true,
          translateTime: 'SYS:standard',
          ignore: 'pid,hostname',
        }
      });
      logger = pino({ level }, transport);
    } catch (e) {
      // fallback if pino-pretty isn't installed or transport isn't supported
      logger = pino({ level });
    }
  } else {
    logger = pino({ level });
  }
} catch (err) {
  // last-resort fallback
  // eslint-disable-next-line no-console
  console.error('Failed to initialize logger, falling back to console:', err?.message || err);
  logger = {
    info: (...args) => console.log(...args),
    warn: (...args) => console.warn(...args),
    error: (...args) => console.error(...args),
    debug: (...args) => console.debug(...args),
    child: () => logger,
  };
}

module.exports = logger;
