import {canUseDashboard} from '@field-assist/contracts';
import {headers} from 'next/headers';
import {redirect} from 'next/navigation';
import {authenticate} from '@/server/auth';
import Login from '@/components/login';
export default async function Page(){
 let signedIn=false;
 try {const h=await headers();const c=await authenticate(new Request('http://localhost/api/v1/me',{headers:{cookie:h.get('cookie')??''}}));signedIn=canUseDashboard(c.user.role);}catch{}
 if(signedIn)redirect('/dashboard');
 return <Login/>;
}
