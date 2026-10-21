import {Prisma} from '@prisma/client';
import {db} from '../../../../packages/database';
import {requirePermission,type Context} from './auth';
import {notFound} from './errors';

// Directory data is independent of operational RBAC. Never return full User/Team rows here.
const personSelect={id:true,name:true,email:true,avatarId:true,role:true,department:true,jobTitle:true,employeeCode:true,baseLocation:true,teamId:true} satisfies Prisma.UserSelect;
const teamSelect={id:true,name:true,department:true,leadId:true} satisfies Prisma.TeamSelect;
const activePeople=(org:string):Prisma.UserWhereInput=>({organizationId:org,disabledAt:null,removedAt:null});

export async function organisation(ctx:Context){
 requirePermission(ctx,'directory.read');
 const org=ctx.user.organizationId,where=activePeople(org);
 const [company,peopleCount,unassignedCount,departments,teams,teamCount]=await Promise.all([
  db.organization.findUniqueOrThrow({where:{id:org},select:{id:true,name:true}}),
  db.user.count({where}),
  db.user.count({where:{...where,OR:[{teamId:null},{teamId:{in:(await db.team.findMany({where:{organizationId:org,archivedAt:{not:null}},select:{id:true}})).map(t=>t.id)}}]}}),
  db.user.groupBy({by:['department'],where,_count:{_all:true}}),
  db.team.findMany({where:{organizationId:org,archivedAt:null},select:teamSelect,orderBy:[{department:'asc'},{name:'asc'},{id:'asc'}],take:201}),
  db.team.count({where:{organizationId:org,archivedAt:null}}),
 ]);
 const visible=teams.slice(0,200),leads=await db.user.findMany({where:{...where,id:{in:visible.map(t=>t.leadId)}},select:personSelect}),leadMap=new Map(leads.map(p=>[p.id,p]));
 const items=await Promise.all(visible.map(async t=>{
  const membersWhere={...where,teamId:t.id,id:{not:t.leadId}};
  const [members,memberCount]=await Promise.all([db.user.findMany({where:membersWhere,select:personSelect,orderBy:[{name:'asc'},{id:'asc'}],take:4}),db.user.count({where:membersWhere})]);
  return {...t,lead:leadMap.get(t.leadId)??null,members,memberCount};
 }));
 const departmentNames=[...new Set([...departments.map(d=>d.department),...items.map(t=>t.department)])].sort((a,b)=>a.localeCompare(b));
 return {organisation:company,counts:{people:peopleCount,teams:teamCount,unassigned:unassignedCount,departments:departmentNames.filter(Boolean).length},departments:departmentNames.map(name=>({name,people:departments.find(d=>d.department===name)?._count._all??0})),teams:items,limited:teams.length>200};
}

export async function colleague(ctx:Context,id:string){
 requirePermission(ctx,'directory.read');
 const org=ctx.user.organizationId,where=activePeople(org);
 const person=await db.user.findFirst({where:{...where,id},select:personSelect});if(!person)notFound();
 const [company,primary,teamsLed]=await Promise.all([
  db.organization.findUniqueOrThrow({where:{id:org},select:{id:true,name:true}}),
  person.teamId?db.team.findFirst({where:{organizationId:org,id:person.teamId,archivedAt:null},select:teamSelect}):null,
  db.team.findMany({where:{organizationId:org,leadId:id,archivedAt:null},select:teamSelect,orderBy:[{name:'asc'},{id:'asc'}]}),
 ]);
 const lead=primary&&primary.leadId!==id?await db.user.findFirst({where:{...where,id:primary.leadId},select:personSelect}):null;
 const reportWhere={...where,id:{not:id},teamId:{in:teamsLed.map(t=>t.id)}};
 const peerWhere={...where,id:{notIn:[id,...(primary?[primary.leadId]:[])]},teamId:primary?.id??'00000000-0000-4000-8000-000000000000'};
 const [reports,reportCount,peers,peerCount]=await Promise.all([
  db.user.findMany({where:reportWhere,select:personSelect,orderBy:[{name:'asc'},{id:'asc'}],take:20}),db.user.count({where:reportWhere}),
  db.user.findMany({where:peerWhere,select:personSelect,orderBy:[{name:'asc'},{id:'asc'}],take:8}),db.user.count({where:peerWhere}),
 ]);
 return {person,organisation:company,primaryTeam:primary?{...primary,lead}:null,teamsLed,reports,reportCount,peers,peerCount,reportingBasis:'Primary squad membership and responsible team lead'};
}
