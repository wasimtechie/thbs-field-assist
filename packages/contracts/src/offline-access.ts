import {z} from 'zod';
import {CLOSURE_TEMPLATE_ID} from './closure/policy';

export const NON_EXPIRING_DEMO_ACCESS = 'non-expiring-synthetic-demo';
export const SYNTHETIC_DEMO_EMAIL = 'closure@fieldassist.demo';
export const SYNTHETIC_DEMO_ORGANIZATION = '10000000-0000-4000-8000-000000000001';

export const offlineProvisionSchema = z.object({
  deviceId:z.uuid(), platform:z.enum(['ios','android']),
  appVersion:z.string().min(1).max(40), osVersion:z.string().min(1).max(100),
  model:z.string().max(100).optional(), nonExpiringDemo:z.boolean().optional(),
});

type DemoScope = {email:string; organizationId:string; templateId:string};
export function isSyntheticOfflineDemo(scope:DemoScope) {
  return scope.email === SYNTHETIC_DEMO_EMAIL &&
    scope.organizationId === SYNTHETIC_DEMO_ORGANIZATION &&
    scope.templateId === CLOSURE_TEMPLATE_ID;
}

export function canIssueNonExpiringDemo(scope:DemoScope & {enabled:boolean; databaseUrl:string}) {
  let local = false;
  try { local = ['localhost','127.0.0.1','[::1]'].includes(new URL(scope.databaseUrl).hostname); } catch {}
  return scope.enabled && local && isSyntheticOfflineDemo(scope);
}

// The caller must already trust the token's signature or its server database row.
export function hasNonExpiringDemoClaims(claims:Record<string,unknown>, scope:DemoScope) {
  return isSyntheticOfflineDemo(scope) &&
    claims.offlineAccess === NON_EXPIRING_DEMO_ACCESS &&
    claims.demoAccount === scope.email && claims.organizationId === scope.organizationId &&
    claims.expiresAt === null && !Object.hasOwn(claims,'exp') &&
    Array.isArray(claims.allowedTemplateIds) && claims.allowedTemplateIds.length === 1 &&
    claims.allowedTemplateIds[0] === scope.templateId;
}

export function offlineConfirmationAllowed(access:{issuedAt:Date; expiresAt:Date|null}, confirmed:Date, now:Date, nonExpiringDemo=false) {
  return confirmed >= access.issuedAt && confirmed.getTime() <= now.getTime()+120000 &&
    (access.expiresAt === null ? nonExpiringDemo : confirmed <= access.expiresAt);
}
