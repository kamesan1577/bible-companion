// Pinned build-output helper: cf's Wrangler delegate currently needs an assets
// directory its public config type cannot express; write the same official output spec.
import {resolve} from 'node:path';
import {mkdir} from 'node:fs/promises';
import {build} from 'esbuild';
import config from '../apps/api/cloudflare.config.ts';
import {readBundledScriptureAssetInputs,planScriptureAssets,writeScriptureAssetPlan} from './build-scripture-assets.mjs';
import {writeAssets,readBuildOutput,writeWorkerConfig,writeRootConfig,getWorkerBundleDir,cleanBuildOutputDir} from '@cloudflare/build-output-utils';
const plan=planScriptureAssets(readBundledScriptureAssetInputs());
writeScriptureAssetPlan(plan,'.cache/scripture/assets');
const api=resolve('apps/api');await cleanBuildOutputDir(api);
const bundle=getWorkerBundleDir(api);await mkdir(bundle,{recursive:true});
await build({entryPoints:[resolve('apps/api/src/index.ts')],bundle:true,format:'esm',platform:'neutral',target:'es2022',conditions:['workerd','worker','browser'],mainFields:['browser','module','main'],external:['cloudflare:*','node:*'],outfile:resolve(bundle,'index.js'),tsconfig:resolve('tsconfig.json')});
await writeAssets({root:api,sourceDirectory:resolve('.cache/scripture/assets')});
await writeWorkerConfig({root:api,config:config.worker,manifest:{type:'complete',mainModule:'index.js',modules:{'index.js':{type:'esm'}}}});
const {worker,...settings}=config;await writeRootConfig(api,settings,{isPreview:false});
const output=await readBuildOutput(api);
if(!output.workers.default.assetsDir)throw Error('Assets absent from validated build output');
console.log(JSON.stringify({assets:plan.summary,buildOutputValidated:true}));
