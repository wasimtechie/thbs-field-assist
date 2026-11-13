"""Compile the manager's synthetic banks into a versioned demo policy.
The source text is preserved separately; choices and executable rules below are
implementation hypotheses. This does not import operational Openreach policy.
"""
import json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
banks=json.loads((ROOT/'fixtures/closure-mvp/question-banks.json').read_text())['banks']
def eq(f,v=True):return {'field':f,'op':'eq','value':v}
def one(f,*v):return {'field':f,'op':'in','value':list(v)}
def present(f):return {'field':f,'op':'present'}
def all_(*v):return {'all':list(v)}
def any_(*v):return {'any':list(v)}
final=eq('work_stage','final_provision');complete=eq('claimed_outcome','completed');nonhold=one('claimed_outcome','completed','partial','blocked','referred','stage_completed','network_ready')
install=any_(all_(eq('scenario','S1'),eq('route_obstructed',False)),all_(eq('scenario','S2'),eq('route_obstructed',False)),all_(eq('scenario','S3'),eq('alternative_authorised')))
access=eq('access_permission');connected=eq('fibre_connected');optical=eq('optical_test','passed')
# A bank maps its question IDs to canonical facts; shared facts are asked once.
common=[('identity_verified','boolean'),('work_stage','stage'),('claimed_outcome','outcome'),('actual_work','long_text'),('safety_hazard','boolean'),('access_permission','boolean'),('evidence_sufficient','boolean'),('work_outstanding','boolean'),('affected_party_informed','boolean'),('site_handover_safe','boolean')]
specific={
'S1':[
('serving_asset','short_text',None),('drop_route','route',None),('route_obstructed','boolean',None),('location_agreed','boolean',access),('drilling_consent','boolean',eq('penetration_required')),('external_connection','boolean',access),('internal_fibre','boolean',eq('ont_fitted')),('ont_serial','short_text',eq('ont_fitted')),('ont_status_checked','boolean',eq('ont_fitted')),('optical_test','test',connected),('service_live','boolean',optical),('customer_handover','boolean',eq('service_live')),('installation_evidence','photo',eq('ont_fitted')),('property_damage','boolean',eq('physical_work_attempted')),('reinstatement_accepted','boolean',any_(eq('property_damage'),eq('excavation_performed')))],
'S2':[
('underground_route','boolean',None),('obstruction_section','short_text',eq('route_obstructed')),('safe_attempt','boolean',None),('obstruction_type','short_text',eq('route_obstructed')),('blockage_distance','decimal',eq('route_obstructed')),('clearable_in_scope','boolean',eq('route_obstructed')),('alternate_route_feasible','boolean',eq('route_obstructed')),('civils_required','boolean',eq('route_obstructed')),('permit_dependencies','short_text',eq('civils_required')),('site_handover_safe','boolean',eq('physical_work_attempted')),('follow_on_ref','short_text',eq('civils_required')),('next_owner','short_text',eq('civils_required')),('other_premises_affected','boolean',eq('shared_duct')),('ont_fitted','boolean',None),('service_live','boolean',connected)],
'S3':[
('expected_cbt','short_text',None),('observed_cbt','short_text',None),('serving_location_correct','boolean',None),('cbt_present','boolean',None),('cbt_safe_access','boolean',eq('cbt_present')),('cbt_port_verified','boolean',eq('cbt_present')),('mapping_matches','boolean',eq('cbt_present')),('asset_evidence','photo',any_(eq('cbt_present',False),eq('mapping_matches',False))),('alternative_cbt','short_text',any_(eq('cbt_present',False),eq('mapping_matches',False))),('alternative_authorised','boolean',present('alternative_cbt')),('records_correction','boolean',any_(eq('cbt_present',False),eq('mapping_matches',False))),('follow_on_ref','short_text',eq('records_correction')),('next_owner','short_text',eq('cbt_present',False)),('customer_service_affected','boolean',None),('reappointment_held','boolean',any_(eq('cbt_present',False),eq('cbt_safe_access',False)))],
'S4':[
('ont_fitted','boolean',None),('ont_serial','short_text',eq('ont_fitted')),('location_agreed','boolean',eq('ont_fitted')),('external_connection','boolean',None),('fibre_connected','boolean',None),('ont_status_checked','boolean',eq('ont_fitted')),('optical_rx_dbm','decimal',connected),('optical_test','test',connected),('activation_attempted','boolean',optical),('service_live','boolean',all_(optical,eq('activation_attempted'))),('issue_type','issue',eq('service_live',False)),('diagnostic_evidence','photo',eq('service_live',False)),('next_owner','short_text',eq('service_live',False)),('follow_on_ref','short_text',eq('service_live',False)),('customer_not_live_informed','boolean',eq('service_live',False))],
'S5':[
('work_stage','stage',None),('survey_reference','short_text',one('work_stage','survey','design')),('design_accepted','boolean',one('work_stage','design','civils','fibre','distribution','network_acceptance')),('route_distance','decimal',one('work_stage','survey','design')),('wayleave_required','boolean',None),('wayleave_granted','boolean',eq('wayleave_required')),('civils_segments','short_text',one('work_stage','civils','fibre','distribution','network_acceptance')),('civils_to_design','boolean',eq('work_stage','civils')),('reinstatement_accepted','boolean',eq('work_stage','civils')),('fibre_placed_spliced','boolean',one('work_stage','fibre','distribution','network_acceptance')),('splice_tests_accepted','boolean',eq('fibre_placed_spliced')),('terminal_available_mapped','boolean',one('work_stage','distribution','network_acceptance')),('as_built_accepted','boolean',one('work_stage','civils','fibre','distribution','network_acceptance')),('downstream_handoff','boolean',one('claimed_outcome','stage_completed','network_ready')),('premises_ready','boolean',eq('work_stage','network_acceptance'))]
}
choices={
'scenario':[(b['id'],b['title']) for b in banks],
'stage':[(s,s.replace('_',' ').capitalize()) for s in ['survey','design','civils','fibre','distribution','network_acceptance','final_provision']],
'outcome':[(s,t) for s,t in [('completed','Service live · provision completed'),('partial','Partial installation'),('blocked','Blocked visit'),('referred','Referral required'),('hold','Hold · safety / permission / missing facts'),('stage_completed','This build stage completed'),('network_ready','Network ready · final install pending')]],
'route':[('overhead','Overhead'),('underground','Underground'),('existing','Existing route')],
'issue':[('no_light','No optical signal'),('provider_activation','Provider / provisioning activation'),('external_fibre','External fibre incomplete'),('other','Other technical issue')],
'test':[('passed','Passed'),('failed','Failed'),('not_tested','Not tested')],
}
fields={};order=0
# New helper facts resolve ambiguous pseudocode. None are silently assumed.
def add(fid,kind,label,activation=None,required=True,stage='capture'):
 global order
 if fid in fields:
  if activation is None:fields[fid].pop('activation',None)
  elif fields[fid].get('activation'):fields[fid]['activation']=any_(fields[fid]['activation'],activation)
  return
 f={'id':fid,'sectionId':stage,'order':order,'type':'single_select' if kind in choices else 'boolean' if kind=='photo' else kind,'label':label[:120],'required':required,'voice':{'enabled':kind!='photo','description':f'{label}. Extract explicit facts only; unknown remains unanswered.','question':label+'?','synonyms':[]}}
 if kind in choices:f['options']=[{'id':i,'label':l} for i,l in choices[kind]]
 if kind=='long_text':f['constraints']={'maxLength':1500}
 if kind=='decimal':f['constraints']={'precision':2}
 if kind=='photo':f.update(capture='evidence',evidenceStage='installation' if fid=='installation_evidence' else 'blocker')
 if activation:f['activation']=activation
 fields[fid]=f;order+=1
