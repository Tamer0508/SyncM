const { ZodError } = require('zod');

function asyncHandler(fn) {
  return (req, res, next) => {
    Promise.resolve(fn(req, res, next)).catch((err) => {
      if (err instanceof ZodError) {
        const details = err.errors.map((e) => ({
          path: e.path.join('.'),
          message: e.message,
        }));
        return res.status(400).json({
          error: 'Ошибка валидации',
          details,
        });
      }
      next(err);
    });
  };
}

module.exports = asyncHandler;