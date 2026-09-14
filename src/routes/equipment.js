import { Router } from 'express';
import { query } from '../db.js';
import { wrap, notFound, badRequest } from '../errors.js';
import { requireRole } from '../auth.js';

const router = Router();
router.use(requireRole('staff'));

router.get('/', wrap(async (req, res) => {
  // ?from=&to= reports how many units are free across that window.
  const { from, to } = req.query;
  if (from && to) {
    const { rows } = await query(
      `SELECT e.id, e.name, e.category, e.total_quantity, e.condition,
              committed_quantity(e.id, $1::date, $2::date, NULL) AS committed,
              e.total_quantity - committed_quantity(e.id, $1::date, $2::date, NULL) AS available
         FROM equipment e ORDER BY e.category, e.name`, [from, to]);
    return res.json(rows);
  }
  const { rows } = await query('SELECT * FROM v_equipment_health ORDER BY category, name');
  res.json(rows);
}));

router.post('/', wrap(async (req, res) => {
  const b = req.body;
  const { rows } = await query(
    `INSERT INTO equipment (name, category, total_quantity, condition, purchased_on, notes)
     VALUES ($1,$2,$3,COALESCE($4::equipment_condition,'good'),$5,$6) RETURNING *`,
    [b.name, b.category, b.total_quantity, b.condition ?? null, b.purchased_on ?? null, b.notes ?? null]);
  res.status(201).json(rows[0]);
}));

router.patch('/:id', wrap(async (req, res) => {
  const allowed = ['name', 'category', 'total_quantity', 'condition', 'notes'];
  const keys = Object.keys(req.body).filter((k) => allowed.includes(k));
  if (!keys.length) throw badRequest(`editable fields: ${allowed.join(', ')}`);
  const { rows } = await query(
    `UPDATE equipment SET ${keys.map((k, i) => `${k} = $${i + 2}`).join(', ')}
      WHERE id = $1 RETURNING *`, [req.params.id, ...keys.map((k) => req.body[k])]);
  if (!rows.length) throw notFound(`equipment ${req.params.id} not found`);
  res.json(rows[0]);
}));

// Issue the gear physically (the reservation already passed the availability rule).
router.post('/checkouts/:tripEquipmentId/check-out', wrap(async (req, res) => {
  const { rows } = await query(
    `UPDATE trip_equipment SET checked_out_at = COALESCE($2, now())
      WHERE id = $1 AND checked_out_at IS NULL RETURNING *`,
    [req.params.tripEquipmentId, req.body?.checked_out_at ?? null]);
  if (!rows.length) throw notFound('no pending reservation with that id');
  res.json(rows[0]);
}));

// Return it, recording condition. Returned gear is available again.
router.post('/checkouts/:tripEquipmentId/check-in', wrap(async (req, res) => {
  if (!req.body?.return_condition) throw badRequest('return_condition is required');
  const { rows } = await query(
    `UPDATE trip_equipment
        SET checked_in_at = COALESCE($2, now()), return_condition = $3, notes = COALESCE($4, notes)
      WHERE id = $1 AND checked_out_at IS NOT NULL AND checked_in_at IS NULL RETURNING *`,
    [req.params.tripEquipmentId, req.body.checked_in_at ?? null,
     req.body.return_condition, req.body.notes ?? null]);
  if (!rows.length) throw notFound('no outstanding checkout with that id');

  // Losing an item takes it off the books, so inventory follows the return.
  if (req.body.return_condition === 'lost') {
    await query(
      `UPDATE equipment SET total_quantity = GREATEST(total_quantity - $2, 0)
        WHERE id = (SELECT equipment_id FROM trip_equipment WHERE id = $1)`,
      [req.params.tripEquipmentId, rows[0].quantity]);
  }
  res.json(rows[0]);
}));

router.get('/commitments', wrap(async (_req, res) => {
  const { rows } = await query(
    'SELECT * FROM v_equipment_commitments ORDER BY start_date, name');
  res.json(rows);
}));

export default router;
