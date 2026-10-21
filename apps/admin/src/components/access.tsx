'use client';
import {createContext,useContext} from 'react';
import {permissionsFor,type Permission} from '@field-assist/contracts/access';
const AccessContext=createContext<readonly Permission[]>([]);
export function AccessProvider({role,children}:{role:string;children:React.ReactNode}){return <AccessContext.Provider value={permissionsFor(role)}>{children}</AccessContext.Provider>;}
export function useAccess(){const permissions=useContext(AccessContext);return (permission:Permission)=>permissions.includes(permission);}
