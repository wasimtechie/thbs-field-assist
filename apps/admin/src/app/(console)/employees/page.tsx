import {People} from '@/components/accounts';
import {PageAccess} from '@/components/page-access';
export default function Page(){return <PageAccess permission="accounts.manage"><People kind="employee"/></PageAccess>;}
