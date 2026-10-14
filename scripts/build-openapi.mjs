import { writeFileSync } from 'node:fs';
import { z } from 'zod';
import { materialSchema } from '../packages/core/src/materials.ts';
const ref = (name) => ({ $ref: '#/components/schemas/' + name });
const object = (properties, required = Object.keys(properties), extra = false) => ({
  type: 'object',
  properties,
  required,
  additionalProperties: extra,
});
const text = { type: 'string' },
  bool = { type: 'boolean' },
  uuid = { type: 'string', format: 'uuid' },
  time = { type: 'integer', description: 'Unix timestamp in seconds' };
const array = (items) => ({ type: 'array', items });
const nullable = (s) => ({ anyOf: [s, { type: 'null' }] });
const schemas = {
  ReferenceSystem: object({
    canon: { const: 'protestant-66' },
    versification: { const: 'standard-kjv' },
    requestedTranslation: nullable(text),
    translationAlignment: { const: 'unverified' },
    noticeJa: text,
  }),
  ManifestItem: object({
    id: text,
    version: text,
    rights_status: { enum: ['approved', 'pending', 'revoked'] },
    active: { enum: [0, 1] },
    license: text,
    visibility: text,
    reviewed: bool,
    generationAllowed: bool,
  }),
  ContentManifest: object({
    version: text,
    checkedAt: time,
    items: array(ref('ManifestItem')),
    materials: array(
      object({ id: text, version: text, rights_status: text, active: { enum: [0, 1] } }),
    ),
    corpora: array(
      object({
        id: text,
        version: text,
        edition: text,
        language: text,
        license: text,
        manifestSha256: text,
        state: text,
        rights_status: text,
        active: { enum: [0, 1] },
      }),
    ),
  }),
  MaterialCard: z.toJSONSchema(materialSchema, { target: 'openapi-3.0' }),
  Reading: object({
    checkedAt: time,
    offlineCache: object({
      eligible: bool,
      maxAgeSeconds: { type: 'integer', minimum: 0, maximum: 86400 },
      reason: text,
      allowedFields: array({ const: 'overview' }),
      dependencies: array(object({ id: text, version: text })),
      policyVersion: { const: 1 },
    }),
    passage: ref('Passage'),
    translation: nullable(text),
    spoilerAllowed: bool,
    sourceVersion: text,
    overview: object({
      contentKind: { enum: ['literal-primary-text', 'curated-reference'] },
      noticeJa: text,
      referenceSystem: ref('ReferenceSystem'),
      text,
      claims: array({ type: 'object', additionalProperties: true }),
      citations: array(ref('Citation')),
      mode: { const: 'source-only' },
      modelInvoked: { const: false },
    }),
    sources: array({ type: 'object', additionalProperties: true }),
    people: array(ref('MaterialCard')),
    places: array(ref('MaterialCard')),
    artworks: array(ref('MaterialCard')),
    materialNotice: text,
    cache: { enum: ['public-hit', 'public-miss'] },
  }),
  ScripturePage: object({
    available: bool,
    passage: ref('Passage'),
    corpus: nullable(
      object({
        id: text,
        version: text,
        edition: { const: 'engwebp' },
        language: { const: 'en' },
        license: { const: 'public-domain' },
        manifestSha256: text,
        referenceAlignment: { const: 'canonical-compatible' },
        editorialReview: { const: 'unreviewed' },
      }),
    ),
    items: {
      type: 'array',
      maxItems: 100,
      items: object({ id: text, chapter: { type: 'integer' }, verse: { type: 'integer' }, text }),
    },
    nextCursor: nullable(text),
    sourcePolicyVersion: { type: 'integer' },
    noticeJa: text,
    coverage: { enum: ['unavailable', 'source-coordinate-subset'] },
    omissions: array(
      object({
        chapter: { type: 'integer' },
        verse: { type: 'integer' },
        reason: { enum: ['source_text_empty', 'source_reference_missing'] },
      }),
    ),
    unversifiedTextIncluded: { const: false },
  }),
  Error: object({
    error: object({ code: text, message: text, requestId: text }, ['code', 'message']),
  }),
  Verse: object({
    chapter: { type: 'integer', minimum: 1, maximum: 150 },
    verse: { type: 'integer', minimum: 1, maximum: 176 },
  }),
  Passage: object({
    book: {
      type: 'string',
      description:
        'Canonical 66-book YouVersion ID, e.g. ACT, GEN, 1CO. Actual chapter/verse maxima validated using bundled metadata.',
    },
    start: ref('Verse'),
    end: ref('Verse'),
  }),
  User: object({ id: uuid, display_name: text, role: { enum: ['owner', 'member'] } }),
  ParseImport: object({
    ranges: array(ref('Passage')),
    translation: nullable(text),
    sourceUrl: nullable(text),
    needsConfirmation: bool,
    warnings: array(text),
  }),
  ImportInput: object(
    {
      idempotencyKey: uuid,
      sharedText: { type: 'string', maxLength: 20000 },
      ranges: { type: 'array', items: ref('Passage'), minItems: 1, maxItems: 20 },
      translation: nullable({ type: 'string', pattern: '^[A-Z0-9-]{1,30}$' }),
    },
    ['idempotencyKey'],
  ),
  Import: object({
    id: uuid,
    idempotencyKey: uuid,
    ranges: array(ref('Passage')),
    translation: nullable(text),
    sourceUrl: nullable(text),
    createdAt: time,
  }),
  ImportPage: object({
    items: array(ref('Import')),
    nextCursor: nullable({
      type: 'string',
      description: 'Opaque composite cursor. URL-encode and send as before.',
    }),
  }),
  ConversationInput: object(
    {
      importId: uuid,
      rangeIndex: { type: 'integer', minimum: 0, maximum: 19, default: 0 },
      passage: ref('Passage'),
      spoilerAllowed: { type: 'boolean', default: false },
    },
    ['importId'],
  ),
  Conversation: object(
    {
      id: uuid,
      importId: uuid,
      passage: ref('Passage'),
      readingBoundary: ref('Passage'),
      spoilerAllowed: bool,
      createdAt: time,
      nextMessageCursor: nullable(uuid),
      sourcePolicyVersion: { type: 'integer', minimum: 0 },
      messages: array(ref('Message')),
    },
    ['id', 'importId', 'passage', 'readingBoundary', 'spoilerAllowed', 'createdAt'],
  ),
  ConversationSummary: object({
    id: uuid,
    importId: uuid,
    passage: ref('Passage'),
    readingBoundary: ref('Passage'),
    spoilerAllowed: bool,
    createdAt: time,
    messageCount: { type: 'integer', minimum: 0 },
    lastMessageAt: nullable(time),
  }),
  ConversationPage: object({
    items: array(ref('ConversationSummary')),
    nextCursor: nullable(text),
  }),
  ComparisonSummary: object({
    requestId: uuid,
    status: { enum: ['reserved', 'running', 'complete', 'failed', 'cancelled', 'expired'] },
    saved: bool,
    createdAt: time,
    updatedAt: time,
    trialCount: { type: 'integer', minimum: 0, maximum: 20 },
    errorCode: nullable(text),
  }),
  ComparisonPage: object({ items: array(ref('ComparisonSummary')), nextCursor: nullable(text) }),
  Message: object({
    id: uuid,
    role: { enum: ['user', 'assistant'] },
    content: {
      type: 'object',
      description:
        'User text and server scope, answer result, or {hidden:true,reason} when the current spoiler policy hides a prior answer.',
      additionalProperties: true,
    },
    createdAt: time,
  }),
  QuestionInput: object(
    {
      requestId: uuid,
      question: { type: 'string', minLength: 1, maxLength: 2000 },
      sourceOnly: { type: 'boolean', default: false },
      answerMode: {
        enum: ['reviewed-claim-selection', 'grounded-generation'],
        default: 'reviewed-claim-selection',
      },
    },
    ['requestId', 'question'],
  ),
  AnswerResult: object(
    {
      referenceSystem: ref('ReferenceSystem'),
      answer: text,
      status: { enum: ['answered', 'insufficient-evidence', 'spoiler-boundary'] },
      claims: array({ type: 'object', additionalProperties: true }),
      citations: array(ref('Citation')),
      provider: text,
      modelId: text,
      modelInvoked: bool,
      mode: { enum: ['reviewed-claim-selection', 'grounded-generation', 'source-only'] },
      cacheScope: { const: 'private' },
      usage: { type: 'object', additionalProperties: true },
      timing: { type: 'object', additionalProperties: true },
      warnings: array(text),
      spoilerAllowed: bool,
    },
    [
      'answer',
      'status',
      'claims',
      'citations',
      'modelId',
      'modelInvoked',
      'mode',
      'cacheScope',
      'usage',
      'timing',
      'warnings',
    ],
    true,
  ),
  PrimaryTextVerification: object({
    kind: { const: 'trusted-primary-text' },
    corpusId: text,
    edition: text,
    language: { const: 'en' },
    manifestSha256: { type: 'string', pattern: '^[a-f0-9]{64}$' },
    referenceSystem: { const: 'web-protestant' },
    referenceAlignment: { const: 'canonical-compatible' },
  }),
  MaterialSourceReference: object(
    {
      id: text,
      title: text,
      url: { type: 'string', format: 'uri' },
      publisher: text,
      license: {
        enum: ['public-domain', 'original-commentary', 'citation-only', 'cc-by-3.0', 'odbl-1.0'],
      },
      licenseUrl: { type: 'string', format: 'uri' },
      attribution: text,
      checkedAt: text,
    },
    ['id', 'title', 'url', 'publisher', 'license'],
  ),
  MaterialSummaryProvenance: object({
    kind: { const: 'reviewed-material-summary' },
    materialId: text,
    materialVersion: text,
    materialKind: { enum: ['person', 'place', 'artwork'] },
    references: { type: 'array', minItems: 1, maxItems: 10, items: ref('MaterialSourceReference') },
  }),
  Citation: object(
    {
      sourceId: text,
      sourceKind: { enum: ['scripture', 'commentary'] },
      materialProvenance: ref('MaterialSummaryProvenance'),
      verification: ref('PrimaryTextVerification'),
      title: text,
      url: { type: 'string', format: 'uri' },
      passage: ref('Passage'),
      version: text,
      license: text,
    },
    ['sourceId', 'title', 'passage', 'version', 'license'],
  ),
  RequestResult: object(
    {
      requestId: uuid,
      status: { enum: ['reserved', 'running', 'complete', 'failed', 'cancelled'] },
      result: nullable(ref('AnswerResult')),
    },
    ['requestId', 'status'],
  ),
  ModelSettings: object(
    {
      maxOutputTokens: { type: 'integer', minimum: 64, maximum: 2048 },
      temperature: { type: 'number', minimum: 0, maximum: 2 },
      timeoutMs: { type: 'integer', minimum: 1000, maximum: 30000 },
      stream: { const: false },
      reasoning: {
        enum: ['off', 'low', 'medium', 'high'],
        description: 'Currently rejected unless a verified model adapter supports it.',
      },
    },
    [],
  ),
  ComparisonTrial: object({
    index: { type: 'integer', minimum: 0, maximum: 19 },
    questionIndex: { type: 'integer', minimum: 0, maximum: 9 },
    modelIndex: { type: 'integer', minimum: 0, maximum: 1 },
    modelId: text,
    status: { enum: ['queued', 'running', 'complete', 'failed', 'cancelled'] },
    reservedBudgetUnits: { type: 'integer', minimum: 1 },
    modelInvoked: nullable(bool),
    usageUnknown: bool,
    leaseExpiresAt: nullable(time),
  }),
  ComparisonState: object({
    requestId: uuid,
    status: { enum: ['reserved', 'running', 'complete', 'failed', 'cancelled', 'expired'] },
    phase: { enum: ['preparing', 'ready', 'executing', 'terminal'] },
    saved: bool,
    trialCount: { type: 'integer', minimum: 0, maximum: 20 },
    completedCount: { type: 'integer', minimum: 0, maximum: 20 },
    nextTrialIndex: nullable({ type: 'integer', minimum: 0, maximum: 19 }),
    activeTrialIndex: nullable({ type: 'integer', minimum: 0, maximum: 19 }),
    expiresAt: nullable(time),
    trials: array(ref('ComparisonTrial')),
    results: nullable({ type: 'object', additionalProperties: true }),
    errorCode: nullable(text),
  }),
  ComparisonStep: object({
    state: ref('ComparisonState'),
    trialIndex: { type: 'integer', minimum: 0, maximum: 19 },
    result: nullable({
      anyOf: [ref('AnswerResult'), object({ hidden: { const: true }, reason: text })],
    }),
    replayed: bool,
    resultAvailability: { enum: ['returned', 'saved', 'not_saved'] },
  }),
  ComparisonPlan: object(
    {
      requestId: uuid,
      models: {
        type: 'array',
        minItems: 1,
        maxItems: 2,
        items: object(
          {
            modelId: text,
            settings: ref('ModelSettings'),
            answerMode: { enum: ['reviewed-claim-selection', 'grounded-generation'] },
          },
          ['modelId'],
        ),
      },
      questions: {
        type: 'array',
        minItems: 1,
        maxItems: 10,
        items: object(
          {
            passage: ref('Passage'),
            question: { type: 'string', minLength: 1, maxLength: 2000 },
            spoilerAllowed: bool,
            translation: { type: 'string', pattern: '^[A-Z0-9_-]{1,30}$' },
          },
          ['passage', 'question'],
        ),
      },
      saveResults: { type: 'boolean', default: false },
    },
    ['requestId', 'models', 'questions'],
  ),
};
const paths = {};
function op(
  method,
  path,
  summary,
  {
    input,
    output,
    status = '200',
    additionalSuccess = [],
    contentType = 'application/json',
    auth = true,
    parameters = [],
    description = '',
  } = {},
) {
  const parametersInPath = [...path.matchAll(/\{(\w+)\}/g)].map((m) => ({
    name: m[1],
    in: 'path',
    required: true,
    schema: uuid,
  }));
  (paths[path] ??= {})[method] = {
    summary,
    description,
    security: auth ? [{ bearerAuth: [] }] : [],
    parameters: [...parametersInPath, ...parameters],
    ...(input
      ? { requestBody: { required: true, content: { 'application/json': { schema: input } } } }
      : {}),
    responses: {
      [status]: {
        description: 'Success',
        ...(output ? { content: { [contentType]: { schema: output } } } : {}),
      },
      ...Object.fromEntries(
        additionalSuccess.map((code) => [
          code,
          {
            description: 'Idempotent replay success',
            ...(output ? { content: { [contentType]: { schema: output } } } : {}),
          },
        ]),
      ),
      default: {
        description: 'Explicit error; no private request content included',
        content: { 'application/json': { schema: ref('Error') } },
      },
    },
  };
}
const query = (name, schema, required = false) => ({ name, in: 'query', required, schema });
op('get', '/health', 'Service status', {
  auth: false,
  output: object({ ok: bool, version: text, aiEnabled: bool }),
});
op('get', '/auth/authorize', 'Begin browser passkey flow', {
  auth: false,
  output: text,
  contentType: 'text/html',
  parameters: [
    query('state', { type: 'string', pattern: '^[A-Za-z0-9_-]{22,128}$' }, true),
    query('code_challenge', { type: 'string', pattern: '^[A-Za-z0-9_-]{43}$' }, true),
    query('code_challenge_method', { const: 'S256' }, true),
  ],
  description:
    'Returns HTML with a short-lived HttpOnly SameSite=Strict flow cookie. Native callback is server-configured; no arbitrary redirect URI is accepted.',
});
op('post', '/auth/options', 'Get browser WebAuthn options', {
  auth: false,
  input: object({ mode: { enum: ['login', 'register'] } }),
  output: object({ options: { type: 'object', additionalProperties: true } }),
  description:
    'Requires exact Origin and flow cookie. userVerification=required, discoverable registration credentials.',
});
op('post', '/auth/verify', 'Verify one-use WebAuthn ceremony', {
  auth: false,
  input: object(
    {
      response: { type: 'object', additionalProperties: true },
      invitation: { type: 'string', maxLength: 200 },
      displayName: { type: 'string', minLength: 1, maxLength: 60 },
    },
    ['response'],
  ),
  output: object({ callback: { type: 'string', format: 'uri' } }),
  description:
    'Requires exact Origin and flow cookie. Invitation required for registration. Callback contains only one-time code and state; never bearer credentials.',
});
op('post', '/auth/token', 'Exchange one-time code with PKCE', {
  auth: false,
  input: object({
    code: { type: 'string', pattern: '^[A-Za-z0-9_-]{43}$' },
    codeVerifier: { type: 'string', pattern: '^[A-Za-z0-9._~-]{43,128}$' },
  }),
  output: object({
    accessToken: text,
    tokenType: { const: 'Bearer' },
    expiresAt: time,
    user: ref('User'),
  }),
});
op('get', '/v1/me', 'Current account', { output: object({ user: ref('User') }) });
op('post', '/v1/logout', 'Revoke current native session', { status: '204' });
op('delete', '/v1/me', 'Delete account with fresh authentication', {
  input: object({ confirmation: { const: 'DELETE_MY_ACCOUNT' } }),
  output: { type: 'object', additionalProperties: true },
  description:
    'Requires a session issued within5minutes. Account/passkeys/sessions and all private reading data are deleted; backup erasure policy remains a deployment decision.',
});
op('delete', '/v1/me/reading-data', 'Delete all private reading data', {
  input: object({ confirmation: { const: 'DELETE_MY_READING_DATA' } }),
  output: { type: 'object', additionalProperties: true },
  description: 'Requires a session issued within5minutes. Account is retained.',
});
op('delete', '/v1/developer/comparisons/{id}/history', 'Delete own comparison record', {
  status: '204',
});
op('get', '/v1/me/ai-policy', 'Read allowed answer modes and current experimental consent', {
  output: object({
    allowedAnswerModes: array({ enum: ['reviewed-claim-selection', 'grounded-generation'] }),
    defaultAnswerMode: nullable(text),
    groundedPolicyVersion: text,
    groundedNoticeJa: text,
    workersAiConsent: bool,
    groundedConsent: object({ accepted: bool, policyVersion: nullable(text) }),
  }),
});
op('post', '/v1/me/consents', 'Confirm or revoke Cloudflare AI data transmission', {
  input: object(
    { workersAi: bool, groundedGeneration: object({ accepted: bool, policyVersion: text }) },
    [],
  ),
  output: object({ workersAi: bool }),
});
op('post', '/v1/me/export/snapshots', 'Start a bounded private export snapshot', {
  input: object({}),
  status: '201',
  output: { type: 'object', additionalProperties: true },
  description:
    'Expires after 15 minutes; creating a new snapshot invalidates the previous one. Any private write or source-policy change requires discarding the incomplete file and restarting. Metadata contains user/settings/model preference, never authentication material.',
});
op('get', '/v1/me/export/pages', 'Read one bounded private export page', {
  parameters: [
    query('snapshotId', uuid, true),
    query('section', { enum: ['imports', 'conversations', 'messages', 'comparisons'] }, true),
    query('cursor', text),
  ],
  output: object({
    version: { const: 1 },
    snapshotId: uuid,
    section: text,
    items: array({ type: 'object', additionalProperties: true }),
    nextCursor: nullable(text),
  }),
  description:
    'At most 25 items and 1 MiB encoded JSON per page. A single entity over 1,000,000 bytes fails explicitly. Preserve source-redaction markers and user-authored text. Each cursor is scoped to snapshot and section; a changed/expired snapshot returns409.',
});
op('get', '/v1/me/export', 'Export only this account’s reading data', {
  output: { type: 'object', additionalProperties: true },
  description: 'JSON attachment; credentials and sessions are excluded.',
});
op('post', '/v1/imports/parse', 'Parse shared text transiently', {
  input: object({ sharedText: { type: 'string', maxLength: 20000 } }),
  output: ref('ParseImport'),
});
op('post', '/v1/imports', 'Idempotently save confirmed passage metadata', {
  additionalSuccess: ['200'],
  input: ref('ImportInput'),
  output: ref('Import'),
  status: '201',
  description:
    'Retry returns200 with the same result; different payload with same key returns409. At least sharedText or ranges required. Raw shared text is never persisted.',
});
op('get', '/v1/imports', 'List private reading history', {
  parameters: [query('before', text)],
  output: ref('ImportPage'),
});
op('get', '/v1/imports/{id}', 'Read a private import', { output: ref('Import') });
op('delete', '/v1/imports/{id}', 'Delete import and its conversations', { status: '204' });
op('get', '/v1/imports/{id}/reading', 'Read reviewed sources and public-only cached overview', {
  parameters: [query('rangeIndex', { type: 'integer', minimum: 0 }), query('spoilers', bool)],
  output: ref('Reading'),
  description:
    'No provider is called. Source version keys prevent reuse after source edits/rights revocation. Empty artwork/maps are explicit.',
});
op(
  'get',
  '/v1/imports/{id}/scripture',
  'Read a bounded page of verified public-domain English source text',
  {
    parameters: [
      query('rangeIndex', { type: 'integer', minimum: 0, maximum: 19 }),
      query('after', text),
    ],
    output: ref('ScripturePage'),
    description:
      'Owner-scoped to the selected imported range. At most100 verses and120KB item bytes, with an opaque range/version/policy-bound cursor. Missing corpus returns available:false. Source numbering is retained; empty/missing references are explicit and never remapped. No JCB alignment, editorial interpretation review or offline grant is implied.',
  },
);
op('get', '/v1/content-manifest', 'Current public source versions and rights state', {
  output: ref('ContentManifest'),
  description:
    'Any manifest version change invalidates offline materials, including same-version policy/content corrections.',
});
op('get', '/v1/sources', 'Read approved boundary-filtered sources', {
  parameters: [
    query('passage', { type: 'string', description: 'URL-encoded JSON Passage' }, true),
    query('spoilers', bool),
  ],
  output: { type: 'object', additionalProperties: true },
});
op('get', '/v1/conversations', 'List own private conversations', {
  output: ref('ConversationPage'),
  parameters: [query('importId', uuid), query('before', text)],
  description:
    'At most50 metadata summaries, newest creation first. Cursor binds the optional import filter. Other owners’ import filters return404. Bodies remain in the private detail endpoint.',
});
op('post', '/v1/conversations', 'Start a private passage conversation', {
  input: ref('ConversationInput'),
  output: ref('Conversation'),
  status: '201',
});
op('get', '/v1/conversations/{id}', 'Resume private conversation', {
  description:
    'Latest at most50 messages, chronological within a page, under1MiB after raw-length preflight. beforeMessageId loads older messages. sourcePolicyVersion lets clients reject mixed policy pages. Oversized single messages fail413 without truncation.',
  parameters: [query('beforeMessageId', uuid)],
  output: ref('Conversation'),
});
op('patch', '/v1/conversations/{id}', 'Change spoiler setting', {
  input: object({ spoilerAllowed: bool }),
  output: object({ spoilerAllowed: bool }),
});
op('delete', '/v1/conversations/{id}', 'Delete private conversation', { status: '204' });
op('post', '/v1/conversations/{id}/questions', 'Ask or explicitly request source-only reading', {
  input: ref('QuestionInput'),
  output: ref('RequestResult'),
  description:
    'No automatic retries. Owner model preferences apply only to future answers. Ordinary clients cannot select arbitrary models, URLs, sources or owners. True AI requires recorded consent, connected allowlisted model and verified budget.',
});
op('get', '/v1/requests/{id}', 'Check an existing private question request', {
  output: ref('RequestResult'),
});
op('delete', '/v1/requests/{id}', 'Cancel an active question', {
  output: object({ status: { const: 'cancelled' }, usageMayHaveOccurred: { const: true } }),
  description:
    'Persists an owner-scoped cancellation marker even before claim. GET 404 alone is unknown, not proof of no dispatch. Retry only the same frozen request UUID and payload.',
});
op('get', '/v1/usage', 'Get private daily budget and reset', {
  output: { type: 'object', additionalProperties: true },
});
op('get', '/v1/developer/comparisons', 'List own saved or unsaved comparison metadata', {
  output: ref('ComparisonPage'),
  parameters: [query('saved', { enum: ['true', 'false'], default: 'true' }), query('before', text)],
  description:
    'Owner-only, at most50 metadata items. No question or answer bodies in this list. Cursor binds saved filter; detail reads apply current rights policy.',
});
op('get', '/v1/developer/models', 'Owner-only model registry', {
  output: { type: 'object', additionalProperties: true },
});
op('put', '/v1/developer/model-preference', 'Owner-only verified model selection', {
  input: object({ modelId: text, settings: ref('ModelSettings') }, ['modelId']),
  output: { type: 'object', additionalProperties: true },
});
op('delete', '/v1/developer/model-preference', 'Reset owner’s model preference', { status: '204' });
op('post', '/v1/developer/comparisons/plan', 'Validate and estimate owner-only comparison', {
  input: ref('ComparisonPlan'),
  output: { type: 'object', additionalProperties: true },
});
op(
  'post',
  '/v1/developer/comparisons',
  'Reserve a confirmed owner-only comparison without inference',
  {
    status: '202',
    additionalSuccess: ['200'],
    input: object({
      plan: ref('ComparisonPlan'),
      confirmationHash: { type: 'string', pattern: '^[A-Za-z0-9_-]{43}$' },
    }),
    output: ref('ComparisonState'),
    description:
      'Maximum2 models ×10 questions; one active job per owner. Start reserves only. Explicit steps claim one trial each. Idle expiry is15minutes or the next UTC budget boundary. Unsaved answers are returned once and cannot be reconstructed after a lost acknowledgment.',
  },
);
op(
  'get',
  '/v1/developer/comparisons/{id}',
  'Read own comparison status and optional saved results',
  { output: ref('ComparisonState') },
);
op('get', '/v1/developer/comparisons/active', 'Find own active comparison for explicit recovery', {
  output: object({ comparison: nullable(ref('ComparisonState')) }),
});
op('post', '/v1/developer/comparisons/{id}/steps', 'Claim and execute at most one durable trial', {
  input: object({
    plan: ref('ComparisonPlan'),
    confirmationHash: { type: 'string', pattern: '^[A-Za-z0-9_-]{43}$' },
    trialIndex: { type: 'integer', minimum: 0, maximum: 19 },
  }),
  output: ref('ComparisonStep'),
  description:
    'Replay the exact frozen plan and same trialIndex. Atomic claims prevent repeat invocation. GET ready or404 does not prove that an earlier delayed request cannot still claim. Saved results are projected through current source rights; unsaved acknowledged results cannot be recovered.',
});
op('delete', '/v1/developer/comparisons/{id}', 'Cancel own active comparison', {
  output: object({ status: { const: 'cancelled' }, usageMayHaveOccurred: { const: true } }),
  description:
    'Persists an owner-scoped cancellation marker even before claim. GET 404 alone is unknown, not proof of no dispatch. Retry only the same frozen request UUID and payload.',
});
const spec = {
  openapi: '3.1.0',
  info: {
    title: '聖書読書コンパニオン API',
    version: '0.1.0',
    description:
      'Local-first initial API. No live deployment or AI quality claims. All private operations derive ownership from bearer session.',
  },
  servers: [{ url: 'http://localhost:8787', description: 'Local development only' }],
  paths,
  components: { securitySchemes: { bearerAuth: { type: 'http', scheme: 'bearer' } }, schemas },
};
writeFileSync(
  new URL('../docs/openapi.json', import.meta.url),
  JSON.stringify(spec, null, 2) + '\n',
);
console.log(
  'Generated OpenAPI 3.1 contract: ' +
    Object.values(paths).reduce((n, p) => n + Object.keys(p).length, 0) +
    ' operations.',
);
