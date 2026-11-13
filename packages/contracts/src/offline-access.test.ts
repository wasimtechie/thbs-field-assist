import {describe,it,expect} from 'vitest';
import {CLOSURE_TEMPLATE_ID} from './closure/policy';
import {offlineProvisionSchema,canIssueNonExpiringDemo,hasNonExpiringDemoClaims,offlineConfirmationAllowed,NON_EXPIRING_DEMO_ACCESS,SYNTHETIC_DEMO_EMAIL,SYNTHETIC_DEMO_ORGANIZATION} from './offline-access';

const scope={email:SYNTHETIC_DEMO_EMAIL,organizationId:SYNTHETIC_DEMO_ORGANIZATION,templateId:CLOSURE_TEMPLATE_ID};
const enabled={...scope,enabled:true,databaseUrl:'postgresql://example@127.0.0.1:54329/fieldassist'};
const claims={offlineAccess:NON_EXPIRING_DEMO_ACCESS,demoAccount:scope.email,organizationId:scope.organizationId,expiresAt:null,allowedTemplateIds:[scope.templateId]};
describe('explicit non-expiring synthetic offline access',()=>{
  it('requires explicit backend opt-in and a local synthetic scope',()=>{
    expect(canIssueNonExpiringDemo(enabled)).toBe(true);
    for(const changed of [{enabled:false},{databaseUrl:'postgresql://example@production.example/fieldassist'},{databaseUrl:'invalid'},{email:'engineer@example.com'},{email:'fibre@fieldassist.demo'},{organizationId:'another-org'},{templateId:'another-template'}])expect(canIssueNonExpiringDemo({...enabled,...changed})).toBe(false);
  });
  it('keeps ordinary provisioning time-limited by default and validates opt-in type',()=>{
    const body={deviceId:'90000000-0000-4000-8000-000000000001',platform:'android',appVersion:'test',osVersion:'test'};
    expect(offlineProvisionSchema.parse(body).nonExpiringDemo).toBeUndefined();
    expect(offlineProvisionSchema.parse({...body,nonExpiringDemo:true}).nonExpiringDemo).toBe(true);
    expect(offlineProvisionSchema.safeParse({...body,nonExpiringDemo:'true'}).success).toBe(false);
  });
  it('requires the scoped signed-claim shape, without a hidden far-future expiry',()=>{
    expect(hasNonExpiringDemoClaims(claims,scope)).toBe(true);
    for(const changed of [{offlineAccess:undefined},{demoAccount:'engineer@example.com'},{organizationId:'other-org'},{allowedTemplateIds:[scope.templateId,'other']},{expiresAt:'2099-01-01T00:00:00.000Z'},{exp:null},{exp:9999999999}])expect(hasNonExpiringDemoClaims({...claims,...changed},scope)).toBe(false);
    expect(hasNonExpiringDemoClaims(claims,{...scope,email:'engineer@example.com'})).toBe(false);
  });
  it('accepts later demo reports only when non-expiring authorisation is established',()=>{
    const grant={issuedAt:new Date('2026-11-13T00:00:00Z'),expiresAt:null};
    const now=new Date('2050-01-01T00:00:00Z');
    expect(offlineConfirmationAllowed(grant,now,now,true)).toBe(true);
    expect(offlineConfirmationAllowed(grant,now,now)).toBe(false);
    expect(offlineConfirmationAllowed(grant,new Date('2026-11-12T00:00:00Z'),now,true)).toBe(false);
    expect(offlineConfirmationAllowed(grant,new Date('2050-01-01T00:03:00Z'),now,true)).toBe(false);
  });
  it('continues to reject reports confirmed after an ordinary lease expired',()=>{
    const grant={issuedAt:new Date('2026-11-13T00:00:00Z'),expiresAt:new Date('2026-11-16T00:00:00Z')};
    expect(offlineConfirmationAllowed(grant,new Date('2026-11-14T00:00:00Z'),new Date('2026-11-17T00:00:00Z'))).toBe(true);
    expect(offlineConfirmationAllowed(grant,new Date('2026-11-17T00:00:00Z'),new Date('2026-11-17T00:00:00Z'),true)).toBe(false);
  });
});
