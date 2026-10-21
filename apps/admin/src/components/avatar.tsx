'use client';
import {useState} from 'react';
import {avatarIds} from '@field-assist/contracts/workspace';
import {initials} from '@/lib/api';
export function Avatar({person,size=32}:{person?:{name?:string;avatarId?:string}|null;size?:number}){const [failed,setFailed]=useState('');const id=person?.avatarId??'',valid=(avatarIds as readonly string[]).includes(id)&&id&&failed!==id;return <span className="person-avatar" style={{width:size,height:size,fontSize:size*.34}}>{valid?<img src={`/avatars/${id}.png`} alt="" width={size} height={size} onError={()=>setFailed(id)}/>:initials(person?.name??'THBS')}</span>;}
export function PersonChip({person,label}:{person:any;label:string}){return <span className="person-chip"><Avatar person={person}/><span><small>{label}</small><strong>{person?.name??'Unavailable'}</strong></span></span>;}
