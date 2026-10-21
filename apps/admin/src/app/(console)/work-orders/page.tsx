import {PageAccess} from '@/components/page-access';
import {WorkOrders} from '@/components/operations';
export default function Page(){return <PageAccess permission="work_orders.read"><WorkOrders/></PageAccess>;}
