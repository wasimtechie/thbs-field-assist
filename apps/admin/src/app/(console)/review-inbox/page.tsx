import {PageAccess} from '@/components/page-access';
import {ReviewInbox} from '@/components/operations';
export default function Page(){return <PageAccess permission="reports.read"><ReviewInbox/></PageAccess>;}
