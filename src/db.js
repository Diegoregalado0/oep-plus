import pg from 'pg';

// DATE columns are calendar dates, not instants. Hand them back as
// 'YYYY-MM-DD' instead of letting them become timezone-shifted Date objects.
pg.types.setTypeParser(1082, (v) => v);
// NUMERIC (the report percentages) parses to string by default; these are small
// and safe as numbers.
pg.types.setTypeParser(1700, (v) => (v === null ? null : Number(v)));

const pool = new pg.Pool({
  host: process.env.PGHOST || 'localhost',
  port: Number(process.env.PGPORT || 55432),
  user: process.env.PGUSER || 'oep',
  password: process.env.PGPASSWORD || 'oep',
  database: process.env.PGDATABASE || 'oep',
  max: 10,
});

// Every session works inside the oep schema.
pool.on('connect', (client) => client.query('SET search_path TO oep, public'));

export const query = (text, params) => pool.query(text, params);

export async function tx(fn) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const result = await fn(client);
    await client.query('COMMIT');
    return result;
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}

export const close = () => pool.end();

// Postgres error codes the rule triggers raise, mapped to HTTP status.
const STATUS_BY_CODE = {
  '23514': 409, // check_violation -- a business rule said no
  '23505': 409, // unique_violation
  '23503': 400, // foreign_key_violation
  '23502': 400, // not_null_violation
  '22P02': 400, // invalid_text_representation (bad enum value, bad date)
  'P0001': 409, // raise_exception
};

export function httpStatusForDbError(err) {
  return STATUS_BY_CODE[err.code] || (err.code?.startsWith('22') ? 400 : 500);
}
