import express from 'express';
import { fileURLToPath } from 'node:url';
import { identify } from './auth.js';
import { errorHandler, wrap } from './errors.js';
import { query } from './db.js';
import trips from './routes/trips.js';
import registrations from './routes/registrations.js';
import members from './routes/members.js';
import guides from './routes/guides.js';
import equipment from './routes/equipment.js';
import reports from './routes/reports.js';
import admin from './routes/admin.js';

export function createApp() {
  const app = express();
  app.use(express.json());

  // The test console at http://localhost:3000 -- static, so it loads before the
  // identity middleware and then declares its role per request like any client.
  app.use(express.static(fileURLToPath(new URL('../public', import.meta.url))));

  app.get('/health', wrap(async (_req, res) => {
    const { rows } = await query('SELECT count(*)::int AS trips FROM trips');
    res.json({ ok: true, trips: rows[0].trips });
  }));

  app.use(identify);

  // "Who am I" convenience routes for the guide and member views.
  app.get('/me/certifications', (req, res, next) =>
    res.redirect(307, `/guides/${req.actor.id}/certifications`));
  app.get('/me/trips', (req, res) => res.redirect(307, `/guides/${req.actor.id}/trips`));
  app.get('/me/registrations', (req, res) =>
    res.redirect(307, `/members/${req.actor.id}/registrations`));

  app.use('/trips', trips);
  app.use('/registrations', registrations);
  app.use('/members', members);
  app.use('/guides', guides);
  app.use('/equipment', equipment);
  app.use('/reports', reports);
  app.use('/admin', admin);

  app.use((_req, res) => res.status(404).json({ error: 'no such endpoint' }));
  app.use(errorHandler);
  return app;
}