add('scenario','scenario','FTTP scenario',stage='context')
for bank in banks:
 scenario=eq('scenario',bank['id'])
 for i,(fid,kind) in enumerate(common):
  extra=any_(eq('customer_facing'),eq('work_outstanding')) if i==8 else eq('physical_work_attempted') if i==9 else None
  cond=all_(scenario,extra) if extra else scenario
  add(fid,kind,bank['questions'][i]['question'].rstrip('?'),cond,stage='context' if i<3 else 'capture')
  bank['questions'][i]['fieldId']=fid
 for i,(fid,kind,extra) in enumerate(specific[bank['id']]):
  cond=all_(scenario,extra) if extra else scenario
  add(fid,kind,bank['questions'][i+10]['question'].rstrip('?'),cond)
  bank['questions'][i+10]['fieldId']=fid
# Installation continuation facts also apply when a blocked/mismatched route is resolved.
for fid in ['serving_asset','drop_route','location_agreed','external_connection','internal_fibre','ont_serial','ont_status_checked','optical_test','service_live','customer_handover','installation_evidence']:
 extra=eq('ont_fitted') if fid in ['internal_fibre','ont_serial','ont_status_checked','installation_evidence'] else connected if fid=='optical_test' else optical if fid=='service_live' else eq('service_live') if fid=='customer_handover' else None
 f=fields[fid];f['activation']=any_(f['activation'],all_(install,access,extra) if extra else all_(install,access))
