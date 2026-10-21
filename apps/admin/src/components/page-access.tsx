import Link from 'next/link';
import {headers} from 'next/headers';
import {authenticate} from '@/server/auth';
import {hasPermission,type Permission} from '@field-assist/contracts';
export async function PageAccess({permission,children}:{permission:Permission;children:React.ReactNode}){
 const h=await headers();const ctx=await authenticate(new Request('http://localhost/api/v1/me',{headers:{cookie:h.get('cookie')??''}}));
 if(!hasPermission(ctx.user.role,permission))return <section className="panel" style={{padding:32}}><h1>Access restricted</h1><p className="body-copy">Your access level does not include this area. Ask an administrator if your responsibilities require it.</p><Link className="button primary" href="/dashboard">Return to overview</Link></section>;
 return children;
}
