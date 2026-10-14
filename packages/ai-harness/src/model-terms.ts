/** Discovery evidence only. Linked terms have not been accepted or legally reviewed by this package. */
export const MODEL_TERMS_POLICY_VERSION = 'workers-ai-terms-2026-10-13.v1';
/** Links explicitly published on the official model pages checked on 2026-10-13.
 * Absence means unknown, never unrestricted. Cloudflare service terms also apply. */
export const PUBLISHED_MODEL_TERMS: Readonly<Record<string, string>> = Object.freeze({
  '@cf/google/gemma-4-26b-a4b-it': 'https://ai.google.dev/gemma/docs/gemma_4_license',
  '@cf/meta/llama-3.2-1b-instruct':
    'https://github.com/meta-llama/llama-models/blob/main/models/llama3_2/LICENSE',
  '@cf/meta/llama-3.2-3b-instruct':
    'https://github.com/meta-llama/llama-models/blob/main/models/llama3_2/LICENSE',
  '@cf/meta/llama-3.1-8b-instruct-fp8':
    'https://github.com/meta-llama/llama-models/blob/main/models/llama3_1/LICENSE',
  '@cf/meta/llama-3.3-70b-instruct-fp8-fast':
    'https://github.com/meta-llama/llama-models/blob/main/models/llama3_3/LICENSE',
  '@cf/meta/llama-4-scout-17b-16e-instruct':
    'https://github.com/meta-llama/llama-models/blob/main/models/llama4/LICENSE',
  '@cf/deepseek-ai/deepseek-r1-distill-qwen-32b':
    'https://github.com/deepseek-ai/DeepSeek-R1/blob/main/LICENSE',
  '@cf/moonshotai/kimi-k2.6': 'https://huggingface.co/moonshotai/Kimi-K2.6/blob/main/LICENSE',
  '@cf/moonshotai/kimi-k2.7-code':
    'https://huggingface.co/moonshotai/Kimi-K2.7-Code/blob/main/LICENSE',
  '@cf/zai-org/glm-5.3-flash': 'https://huggingface.co/zai-org/GLM-5.3-Flash/blob/main/LICENSE',
});
