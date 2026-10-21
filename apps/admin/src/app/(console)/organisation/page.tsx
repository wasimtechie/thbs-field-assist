import {Organisation} from '@/components/organisation';
import {PageAccess} from '@/components/page-access';
export default function Page(){return <PageAccess permission="directory.read"><Organisation/></PageAccess>;}
