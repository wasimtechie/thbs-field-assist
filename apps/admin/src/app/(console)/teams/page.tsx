import {Teams} from '@/components/client-teams';
import {PageAccess} from '@/components/page-access';
export default function Page(){return <PageAccess permission="teams.read"><Teams/></PageAccess>;}
