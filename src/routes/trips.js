import { Router } from 'express';
import { query } from '../db.js';
import { wrap, notFound, forbidden, badRequest } from '../errors.js';
import { requireRole, isStaff } from '../auth.js';

const router = Router();

const tripFields = `id, name, destination, description, difficulty, start_date, end_date,
                    capacity, fee_cents, required_certification_id, pre_trip_meeting_at, status`;

// Browse upcoming trips (members, guides, staff).
router.get('/', wrap(async (req, res) => {
  const { status, from, difficulty } = req.query;
  const params = [];
  const where = [];
  if (status) { params.push(status); where.push(`c.status = $${params.length}`); }
  // Drafts are staff-only whatever was asked for, so ?status=draft cannot leak them.
  if (!isStaff(req)) where.push(`c.status <> 'draft'`);
  if (difficulty) { params.push(difficulty); where.push(`c.difficulty = $${params.length}`); }
  params.push(from || new Date().toISOString().slice(0, 10));
  where.push(`c.start_date >= $${params.length}`);

  const { rows } = await query(
    `SELECT c.*, t.fee_cents, t.pre_trip_meeting_at, t.required_certification_id,
            cert.code AS required_certification
       FROM v_trip_capacity c
       JOIN trips t ON t.id = c.trip_id
       LEFT JOIN certifications cert ON cert.id = t.required_certification_id
      WHERE ${where.join(' AND ')}
      ORDER BY c.start_date, c.name`, params);
  res.json(rows);
}));

router.get('/:id', wrap(async (req, res) => {
  const { rows } = await query(
    `SELECT c.*, t.description, t.fee_cents, t.pre_trip_meeting_at,
            cert.code AS required_certification,
            COALESCE((SELECT json_agg(json_build_object(
                        'guide_id', g.id, 'name', g.first_name || ' ' || g.last_name,
                        'role', tg.role) ORDER BY tg.role)
                      FROM trip_guides tg JOIN guides g ON g.id = tg.guide_id
                     WHERE tg.trip_id = t.id), '[]') AS guides,
            COALESCE((SELECT json_agg(json_build_object(
                        'equipment_id', e.id, 'name', e.name, 'quantity', te.quantity,
                        'checked_out_at', te.checked_out_at, 'checked_in_at', te.checked_in_at,
                        'return_condition', te.return_condition) ORDER BY e.name)
                      FROM trip_equipment te JOIN equipment e ON e.id = te.equipment_id
                     WHERE te.trip_id = t.id), '[]') AS equipment
       FROM v_trip_capacity c
       JOIN trips t ON t.id = c.trip_id
       LEFT JOIN certifications cert ON cert.id = t.required_certification_id
      WHERE c.trip_id = $1`, [req.params.id]);
  if (!rows.length) throw notFound(`trip ${req.params.id} not found`);
  if (rows[0].status === 'draft' && !isStaff(req)) throw notFound(`trip ${req.params.id} not found`);
  res.json(rows[0]);
}));

// Roster: staff, or a guide assigned to this trip.
router.get('/:id/roster', wrap(async (req, res) => {
  if (!isStaff(req)) {
    if (req.actor.role !== 'guide') throw forbidden('only staff and assigned guides may view a roster');
    const { rowCount } = await query(
      'SELECT 1 FROM trip_guides WHERE trip_id = $1 AND guide_id = $2',
      [req.params.id, req.actor.id]);
    if (!rowCount) throw forbidden('you are not assigned to this trip');
  }
  const [{ rows: roster }, { rows: waitlist }] = await Promise.all([
    query(`SELECT * FROM v_trip_roster WHERE trip_id = $1 AND status IN ('confirmed','completed','no_show')
            ORDER BY member_name`, [req.params.id]),
    query('SELECT * FROM v_waitlist WHERE trip_id = $1 ORDER BY position', [req.params.id]),
  ]);
  res.json({ trip_id: Number(req.params.id), roster, waitlist });
}));

// ------------------------------------------------------------------ staff only

router.post('/', requireRole('staff'), wrap(async (req, res) => {
  const b = req.body;
  const { rows } = await query(
    `INSERT INTO trips (name, destination, description, difficulty, start_date, end_date,
                        capacity, fee_cents, required_certification_id, pre_trip_meeting_at, status)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,COALESCE($11::trip_status,'open'))
     RETURNING ${tripFields}`,
    [b.name, b.destination, b.description, b.difficulty, b.start_date, b.end_date,
     b.capacity, b.fee_cents ?? 0, b.required_certification_id ?? null,
     b.pre_trip_meeting_at ?? null, b.status ?? null]);
  res.status(201).json(rows[0]);
}));

