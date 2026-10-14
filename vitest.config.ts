import {defineConfig} from 'vitest/config';
import {fileURLToPath} from 'node:url';
export default defineConfig({resolve:{alias:{'@bible/core':fileURLToPath(new URL('./packages/core/src/index.ts',import.meta.url)),'@bible/ai-harness':fileURLToPath(new URL('./packages/ai-harness/src/index.ts',import.meta.url))}},test:{include:['apps/**/test/**/*.test.ts','packages/**/test/**/*.test.ts'],testTimeout:15000}});
