import {headers} from 'next/headers';
import {redirect} from 'next/navigation';
import {authenticate} from '@/server/auth';
import {canUseDashboard} from '@field-assist/contracts';
import {Shell} from '@/components/shell';
export default async function Layout({children}:{children:React.ReactNode}){
  let user;try{const h=await headers();const ctx=await authenticate(new Request('http://localhost/api/v1/me',{headers:{cookie:h.get('cookie')??''}}));if(!canUseDashboard(ctx.user.role))redirect('/login');user={avatarId:ctx.user.avatarId,id:ctx.user.id,role:ctx.user.role,name:ctx.user.name,email:ctx.user.email};}catch{redirect('/login');}
  return <Shell user={user}>{children}</Shell>;
}
