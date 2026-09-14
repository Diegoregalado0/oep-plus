import { Router } from 'express';
import { query } from '../db.js';
import { wrap, notFound, forbidden, badRequest } from '../errors.js';
import { requireRole, isStaff } from '../auth.js';

const router = Router();

const ownGuideOrStaff = (req, id) => {
  if (isStaff(req)) return;
  if (req.actor.role === 'guide' && req.actor.id === Number(id)) return;
  throw forbidden('guides may only view their own record');
};

router.get('/', requireRole('staff'), wrap(async (_req, res) => {
  const { rows } = await query(
    `SELECT g.id, g.first_name, g.last_name, g.email, g.phone, g.hired_on, g.active,
            COALESCE(json_agg(json_build_object(
                'code', v.code, 'certification', v.certification,
                'expires_on', v.expires_on, 'urgency', v.urgency)
              ORDER BY v.expires_on) FILTER (WHERE v.code IS NOT NULL), '[]') AS certifications
       FROM guides g LEFT JOIN v_certification_expiry v ON v.guide_id = g.id
      GROUP BY g.id ORDER BY g.last_name`);
  res.json(rows);
}));

router.post('/', requireRole('staff'), wrap(async (req, res) => {
  const b = req.body;
  const { rows } = await query(
    `INSERT INTO guides (first_name, last_name, email, phone, hired_on)
     VALUES ($1,$2,$3,$4,COALESCE($5, CURRENT_DATE))
     RETURNING id, first_name, last_name, email, hired_on, active`,
    [b.first_name, b.last_name, b.email, b.phone ?? null, b.hired_on ?? null]);
  res.status(201).json(rows[0]);
}));

// A guide's own certifications and expiry dates.
router.get('/:id/certifications', wrap(async (req, res) => {
  ownGuideOrStaff(req, req.params.id);
  const { rows } = await query(
    `SELECT c.code, c.name AS certification, c.issuing_body, gc.issued_on, gc.expires_on,
            gc.certificate_no, (gc.expires_on - CURRENT_DATE) AS days_until_expiry,
            gc.expires_on >= CURRENT_DATE AS currently_valid
       FROM guide_certifications gc JOIN certifications c ON c.id = gc.certification_id
      WHERE gc.guide_id = $1 ORDER BY gc.expires_on DESC`, [req.params.id]);
  res.json(rows);
}));

router.post('/:id/certifications', requireRole('staff'), wrap(async (req, res) => {
  const b = req.body;
  if (!b.certification_id && !b.code) throw badRequest('certification_id or code is required');
  const { rows } = await query(
    `INSERT INTO guide_certifications (guide_id, certification_id, issued_on, expires_on, certificate_no)
     VALUES ($1, COALESCE($2, (SELECT id FROM certifications WHERE code = $3)), $4, $5, $6)
     RETURNING *`,
    [req.params.id, b.certification_id ?? null, b.code ?? null,
     b.issued_on, b.expires_on, b.certificate_no ?? null]);
  res.status(201).json(rows[0]);
}));

// Trips a guide is assigned to.
router.get('/:id/trips', wrap(async (req, res) => {
  ownGuideOrStaff(req, req.params.id);
  const { rows } = await query(
    `SELECT t.id AS trip_id, t.name, t.destination, t.difficulty, t.start_date, t.end_date,
            t.status, t.pre_trip_meeting_at, tg.role,
            c.confirmed, c.waitlisted, c.capacity,
            cert.code AS required_certification
       FROM trip_guides tg
       JOIN trips t ON t.id = tg.trip_id
       JOIN v_trip_capacity c ON c.trip_id = t.id
       LEFT JOIN certifications cert ON cert.id = t.required_certification_id
      WHERE tg.guide_id = $1 ORDER BY t.start_date DESC`, [req.params.id]);
  res.json(rows);
}));

export default router;
