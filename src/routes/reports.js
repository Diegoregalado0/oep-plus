import { Router } from 'express';
import { query } from '../db.js';
import { wrap } from '../errors.js';
import { requireRole } from '../auth.js';

const router = Router();
router.use(requireRole('staff'));

// Capacity and waitlist status per upcoming trip.
router.get('/trip-capacity', wrap(async (req, res) => {
  const { rows } = await query(
    `SELECT * FROM v_trip_capacity
      WHERE start_date >= COALESCE($1::date, CURRENT_DATE)
      ORDER BY start_date`, [req.query.from ?? null]);
  res.json(rows);
}));

// Guides whose certifications are expiring soon (default 90 days) or expired.
router.get('/certifications-expiring', wrap(async (req, res) => {
  const days = Number(req.query.days ?? 90);
  const { rows } = await query(
    `SELECT * FROM v_certification_expiry
      WHERE expires_on <= CURRENT_DATE + $1::int
      ORDER BY expires_on`, [days]);
  res.json({ window_days: days, count: rows.length, certifications: rows });
}));

// Equipment with a high damage or loss rate.
router.get('/equipment-health', wrap(async (req, res) => {
  const min = Number(req.query.min_rate_pct ?? 0);
  const { rows } = await query(
    `SELECT * FROM v_equipment_health
      WHERE COALESCE(damage_loss_rate_pct, 0) >= $1
      ORDER BY COALESCE(damage_loss_rate_pct, 0) DESC, times_lost DESC, name`, [min]);
  res.json(rows);
}));

// Per-member trip history and payment totals.
router.get('/member-history', wrap(async (_req, res) => {
  const { rows } = await query(
    'SELECT * FROM v_member_history ORDER BY trips_completed DESC, member_name');
  res.json(rows);
}));

// Revenue by month, optionally bounded.
router.get('/revenue', wrap(async (req, res) => {
  const { rows } = await query(
    `SELECT * FROM v_revenue_by_month
      WHERE ($1::text IS NULL OR month >= $1) AND ($2::text IS NULL OR month <= $2)
      ORDER BY month`, [req.query.from ?? null, req.query.to ?? null]);
  const total = rows.reduce((acc, r) => acc + Number(r.collected_cents), 0);
  res.json({ months: rows, collected_cents_total: total });
}));

// One-call program snapshot for a staff dashboard.
router.get('/dashboard', wrap(async (_req, res) => {
  const [trips, certs, gear, revenue, waitlists] = await Promise.all([
    query(`SELECT * FROM v_trip_capacity WHERE status = 'open' AND start_date >= CURRENT_DATE
            ORDER BY start_date LIMIT 10`),
    query(`SELECT * FROM v_certification_expiry WHERE urgency IN ('expired','critical','warning')
            ORDER BY expires_on`),
    query(`SELECT * FROM v_equipment_health WHERE COALESCE(damage_loss_rate_pct,0) > 0
            ORDER BY damage_loss_rate_pct DESC LIMIT 10`),
    query(`SELECT * FROM v_revenue_by_month ORDER BY month DESC LIMIT 6`),
    query(`SELECT trip_name, count(*) AS waiting FROM v_waitlist GROUP BY trip_name ORDER BY 2 DESC`),
  ]);
  res.json({
    upcoming_trips: trips.rows,
    certifications_needing_attention: certs.rows,
    equipment_attention: gear.rows,
    recent_revenue: revenue.rows,
    waitlists: waitlists.rows,
  });
}));

export default router;
