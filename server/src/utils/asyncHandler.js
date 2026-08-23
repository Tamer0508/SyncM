const { ZodError } = require('zod');
const { t } = require('../infrastructure/i18n');

function asyncHandler(fn) {
  return (req, res, next) => {
    Promise.resolve(fn(req, res, next)).catch((err) => {
      if (res.headersSent) return next(err);

      if (err instanceof ZodError) {
        const details = err.issues.map((e) => ({
          path: e.path.join('.'),
          message: e.message,
        }));
        return res.status(400).json({
          error: t(req, 'validationFailed'),
          details,
        });
      }
      next(err);
    });
  };
}

module.exports = asyncHandler;