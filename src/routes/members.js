import { Router } from 'express';
import { query } from '../db.js';
import { wrap, notFound, forbidden, badRequest } from '../errors.js';
import { requireRole, isStaff } from '../auth.js';

const router = Router();

router.get('/', requireRole('staff'), wrap(async (req, res) => {
  const { rows } = await query(
    `SELECT id, first_name, last_name, email, phone, membership_type, membership_status, joined_on
       FROM members ORDER BY last_name, first_name`);
  res.json(rows);
}));

router.post('/', requireRole('staff'), wrap(async (req, res) => {
  const b = req.body;
  const { rows } = await query(
    `INSERT INTO members (first_name, last_name, email, phone, membership_type, membership_status)
     VALUES ($1,$2,$3,$4,$5,COALESCE($6::membership_status,'active'))
     RETURNING id, first_name, last_name, email, membership_type, membership_status, joined_on`,
    [b.first_name, b.last_name, b.email, b.phone ?? null, b.membership_type, b.membership_status ?? null]);
  res.status(201).json(rows[0]);
}));

router.patch('/:id', requireRole('staff'), wrap(async (req, res) => {
  const allowed = ['first_name', 'last_name', 'email', 'phone', 'membership_type', 'membership_status'];
  const keys = Object.keys(req.body).filter((k) => allowed.includes(k));
  if (!keys.length) throw badRequest(`editable fields: ${allowed.join(', ')}`);
  const { rows } = await query(
    `UPDATE members SET ${keys.map((k, i) => `${k} = $${i + 2}`).join(', ')}
      WHERE id = $1 RETURNING id, first_name, last_name, email, membership_type, membership_status`,
    [req.params.id, ...keys.map((k) => req.body[k])]);
  if (!rows.length) throw notFound(`member ${req.params.id} not found`);
  res.json(rows[0]);
}));

// A member's own view: registrations, waitlist positions, history, totals.
router.get('/:id/registrations', wrap(async (req, res) => {
  const id = Number(req.params.id);
  if (!isStaff(req) && !(req.actor.role === 'member' && req.actor.id === id)) {
    throw forbidden('you may only view your own registrations');
  }
  const [{ rows: regs }, { rows: summary }] = await Promise.all([
    query(
      `SELECT r.id, r.trip_id, t.name AS trip_name, t.destination, t.start_date, t.end_date,
              t.fee_cents, t.pre_trip_meeting_at, r.status, r.payment_status,
              r.amount_paid_cents, r.attended_pre_trip_meeting, r.registered_at,
              (SELECT position FROM v_waitlist w WHERE w.registration_id = r.id) AS waitlist_position
         FROM registrations r JOIN trips t ON t.id = r.trip_id
        WHERE r.member_id = $1 ORDER BY t.start_date DESC`, [id]),
    query('SELECT * FROM v_member_history WHERE member_id = $1', [id]),
  ]);
  if (!summary.length) throw notFound(`member ${id} not found`);
  res.json({ member: summary[0], registrations: regs });
}));

export default router;
