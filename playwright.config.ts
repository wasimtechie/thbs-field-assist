import {defineConfig} from '@playwright/test';
export default defineConfig({testDir:'./tests/admin',fullyParallel:false,workers:1,use:{baseURL:'http://localhost:3000',viewport:{width:1440,height:1040},channel:'chrome',screenshot:'only-on-failure',trace:'retain-on-failure'},reporter:[['list'],['html',{open:'never'}]],timeout:60000});
