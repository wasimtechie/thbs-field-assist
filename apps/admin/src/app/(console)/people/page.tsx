import {PeopleDirectory} from '@/components/messaging';
import {PageAccess} from '@/components/page-access';
export default function Page(){return <PageAccess permission="directory.read"><PeopleDirectory/></PageAccess>;}
