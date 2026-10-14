import { runForwardedChild } from './forwarded-child.mjs';
import { mkdirSync, readFileSync } from 'node:fs';
import {
  validateLocalWranglerInvocation,
  validateScaffoldConfig,
  validateOperatorConfig,
  LOCAL_WRANGLER_ENV,
} from './config.mjs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const selectedConfig = validateLocalWranglerInvocation(process.argv.slice(2));
const configPath = resolve(root, selectedConfig);
if (!configPath.startsWith(root + '/'))
  throw Error('Configuration must be inside this repository.');
(selectedConfig === 'apps/api/wrangler.operator.json'
  ? validateOperatorConfig
  : validateScaffoldConfig)(JSON.parse(readFileSync(configPath, 'utf8')));
const cache = resolve(root, '.cache');
mkdirSync(cache, { recursive: true });
const local =
  process.argv.includes('--local') ||
  process.argv.includes('--dry-run') ||
  process.argv.includes('dev');
const result = await runForwardedChild(
  process.execPath,
  [resolve(root, 'node_modules/wrangler/bin/wrangler.js'), ...process.argv.slice(2)],
  {
    cwd: root,
    stdio: 'inherit',
    env: {
      ...process.env,
      XDG_CONFIG_HOME: local ? resolve(cache, 'config') : process.env.XDG_CONFIG_HOME,
      WRANGLER_LOG_PATH: resolve(cache, 'wrangler.log'),
      ...LOCAL_WRANGLER_ENV,
    },
  },
);
if (result.error) console.error(result.error.message);
process.exitCode =
  result.code ?? (result.signal ? 128 + ({ SIGINT: 2, SIGTERM: 15 }[result.signal] ?? 1) : 1);