for fid,kind,label,cond in [
 ('customer_facing','boolean','Is this a customer-facing work order?',None),('physical_work_attempted','boolean','Was physical work attempted?',None),
 ('penetration_required','boolean','Was new property penetration required?',all_(install,access)),('ont_fitted','boolean','Was an ONT fitted?',all_(install,access)),('fibre_connected','boolean','Is fibre connected end to end?',any_(install,eq('scenario','S4'))),
 ('optical_rx_dbm','decimal','Recorded receive optical power (dBm)',all_(connected,any_(install,eq('scenario','S4')))),
 ('hazard_mitigated','boolean','Has the recorded hazard been mitigated?',eq('safety_hazard')),('safety_escalation','short_text','Safety escalation reference',eq('safety_hazard')),
 ('next_owner','short_text','Named receiving team / owner',any_(eq('work_outstanding'),one('claimed_outcome','partial','blocked','referred','hold','network_ready','stage_completed'))),
 ('follow_on_ref','short_text','Follow-on task / escalation reference',any_(eq('work_outstanding'),one('claimed_outcome','partial','blocked','referred','hold','network_ready','stage_completed'))),
 ('next_action','long_text','Next action and dependency status',any_(eq('work_outstanding'),one('claimed_outcome','partial','blocked','referred','hold','network_ready','stage_completed'))),
 ('excavation_performed','boolean','Was excavation performed during THIS visit?',all_(eq('scenario','S1'),eq('physical_work_attempted'))),
 ('excavation_required','boolean','Is excavation required?',eq('civils_required')),
 ('operational_test','test','Recorded operational / activation test result',optical),
 ('tester_reference','short_text','Test instrument / recorded result reference',connected),
 ('test_evidence','photo','Optical / segment test evidence',any_(connected,eq('fibre_placed_spliced'))),
 ('shared_duct','boolean','Is this a shared duct?',eq('scenario','S2')),('route_obstructed','boolean','Is the route obstructed?',eq('scenario','S2')),
 ('blocker_evidence','photo','Blocker / obstruction evidence',all_(eq('scenario','S2'),eq('route_obstructed'))),
 ('route_constraints','long_text','Survey route constraints and dependencies',all_(eq('scenario','S5'),one('work_stage','survey','design'))),
 ('all_network_stages_accepted','boolean','Have all prerequisite network stages been accepted?',all_(eq('scenario','S5'),eq('work_stage','network_acceptance'))),
 ('build_evidence','photo','Build stage evidence',eq('scenario','S5')),
]:add(fid,kind,label,cond,stage='context' if fid in ['customer_facing','physical_work_attempted'] else 'handoff' if fid in ['next_owner','follow_on_ref','next_action'] else 'capture')
for fid,_,extra in specific['S2']:
 if fid not in [x[0] for x in common]: fields[fid]['activation']=any_(fields[fid]['activation'],all_(eq('scenario','S1'),eq('route_obstructed'),extra) if extra else all_(eq('scenario','S1'),eq('route_obstructed')))
fields['service_live']['activation']=any_(fields['service_live']['activation'],eq('scenario','S4'))
for fid in ['internal_fibre','customer_handover','installation_evidence','penetration_required']:
 fields[fid]['activation']=any_(fields[fid]['activation'],all_(eq('scenario','S4'),eq('service_live')))
