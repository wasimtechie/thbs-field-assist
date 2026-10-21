import {PageAccess} from '@/components/page-access';
import {SubmissionDetail} from '@/components/submissions';
export default function Page(){return <PageAccess permission="reports.read"><SubmissionDetail/></PageAccess>;}
