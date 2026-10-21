export const dashboardRoles=['ADMIN','OPERATIONS_MANAGER','TEAM_LEAD','SALES','TEMPLATE_MANAGER','VIEWER'] as const;
export const accountRoles=[...dashboardRoles,'ENGINEER'] as const;
export type AccountRole=typeof accountRoles[number];
export const roleLabels:Record<AccountRole,string>={ADMIN:'Administrator',OPERATIONS_MANAGER:'Operations Manager',TEAM_LEAD:'Team Lead',SALES:'Sales',TEMPLATE_MANAGER:'Template Manager',VIEWER:'Viewer',ENGINEER:'Field Engineer'};
export const permissionNames=['overview.read','work_orders.read','work_orders.manage','work_orders.respond','reports.read','reports.review','assets.read','templates.read','templates.manage','types.read','types.manage','engineers.read','accounts.manage','devices.read','clients.read','clients.manage','teams.read','teams.manage','directory.read','messages.use','notifications.read','boards.read','boards.manage','time.read','ai.use'] as const;
export type Permission=typeof permissionNames[number];
const collaboration:Permission[]=['directory.read','messages.use','notifications.read','teams.read'];
const grants:Record<AccountRole,readonly Permission[]>={
 ADMIN:permissionNames.filter(p=>p!=='work_orders.respond'),
 OPERATIONS_MANAGER:['ai.use','overview.read','work_orders.read','work_orders.manage','reports.read','reports.review','assets.read','types.read','engineers.read','devices.read','clients.read','clients.manage','boards.read','boards.manage','time.read',...collaboration],
 TEAM_LEAD:['ai.use','overview.read','work_orders.read','work_orders.manage','reports.read','reports.review','assets.read','types.read','engineers.read','clients.read','boards.read','boards.manage','time.read',...collaboration],
 SALES:['ai.use','overview.read','work_orders.read','work_orders.manage','engineers.read','clients.read','clients.manage','boards.read','boards.manage',...collaboration],
 TEMPLATE_MANAGER:['overview.read','templates.read','templates.manage','types.read','types.manage','engineers.read','devices.read',...collaboration],
 VIEWER:['ai.use','boards.read','time.read','overview.read','work_orders.read','reports.read','assets.read',...collaboration],
 ENGINEER:['ai.use','boards.read','time.read','overview.read','work_orders.read','work_orders.respond','reports.read','assets.read','clients.read',...collaboration],
};
export const permissionsFor=(role:string):readonly Permission[]=>(accountRoles as readonly string[]).includes(role)?grants[role as AccountRole]:[];
export const hasPermission=(role:string,permission:Permission)=>permissionsFor(role).includes(permission);
export const canUseDashboard=(role:string)=>(accountRoles as readonly string[]).includes(role);