fields['route_obstructed']['activation']=any_(fields['route_obstructed']['activation'],all_(eq('scenario','S3'),eq('alternative_authorised')))
fields['route_obstructed']['label']='Is the route obstructed?'
fields['work_outstanding']['label']='Any work outstanding for THIS work order?'
fields['test_evidence']['evidenceStage']='test'
for fid in ['blockage_distance','route_distance']: fields[fid]['constraints']['min']=0
fields['build_evidence']['evidenceStage']='installation'
rules=[]
def rule(rid,when,assertion,message):rules.append({'id':rid,'when':when,'assert':assertion,'message':message,'code':'CLOSURE_GATE'})
rule('safety-hold',all_(eq('safety_hazard'),any_(eq('hazard_mitigated',False),any_(eq('hazard_mitigated',False),{'field':'hazard_mitigated','op':'missing'}))),eq('claimed_outcome','hold'),'An unmitigated hazard requires a hold and supervisor escalation.')
rule('missing-hazard-mitigation',all_(eq('safety_hazard'),nonhold),eq('hazard_mitigated'),'Resolve the safety hold before any other closure disposition.')
rule('identity-confirmed',nonhold,eq('identity_verified'),'Verify this work order and premises identity, or record a hold.')
rule('stage-permission',one('claimed_outcome','stage_completed','network_ready'),access,'Stage acceptance requires adequate recorded access / permissions.')
rule('complete-reinstatement',all_(complete,any_(eq('property_damage'),eq('excavation_performed'))),eq('reinstatement_accepted'),'Complete the required reinstatement acceptance before completed provision.')
rule('live-service-facts',eq('service_live'),all_(final,connected,optical,eq('operational_test','passed')),'A service-live answer needs end-to-end fibre, optical and operational evidence for final provision.')
rule('live-service-route',all_(eq('service_live'),present('route_obstructed')),eq('route_obstructed',False),'A blocked route cannot be recorded as a live service.')
rule('build-design-acceptance',all_(eq('scenario','S5'),one('work_stage','civils','fibre','distribution','network_acceptance'),nonhold),eq('design_accepted'),'The dependent build stage needs an accepted design; otherwise record a hold.')
rule('permissions',complete,access,'Completed installation requires explicit access / permission.')
rule('new-entry-consent',all_(eq('penetration_required'),nonhold),eq('drilling_consent'),'New entry requires explicit consent; record a hold if consent is absent.')
rule('evidence-confirmed',nonhold,eq('evidence_sufficient'),'Confirm that the attached evidence is sufficient and linked to this work order.')
rule('site-safe',all_(eq('physical_work_attempted'),nonhold),eq('site_handover_safe'),'Confirm a safe site handover or record a hold.')
rule('final-stage-only',complete,final,'Only final provision may be recorded as completed customer service.')
for fid in ['ont_fitted','fibre_connected','optical_test','operational_test','service_live','customer_handover','location_agreed','external_connection','internal_fibre','ont_status_checked']:
 rule('complete-'+fid,complete,eq(fid,'passed' if fid in ['optical_test','operational_test'] else True),f'Completed provision requires verified {fid.replace("_"," ")}.')
rule('no-outstanding-complete',complete,eq('work_outstanding',False),'Outstanding work must be handed over; do not mark it completed.')
rule('blocked-route',all_(eq('route_obstructed'),complete),eq('route_obstructed',False),'An obstructed route cannot close as service live.')
rule('alternative',all_(present('alternative_cbt'),complete),eq('alternative_authorised'),'An alternative terminal needs explicit authorisation before completed provision.')
rule('asset-mismatch',all_(eq('scenario','S3'),complete),any_(all_(eq('cbt_present'),eq('mapping_matches'),eq('cbt_safe_access'),eq('cbt_port_verified')),eq('alternative_authorised')),'Resolve the asset mismatch or refer it to the network owner.')
rule('not-live-notification',all_(eq('scenario','S4'),eq('service_live',False),nonhold),eq('customer_not_live_informed'),'Inform the customer that the service is not live.')
rule('wayleave-build',all_(eq('scenario','S5'),one('work_stage','civils','fibre','distribution','network_acceptance'),eq('wayleave_required'),eq('wayleave_granted',False)),eq('claimed_outcome','hold'),'Unapproved wayleave blocks the dependent build stage; record a hold.')
rule('stage-not-service',all_(eq('scenario','S5'),one('claimed_outcome','stage_completed','network_ready')),{'field':'work_stage','op':'neq','value':'final_provision'},'Use the final provision workflow for a live service closure.')
for fid in ['civils_to_design','reinstatement_accepted','as_built_accepted']:
 rule('civils-'+fid,all_(eq('scenario','S5'),eq('work_stage','civils'),eq('claimed_outcome','stage_completed')),eq(fid),f'Civils stage acceptance requires {fid.replace("_"," ")}.')
