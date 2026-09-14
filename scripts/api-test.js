// End-to-end API test. Resets the database, starts the API in-process, and
// exercises the role model plus every rule in section 5 over HTTP.
//   npm test
import { execFileSync } from 'node:child_process';
import { createApp } from '../src/app.js';
import { close } from '../src/db.js';

const root = new URL('..', import.meta.url).pathname;
console.log('resetting database...');
try {
  execFileSync('./scripts/reset-db.sh', { cwd: root, stdio: 'pipe' });
} catch (err) {
  console.error(err.stderr?.toString() || err.message);
  process.exit(1);
}

const server = createApp().listen(0);
const base = `http://localhost:${server.address().port}`;

const AS = {
  staff:  { 'X-Role': 'staff' },
  member: (id) => ({ 'X-Role': 'member', 'X-User-Id': String(id) }),
  guide:  (id) => ({ 'X-Role': 'guide',  'X-User-Id': String(id) }),
};

async function call(method, path, { as = AS.staff, body } = {}) {
  const res = await fetch(base + path, {
    method,
    headers: { 'Content-Type': 'application/json', ...as },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  return { status: res.status, body: text ? JSON.parse(text) : null };
}

let passed = 0, failed = 0;
function check(label, ok, detail) {
  if (ok) { passed++; console.log(`  ok    ${label}`); }
  else { failed++; console.log(`  FAIL  ${label}${detail ? ` -- ${detail}` : ''}`); }
}
const section = (t) => console.log(`\n${t}\n${'-'.repeat(t.length)}`);

const ID = {};

// ---------------------------------------------------------------------------
section('health and browsing');
{
  const h = await call('GET', '/health');
  check('GET /health', h.status === 200 && h.body.ok, JSON.stringify(h.body));

  const trips = await call('GET', '/trips', { as: AS.member(1) });
  check('members see only open trips', trips.status === 200 && trips.body.every((t) => t.status === 'open'));
  const draft = trips.body.find((t) => t.name === 'Hike Lembert Dome and Dog Lake');
  check('draft trips hidden from members', draft === undefined);

  const staffTrips = await call('GET', '/trips?status=draft');
  check('staff can list drafts', staffTrips.status === 200 && staffTrips.body.length === 1);

  ID.halfDome = trips.body.find((t) => t.name === 'Hike Dewey Point').trip_id;
  ID.sequoia = trips.body.find((t) => t.name === 'Joshua Tree Stargazing').trip_id;
  ID.clinic = trips.body.find((t) => t.name === 'Camp Yosemite Valley').trip_id;
  ID.sunset = trips.body.find((t) => t.name === 'Intro to Backpacking').trip_id;
  ID.monoLake = trips.body.find((t) => t.name === 'Whale Watching Kayak Tour').trip_id;

  const detail = await call('GET', `/trips/${ID.halfDome}`, { as: AS.member(1) });
  check('trip detail includes guides and equipment',
    detail.status === 200 && Array.isArray(detail.body.guides) && detail.body.guides.length > 0);
}

// ---------------------------------------------------------------------------
section('rule 1 -- capacity and automatic waitlisting');
{
  const full = await call('GET', `/trips/${ID.halfDome}`);
  check('Half Dome is full (3/3)', full.body.confirmed === 3 && full.body.is_full === true);

  const kofi = 10;
  const reg = await call('POST', '/registrations',
    { as: AS.member(kofi), body: { trip_id: ID.halfDome } });
  check('registering for a full trip returns a waitlist spot',
    reg.status === 201 && reg.body.status === 'waitlisted' && reg.body.waitlist_position === 3,
    JSON.stringify(reg.body));
  ID.kofiReg = reg.body.id;

  const still = await call('GET', `/trips/${ID.halfDome}`);
  check('confirmed count did not exceed capacity', still.body.confirmed === 3);

  const force = await call('PATCH', `/registrations/${ID.kofiReg}`, { body: { status: 'confirmed' } });
  check('staff cannot force a 4th confirmed seat',
    force.status === 409 && force.body.rule_violation === true, JSON.stringify(force.body));

  const shrink = await call('PATCH', `/trips/${ID.halfDome}`, { body: { capacity: 1 } });
  check('capacity cannot be cut below the confirmed headcount', shrink.status === 409);

  const suspended = await call('POST', '/registrations',
    { body: { trip_id: ID.sequoia, member_id: 3 } });   // Chris Okafor, suspended
  check('a suspended membership is refused', suspended.status === 409);

  const dupe = await call('POST', '/registrations',
    { as: AS.member(kofi), body: { trip_id: ID.halfDome } });
  check('the same member cannot register twice', dupe.status === 409);
}

// ---------------------------------------------------------------------------
section('rule 2 -- automatic waitlist promotion');
{
  const before = await call('GET', `/trips/${ID.halfDome}/roster`);
  const firstConfirmed = before.body.roster.find((r) => r.status === 'confirmed');
  const nextUp = before.body.waitlist[0];

  const cancelled = await call('DELETE', `/registrations/${firstConfirmed.registration_id}`,
    { as: AS.member(firstConfirmed.member_id), body: { reason: 'work conflict' } });
  check('a member can cancel their own registration', cancelled.status === 200);
  check('the next waitlisted member was promoted automatically',
    cancelled.body.promoted_from_waitlist?.id === nextUp.registration_id,
    JSON.stringify(cancelled.body.promoted_from_waitlist));

  const after = await call('GET', `/trips/${ID.halfDome}`);
  check('the trip is full again', after.body.confirmed === 3);

  const notMine = await call('DELETE', `/registrations/${ID.kofiReg}`, { as: AS.member(1) });
  check('a member cannot cancel someone else\'s registration', notMine.status === 403);
}

// ---------------------------------------------------------------------------
section('rule 3 -- guide certification compliance');
{
  const sam = 4, devon = 2, maya = 1;
  const bad = await call('POST', `/trips/${ID.halfDome}/guides`,
    { body: { guide_id: sam, role: 'assistant' } });
  check('a guide without the required certification is refused',
    bad.status === 409 && /WFR/.test(bad.body.error), JSON.stringify(bad.body));

  const lapsing = await call('POST', `/trips/${ID.sequoia}/guides`,
    { body: { guide_id: devon, role: 'assistant' } });
  check('a certification that expires mid-trip is refused', lapsing.status === 409);

  // A trip with no certification requirement accepts any guide.
  const openTrip = await call('POST', '/trips', {
    body: { name: 'Campus Foothills Evening Walk', destination: 'Merced', difficulty: 'easy',
            start_date: '2026-10-29', end_date: '2026-10-29', capacity: 15, fee_cents: 0 } });
  check('staff can create a trip', openTrip.status === 201, JSON.stringify(openTrip.body));
  ID.walk = openTrip.body.id;
  const ok = await call('POST', `/trips/${ID.walk}/guides`,
    { body: { guide_id: sam, role: 'lead' } });
  check('a guide with no WFR is fine on a trip with no requirement', ok.status === 201,
    JSON.stringify(ok.body));
  const second = await call('POST', `/trips/${ID.walk}/guides`,
    { body: { guide_id: maya, role: 'lead' } });
  check('a trip cannot have two lead guides', second.status === 409);

  const move = await call('PATCH', `/trips/${ID.halfDome}`,
    { body: { start_date: '2027-08-01', end_date: '2027-08-01' } });
  check('a trip cannot move past its guides\' certification expiry', move.status === 409);

  const notStaff = await call('POST', `/trips/${ID.walk}/guides`,
    { as: AS.guide(1), body: { guide_id: 3 } });
  check('guides cannot assign themselves to trips', notStaff.status === 403);
}

// ---------------------------------------------------------------------------
section('rule 4 -- equipment availability across overlapping trips');
{
  const avail = await call('GET', '/equipment?from=2026-10-18&to=2026-10-19');
  const tent = avail.body.find((e) => e.name === '4-Person Tent');
  check('availability accounts for overlapping trips',
    tent.committed === 4 && tent.available === 2, JSON.stringify(tent));

  const fits = await call('POST', `/trips/${ID.sunset}/equipment`,
    { body: { equipment_id: tent.id, quantity: 2 } });
  check('a checkout within availability succeeds', fits.status === 201);
  ID.tentRow = fits.body.id;

  const tooMany = await call('POST', `/trips/${ID.clinic}/equipment`,
    { body: { equipment_id: tent.id, quantity: 3 } });
  check('a checkout that would double-book is refused', tooMany.status === 409);

  const messenger = avail.body.find((e) => e.name === 'Satellite Messenger');
  const overlapping = await call('POST', `/trips/${ID.clinic}/equipment`,
    { body: { equipment_id: messenger.id, quantity: 2 } });
  check('safety gear cannot be committed twice on overlapping dates',
    overlapping.status === 201, JSON.stringify(overlapping.body));  // Oct clinic vs Nov trip: no overlap
  const conflict = await call('POST', `/trips/${ID.sunset}/equipment`,
    { body: { equipment_id: messenger.id, quantity: 1 } });
  check('the third messenger on overlapping dates is refused', conflict.status === 409,
    JSON.stringify(conflict.body));

  const writeOff = await call('PATCH', `/equipment/${tent.id}`, { body: { total_quantity: 3 } });
  check('inventory cannot shrink below live commitments', writeOff.status === 409);

  const out = await call('POST', `/equipment/checkouts/${ID.tentRow}/check-out`, { body: {} });
  check('staff can issue reserved gear', out.status === 200 && out.body.checked_out_at);
  const back = await call('POST', `/equipment/checkouts/${ID.tentRow}/check-in`,
    { body: { return_condition: 'damaged', notes: 'hull scrape' } });
  check('staff can check gear back in with a condition',
    back.status === 200 && back.body.return_condition === 'damaged');
}

// ---------------------------------------------------------------------------
section('rule 5 -- no-show sweep frees spots and feeds the waitlist');
{
  const before = await call('GET', `/trips/${ID.monoLake}/roster`);
  check('Mono Lake starts full with someone waiting',
    before.body.roster.filter((r) => r.status === 'confirmed').length === 2 &&
    before.body.waitlist.length === 1);
  const waiting = before.body.waitlist[0];

  const sweep = await call('POST', '/admin/process-pre-trip-meetings',
    { body: { as_of: '2026-09-11T08:00:00-07:00' } });
  check('the sweep cancelled the member who missed the meeting',
    sweep.status === 200 && sweep.body.no_shows.length === 1, JSON.stringify(sweep.body));
  check('and promoted the waitlisted member',
    sweep.body.promotions.length === 1 &&
    sweep.body.promotions[0].registration_id === waiting.registration_id);

  const again = await call('POST', '/admin/process-pre-trip-meetings',
    { body: { as_of: '2026-09-12T08:00:00-07:00' } });
  check('re-running the sweep does not punish the promoted member',
    again.body.no_shows.length === 0);

  const notStaff = await call('POST', '/admin/process-pre-trip-meetings', { as: AS.member(1) });
  check('members cannot run the sweep', notStaff.status === 403);
}

// ---------------------------------------------------------------------------
section('role-scoped views');
{
  const certs = await call('GET', '/me/certifications', { as: AS.guide(2) });
  check('a guide sees their own certifications and expiry dates',
    certs.status === 200 && certs.body.length > 0 && 'days_until_expiry' in certs.body[0]);

  const other = await call('GET', '/guides/1/certifications', { as: AS.guide(2) });
  check('a guide cannot read another guide\'s certifications', other.status === 403);

  const myTrips = await call('GET', '/me/trips', { as: AS.guide(1) });
  check('a guide sees their assignments with roster counts',
    myTrips.status === 200 && myTrips.body.length > 0 && 'confirmed' in myTrips.body[0]);

  const roster = await call('GET', `/trips/${ID.halfDome}/roster`, { as: AS.guide(1) });
  check('an assigned guide can read the roster', roster.status === 200);
  const denied = await call('GET', `/trips/${ID.halfDome}/roster`, { as: AS.guide(3) });
  check('an unassigned guide cannot', denied.status === 403);

  const mine = await call('GET', '/me/registrations', { as: AS.member(1) });
  check('a member sees their own history and totals',
    mine.status === 200 && mine.body.member.trips_completed >= 1 && mine.body.registrations.length > 0);
  const theirs = await call('GET', '/members/2/registrations', { as: AS.member(1) });
  check('a member cannot read another member\'s history', theirs.status === 403);
  const staffList = await call('GET', '/members', { as: AS.member(1) });
  check('members cannot list the whole membership', staffList.status === 403);
}

// ---------------------------------------------------------------------------
section('reporting');
{
  const cap = await call('GET', '/reports/trip-capacity');
  check('capacity report covers upcoming trips', cap.status === 200 && cap.body.length > 0);

  const exp = await call('GET', '/reports/certifications-expiring?days=60');
  check('expiring certifications report flags Devon\'s WFR',
    exp.status === 200 && exp.body.certifications.some((c) => c.code === 'WFR' && c.urgency !== 'ok'),
    JSON.stringify(exp.body.certifications));

  const gear = await call('GET', '/reports/equipment-health?min_rate_pct=1');
  check('equipment report ranks damage and loss',
    gear.status === 200 && gear.body.length > 0 && gear.body[0].damage_loss_rate_pct > 0,
    JSON.stringify(gear.body[0]));

  const hist = await call('GET', '/reports/member-history');
  check('member history report includes payment totals',
    hist.status === 200 && hist.body.some((m) => Number(m.total_paid_cents) > 0));

  const rev = await call('GET', '/reports/revenue?from=2026-01&to=2026-12');
  check('revenue by month is bounded by the window',
    rev.status === 200 && rev.body.months.length > 0 && rev.body.collected_cents_total > 0,
    JSON.stringify(rev.body.months));

  const dash = await call('GET', '/reports/dashboard');
  check('dashboard returns every panel',
    dash.status === 200 && 'upcoming_trips' in dash.body &&
    'certifications_needing_attention' in dash.body && 'waitlists' in dash.body);

  const nope = await call('GET', '/reports/revenue', { as: AS.guide(1) });
  check('reports are staff-only', nope.status === 403);
}

console.log(`\n${passed} passed, ${failed} failed`);
server.close();
await close();
process.exit(failed ? 1 : 0);
