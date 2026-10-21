import {Clients} from '@/components/client-teams';
import {PageAccess} from '@/components/page-access';
export default function Page(){return <PageAccess permission="clients.read"><Clients/></PageAccess>;}
