import {PageAccess} from '@/components/page-access';
import {VisitSummaryDetail} from '@/components/visit-summaries';
export default function Page(){return <PageAccess permission="reports.read"><VisitSummaryDetail/></PageAccess>;}
