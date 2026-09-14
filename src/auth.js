// Stand-in identity layer. Real deployments would put SSO/CAS in front of this;
// the brief scopes authentication out, so the caller declares who they are:
//   X-Role:    staff | guide | member | guest
//   X-User-Id: guides.id for a guide, members.id for a member
// "guest" is an unauthenticated visitor browsing the public catalog. It carries
// no identity and can only read open trips, the same as the current Fusion
// portal, which lists programs publicly and asks you to sign in to register.
import { forbidden, badRequest } from './errors.js';

const ROLES = new Set(['staff', 'guide', 'member', 'guest']);

export function identify(req, _res, next) {
  const role = (req.get('X-Role') || 'member').toLowerCase();
  if (!ROLES.has(role)) return next(badRequest(`unknown role "${role}"`));
  const rawId = req.get('X-User-Id');
  if (role !== 'staff' && role !== 'guest' && !rawId) {
    return next(badRequest(`role "${role}" requires an X-User-Id header`));
  }
  req.actor = { role, id: rawId ? Number(rawId) : null };
  if (rawId && !Number.isInteger(req.actor.id)) {
    return next(badRequest('X-User-Id must be an integer'));
  }
  next();
}

export const requireRole = (...roles) => (req, _res, next) =>
  roles.includes(req.actor.role) ? next() : next(forbidden(`this endpoint requires role: ${roles.join(' or ')}`));

export const isStaff = (req) => req.actor.role === 'staff';
