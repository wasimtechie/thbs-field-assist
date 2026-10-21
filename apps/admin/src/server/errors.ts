import {randomUUID} from 'node:crypto';
export class ApiError extends Error{
  constructor(public status:number,public code:string,message:string,public fieldErrors:unknown[]=[],public extra:Record<string,unknown>={}){super(message);}
}
export function errorResponse(error:unknown){
  const e=error instanceof ApiError?error:new ApiError(503,'SERVICE_UNAVAILABLE','The service is unavailable. Please retry.');
  return Response.json({error:{code:e.code,message:e.message,fieldErrors:e.fieldErrors,retryable:e.status===503,requestId:randomUUID(),...e.extra}},{status:e.status});
}
export function notFound():never{throw new ApiError(404,'NOT_FOUND','This record is unavailable.');}
