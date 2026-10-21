'use client';
import {useCallback,useEffect,useState} from 'react';
export class RequestError extends Error{constructor(message:string,public status:number,public details:unknown[]=[]){super(message);}}
export async function api<T=any>(path:string,init:RequestInit={}):Promise<T>{
  const response=await fetch(`/api/v1/${path}`,{...init,headers:{'Content-Type':'application/json',...init.headers}});
  let body:any;try{body=await response.json();}catch{throw new RequestError('The service returned an unreadable response. Please retry.',response.status);}
  if(!response.ok){if(response.status===401&&typeof window!=='undefined'&&!path.startsWith('auth/'))window.location.assign('/login');throw new RequestError(body.error?.message??'Something went wrong.',response.status,body.error?.fieldErrors??[]);}return body;
}
export function useResource<T=any>(path:string,refreshEveryMs=0){
 const [data,setData]=useState<T|null>(null),[error,setError]=useState(''),[loading,setLoading]=useState(true),[revision,setRevision]=useState(0);
 const reload=useCallback(()=>setRevision(v=>v+1),[]);
 useEffect(()=>{
  let active=true,inFlight=false;
  const load=async(quiet=false)=>{
   if(inFlight)return;inFlight=true;
   if(!quiet){setLoading(true);setError('');}
   try{const result=await api<T>(path);if(active){setData(result);setError('');}}
   catch(e){if(active)setError((e as Error).message);}
   finally{inFlight=false;if(active&&!quiet)setLoading(false);}
  };
  void load();
  const refresh=()=>{if(document.visibilityState==='visible')void load(true);};
  const interval=refreshEveryMs>0?window.setInterval(refresh,refreshEveryMs):undefined;
  if(refreshEveryMs>0)window.addEventListener('focus',refresh);
  return()=>{active=false;if(interval!==undefined)window.clearInterval(interval);window.removeEventListener('focus',refresh);};
 },[path,revision,refreshEveryMs]);
 return {data,error,loading,reload,setData};
}
export const formatDate=(value:string|null|undefined)=>value?new Intl.DateTimeFormat('en-GB',{day:'numeric',month:'short',year:'numeric'}).format(new Date(value)):'Not reported';
export const formatTime=(value:string|null|undefined)=>value?new Intl.DateTimeFormat('en-GB',{day:'numeric',month:'short',hour:'2-digit',minute:'2-digit'}).format(new Date(value)):'Never contacted';
export const initials=(name:string)=>name.split(' ').slice(0,2).map(s=>s[0]).join('');
