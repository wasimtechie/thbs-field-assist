import {PageAccess} from '@/components/page-access';
import {AssetHistory} from '@/components/operations';
export default function Page(){return <PageAccess permission="assets.read"><AssetHistory/></PageAccess>;}
