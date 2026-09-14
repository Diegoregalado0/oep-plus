import { httpStatusForDbError } from './db.js';

export class HttpError extends Error {
  constructor(status, message, details) {
    super(message);
    this.status = status;
    this.details = details;
  }
}

export const badRequest = (msg, details) => new HttpError(400, msg, details);
export const forbidden  = (msg) => new HttpError(403, msg);
export const notFound   = (msg) => new HttpError(404, msg);

// Wrap async route handlers so rejected promises reach the error middleware.
export const wrap = (fn) => (req, res, next) => Promise.resolve(fn(req, res, next)).catch(next);

export function errorHandler(err, _req, res, _next) {
  if (err instanceof HttpError) {
    return res.status(err.status).json({ error: err.message, details: err.details });
  }
  if (err.code) {
    const status = httpStatusForDbError(err);
    if (status === 500) console.error(err);
    return res.status(status).json({
      error: err.message,
      // A rule rejection is the database talking, so say which rule spoke.
      rule_violation: status === 409,
      detail: err.detail,
      constraint: err.constraint,
    });
  }
  console.error(err);
  return res.status(500).json({ error: 'internal error' });
}