rule('fibre-stage-tests',all_(eq('scenario','S5'),one('work_stage','fibre','distribution'),eq('claimed_outcome','stage_completed')),eq('splice_tests_accepted'),'Fibre stage completion requires accepted segment tests.')
rule('stage-handoff',eq('claimed_outcome','stage_completed'),eq('downstream_handoff'),'Stage completion requires an accepted downstream handoff.')
rule('stage-outstanding',one('claimed_outcome','stage_completed','network_ready'),eq('work_outstanding',False),'Resolve outstanding work for this stage or record a partial / referral.')
rule('design-stage',all_(eq('work_stage','design'),eq('claimed_outcome','stage_completed')),eq('design_accepted'),'Design stage completion requires recorded acceptance.')
rule('distribution-stage',all_(eq('work_stage','distribution'),eq('claimed_outcome','stage_completed')),eq('terminal_available_mapped'),'Distribution completion requires a verified terminal mapping.')
for fid in ['all_network_stages_accepted','fibre_placed_spliced','splice_tests_accepted','terminal_available_mapped','as_built_accepted','premises_ready','downstream_handoff']:
 rule('ready-'+fid,eq('claimed_outcome','network_ready'),eq(fid),f'Network readiness requires {fid.replace("_"," ")}.')
dispositions=[{'when':eq('claimed_outcome','hold'),'outcome':'hold'},
 {'when':all_(eq('safety_hazard'),any_(eq('hazard_mitigated',False),{'field':'hazard_mitigated','op':'missing'})),'outcome':'hold'},
 {'when':all_(eq('safety_hazard'),eq('claimed_outcome','hold')),'outcome':'hold'},
 {'when':all_(eq('scenario','S5'),one('work_stage','civils','fibre','distribution','network_acceptance'),eq('wayleave_required'),eq('wayleave_granted',False)),'outcome':'hold'},
 {'when':all_(eq('scenario','S3'),eq('cbt_safe_access',False)),'outcome':'hold'},
 {'when':eq('route_obstructed'),'outcome':'blocked'},
 {'when':all_(eq('scenario','S3'),any_(eq('cbt_present',False),eq('mapping_matches',False)),eq('alternative_authorised',False)),'outcome':'referred'},
 {'when':all_(eq('scenario','S3'),eq('cbt_present',False),any_(eq('alternative_authorised',False),{'field':'alternative_authorised','op':'missing'})),'outcome':'referred'},
 {'when':all_(eq('scenario','S4'),any_(eq('fibre_connected',False),eq('optical_test','failed'),eq('service_live',False))),'outcome':'partial'},
 {'when':all_(eq('scenario','S5'),eq('work_stage','network_acceptance'),eq('all_network_stages_accepted'),eq('premises_ready'),eq('terminal_available_mapped'),eq('as_built_accepted'),eq('downstream_handoff')),'outcome':'network_ready'},
 {'when':all_(eq('scenario','S5'),eq('downstream_handoff'),any_(all_(eq('work_stage','survey'),present('survey_reference'),present('route_distance'),present('route_constraints')),all_(eq('work_stage','design'),eq('design_accepted')),all_(eq('work_stage','civils'),eq('civils_to_design'),eq('reinstatement_accepted'),eq('as_built_accepted')),all_(eq('work_stage','fibre'),eq('fibre_placed_spliced'),eq('splice_tests_accepted'),eq('as_built_accepted')),all_(eq('work_stage','distribution'),eq('fibre_placed_spliced'),eq('splice_tests_accepted'),eq('as_built_accepted'),eq('terminal_available_mapped')))),'outcome':'stage_completed'},
 {'when':all_(final,connected,optical,eq('service_live'),access,any_(eq('safety_hazard',False),eq('hazard_mitigated')),eq('site_handover_safe'),eq('work_outstanding',False)),'outcome':'completed'},
]
for f in fields.values():
 f['voice']['question']=f['label'].rstrip('?')+'?'
 f['voice']['description']=f["label"]+'. Extract explicit facts only; never infer measurements, test results, permission or safety clearance.'
policy={'id':'fttp-closure-mvp','version':3,'banks':banks,'rules':rules,'dispositions':dispositions,'holdRequired':['scenario','identity_verified','work_stage','claimed_outcome','actual_work','safety_hazard','safety_escalation','next_owner','follow_on_ref','next_action']}
schema={'schemaFormatVersion':1,'templateId':'40000000-0000-4000-8000-000000000006','engineerTypeId':'30000000-0000-4000-8000-000000000006','title':'FTTP closure assistant · synthetic MVP','sections':[{'id':'context','label':'Job context','order':0},{'id':'capture','label':'Applicable checks','order':1},{'id':'handoff','label':'Handover & referral','order':2}],'fields':list(fields.values()),'closurePolicy':policy}
(ROOT/'fixtures/templates/closure-mvp.json').write_text(json.dumps(schema,indent=2)+'\n')
print(f'Compiled {len(fields)} canonical facts, 125 bank entries, {len(rules)} gates.')
