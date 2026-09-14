import { Router } from 'express';
import { query } from '../db.js';
import { wrap, notFound, forbidden, badRequest } from '../errors.js';
import { requireRole, isStaff } from '../auth.js';

const router = Router();

// Register for a trip. Members register themselves; staff may register anyone.
// Capacity and waitlisting are decided by the database, not here.
router.post('/', wrap(async (req, res) => {
  let memberId = req.body.member_id;
  if (!isStaff(req)) {
    if (req.actor.role === 'guest') throw forbidden('sign in to register for a trip');
    if (req.actor.role !== 'member') throw forbidden('guides register through staff');
    if (memberId && memberId !== req.actor.id) throw forbidden('you may only register yourself');
    memberId = req.actor.id;
  }
  if (!memberId) throw badRequest('member_id is required');
  if (!req.body.trip_id) throw badRequest('trip_id is required');

  // Payment is not a separate step: the database records the trip fee as paid
  // as part of creating the registration.
  const { rows } = await query(
    `INSERT INTO registrations (trip_id, member_id)
     VALUES ($1,$2)
     RETURNING id, trip_id, member_id, status, registered_at, payment_status, amount_paid_cents`,
    [req.body.trip_id, memberId]);

  const reg = rows[0];
  if (reg.status === 'waitlisted') {
    const { rows: pos } = await query(
      'SELECT position FROM v_waitlist WHERE registration_id = $1', [reg.id]);
    reg.waitlist_position = pos[0]?.position ?? null;
    reg.message = 'trip is full; you were added to the waitlist and will be promoted automatically if a spot opens';
  }
  res.status(201).json(reg);
}));

router.get('/:id', wrap(async (req, res) => {
  const { rows } = await query(
    `SELECT r.*, t.name AS trip_name, t.start_date,
            (SELECT position FROM v_waitlist w WHERE w.registration_id = r.id) AS waitlist_position
       FROM registrations r JOIN trips t ON t.id = r.trip_id WHERE r.id = $1`, [req.params.id]);
  if (!rows.length) throw notFound(`registration ${req.params.id} not found`);
  if (!isStaff(req) && rows[0].member_id !== req.actor.id) {
    throw forbidden('you may only view your own registrations');
  }
  res.json(rows[0]);
}));

// Cancel. A released confirmed spot promotes the next waitlisted member (rule 2).
router.delete('/:id', wrap(async (req, res) => {
  const { rows: found } = await query(
    'SELECT id, member_id, trip_id, status FROM registrations WHERE id = $1', [req.params.id]);
  if (!found.length) throw notFound(`registration ${req.params.id} not found`);
  const reg = found[0];
  if (!isStaff(req) && reg.member_id !== req.actor.id) {
    throw forbidden('you may only cancel your own registration');
  }
  if (['cancelled', 'completed', 'no_show'].includes(reg.status)) {
    throw badRequest(`registration is already ${reg.status}`);
  }

  const { rows } = await query(
    `UPDATE registrations SET status = 'cancelled', cancel_reason = COALESCE($2,'cancelled by ' || $3)
      WHERE id = $1 RETURNING id, trip_id, member_id, status, cancelled_at`,
    [reg.id, req.body?.reason ?? null, req.actor.role]);

  // Report who the database promoted, if anyone.
  const { rows: promoted } = await query(
    `SELECT id, member_id FROM registrations
      WHERE trip_id = $1 AND status = 'confirmed' AND confirmed_at >= $2
      ORDER BY confirmed_at DESC LIMIT 1`, [reg.trip_id, rows[0].cancelled_at]);

  res.json({ cancelled: rows[0], promoted_from_waitlist: promoted[0] ?? null });
}));

// Staff overrides: payment, attendance, and manual status changes.
router.patch('/:id', requireRole('staff'), wrap(async (req, res) => {
  const allowed = ['status', 'payment_status', 'amount_paid_cents',
                   'attended_pre_trip_meeting', 'cancel_reason'];
  const keys = Object.keys(req.body).filter((k) => allowed.includes(k));
  if (!keys.length) throw badRequest(`editable fields: ${allowed.join(', ')}`);
  const sets = keys.map((k, i) => `${k} = $${i + 2}`);
  const { rows } = await query(
    `UPDATE registrations SET ${sets.join(', ')} WHERE id = $1 RETURNING *`,
    [req.params.id, ...keys.map((k) => req.body[k])]);
  if (!rows.length) throw notFound(`registration ${req.params.id} not found`);
  res.json(rows[0]);
}));

export default router;
