import {PageAccess} from '@/components/page-access';
import {Boards} from '@/components/boards';
export default function Page(){return <PageAccess permission="boards.read"><Boards/></PageAccess>;}
