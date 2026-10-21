import {PageAccess} from '@/components/page-access';
import {TimeTracking} from '@/components/time-tracking';
export default function Page(){return <PageAccess permission="time.read"><TimeTracking/></PageAccess>;}
