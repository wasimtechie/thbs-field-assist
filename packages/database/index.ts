import { PrismaClient } from '@prisma/client';
import { config } from 'dotenv';
import path from 'node:path';
config({path:[path.resolve(process.cwd(),'.env'),path.resolve(process.cwd(),'../../.env')],quiet:true});
const globalDb=globalThis as unknown as {db?:PrismaClient};
export const db=globalDb.db??new PrismaClient();
if(process.env.NODE_ENV!=='production')globalDb.db=db;
