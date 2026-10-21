import {Messages} from '@/components/messaging';
import {PageAccess} from '@/components/page-access';
export default function Page(){return <PageAccess permission="messages.use"><Messages/></PageAccess>;}
