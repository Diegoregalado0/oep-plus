import { Router } from 'express';
import { query } from '../db.js';
import { wrap } from '../errors.js';
import { requireRole } from '../auth.js';

const router = Router();
router.use(requireRole('staff'));

// Rule 5. In production this runs on a schedule (pg_cron, or cron hitting this
// endpoint); it is exposed so staff can also run it on demand.
router.post('/process-pre-trip-meetings', wrap(async (req, res) => {
  const { rows } = await query(
    'SELECT * FROM process_pre_trip_meetings(COALESCE($1::timestamptz, now()))',
    [req.body?.as_of ?? null]);
  res.json({
    as_of: req.body?.as_of ?? new Date().toISOString(),
    no_shows: rows.filter((r) => r.action === 'no_show'),
    promotions: rows.filter((r) => r.action === 'promoted'),
  });
}));

// Certification catalog.
router.get('/certifications', wrap(async (_req, res) => {
  const { rows } = await query('SELECT * FROM certifications ORDER BY code');
  res.json(rows);
}));

router.post('/certifications', wrap(async (req, res) => {
  const b = req.body;
  const { rows } = await query(
    `INSERT INTO certifications (code, name, issuing_body, description, validity_months)
     VALUES ($1,$2,$3,$4,$5) RETURNING *`,
    [b.code, b.name, b.issuing_body ?? null, b.description ?? null, b.validity_months ?? null]);
  res.status(201).json(rows[0]);
}));

export default router;
