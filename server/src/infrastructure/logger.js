const pino = require('pino');

const level = process.env.LOG_LEVEL || 'info';
const isProd = process.env.NODE_ENV === 'production';

let logger;

try {
  if (!isProd) {
    try {
      // preferred: use pino with pino-pretty transport (pino v7+)
      logger = pino({
        level,
        transport: {
          target: 'pino-pretty',
          options: {
            colorize: true,
            translateTime: 'SYS:standard',
            ignore: 'pid,hostname',
          },
        },
      });
    } catch (e) {
      // fallback for configurations where transport isn't supported
      try {
        const transport = pino.transport({
          target: 'pino-pretty',
          options: {
            colorize: true,
            translateTime: 'SYS:standard',
            ignore: 'pid,hostname',
          },
        });
        logger = pino({ level }, transport);
      } catch (e2) {
        logger = pino({ level });
        logger.warn('pino-pretty not available, falling back to JSON logs');
      }
    }
  } else {
    logger = pino({ level });
  }
} catch (err) {
  // last-resort fallback to stderr/stdout
  const fallbackMessage = ['Failed to initialize logger, falling back to console:', err?.message || err].join(' ');
  process.stderr.write(`${fallbackMessage}\n`);
  logger = {
    info: (...args) => process.stdout.write(args.join(' ') + '\n'),
    warn: (...args) => process.stderr.write(args.join(' ') + '\n'),
    error: (...args) => process.stderr.write(args.join(' ') + '\n'),
    debug: (...args) => process.stdout.write(args.join(' ') + '\n'),
    child: () => logger,
  };
}

module.exports = logger;