const EDITABLE = ['name', 'destination', 'description', 'difficulty', 'start_date', 'end_date',
                  'capacity', 'fee_cents', 'required_certification_id', 'pre_trip_meeting_at', 'status'];

router.patch('/:id', requireRole('staff'), wrap(async (req, res) => {
  const keys = Object.keys(req.body).filter((k) => EDITABLE.includes(k));
  if (!keys.length) throw badRequest(`nothing to update; editable fields: ${EDITABLE.join(', ')}`);
  const sets = keys.map((k, i) => `${k} = $${i + 2}`);
  const { rows } = await query(
    `UPDATE trips SET ${sets.join(', ')} WHERE id = $1 RETURNING ${tripFields}`,
    [req.params.id, ...keys.map((k) => req.body[k])]);
  if (!rows.length) throw notFound(`trip ${req.params.id} not found`);
  res.json(rows[0]);
}));

// Cancelling a trip releases its gear and refunds are left to staff.
router.post('/:id/cancel', requireRole('staff'), wrap(async (req, res) => {
  const { rows } = await query(
    `UPDATE trips SET status = 'cancelled' WHERE id = $1 AND status <> 'completed'
     RETURNING ${tripFields}`, [req.params.id]);
  if (!rows.length) throw notFound(`no open trip ${req.params.id} to cancel`);
  const { rowCount } = await query(
    `UPDATE registrations SET status = 'cancelled', cancel_reason = COALESCE($2,'trip cancelled')
      WHERE trip_id = $1 AND status IN ('confirmed','waitlisted')`,
    [req.params.id, req.body?.reason ?? null]);
  res.json({ trip: rows[0], registrations_cancelled: rowCount });
}));

router.post('/:id/complete', requireRole('staff'), wrap(async (req, res) => {
  const { rows } = await query(
    `UPDATE trips SET status = 'completed' WHERE id = $1 RETURNING ${tripFields}`, [req.params.id]);
  if (!rows.length) throw notFound(`trip ${req.params.id} not found`);
  const { rowCount } = await query(
    `UPDATE registrations SET status = 'completed' WHERE trip_id = $1 AND status = 'confirmed'`,
    [req.params.id]);
  res.json({ trip: rows[0], registrations_completed: rowCount });
}));

// Guide assignment -- rejected by the database if the guide lacks the certification.
router.post('/:id/guides', requireRole('staff'), wrap(async (req, res) => {
  const { rows } = await query(
    `INSERT INTO trip_guides (trip_id, guide_id, role) VALUES ($1,$2,COALESCE($3::guide_role,'assistant'))
     RETURNING trip_id, guide_id, role, assigned_at`,
    [req.params.id, req.body.guide_id, req.body.role ?? null]);
  res.status(201).json(rows[0]);
}));

router.delete('/:id/guides/:guideId', requireRole('staff'), wrap(async (req, res) => {
  const { rowCount } = await query(
    'DELETE FROM trip_guides WHERE trip_id = $1 AND guide_id = $2',
    [req.params.id, req.params.guideId]);
  if (!rowCount) throw notFound('assignment not found');
  res.status(204).end();
}));

// Reserve gear for a trip -- rejected if it would double-book overlapping trips.
router.post('/:id/equipment', requireRole('staff'), wrap(async (req, res) => {
  const { rows } = await query(
    `INSERT INTO trip_equipment (trip_id, equipment_id, quantity, notes)
     VALUES ($1,$2,$3,$4) RETURNING *`,
    [req.params.id, req.body.equipment_id, req.body.quantity, req.body.notes ?? null]);
  res.status(201).json(rows[0]);
}));

router.delete('/:id/equipment/:equipmentId', requireRole('staff'), wrap(async (req, res) => {
  const { rowCount } = await query(
    `DELETE FROM trip_equipment WHERE trip_id = $1 AND equipment_id = $2 AND checked_out_at IS NULL`,
    [req.params.id, req.params.equipmentId]);
  if (!rowCount) throw notFound('no un-issued reservation for that item on this trip');
  res.status(204).end();
}));

export default router;
