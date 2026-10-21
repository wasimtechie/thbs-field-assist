import {ColleagueProfile} from '@/components/organisation';
import {PageAccess} from '@/components/page-access';
export default async function Page({params}:{params:Promise<{id:string}>}){const {id}=await params;return <PageAccess permission="directory.read"><ColleagueProfile id={id}/></PageAccess>;}
