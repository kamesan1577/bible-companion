import { z } from 'zod';
import { compareVerse, passageSchema, type Passage } from './index.ts';
const safeUrl = z
  .string()
  .url()
  .max(2000)
  .refine((value) => {
    const url = new URL(value);
    return (
      url.protocol === 'https:' &&
      !url.username &&
      !url.password &&
      !url.port &&
      /^(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)+[a-z]{2,}$/i.test(url.hostname) &&
      !/\.(?:localhost|local|internal|test|invalid|example)$/i.test(url.hostname)
    );
  }, 'Only public HTTPS source URLs are allowed');
const reviewedArtworkImageHosts = new Set([
  'api.nga.gov',
  'images.metmuseum.org',
  'openaccess-cdn.clevelandart.org',
]);
const imageUrl = safeUrl.refine((value) => {
  const url = new URL(value);
  if (url.hash) return false;
  if (reviewedArtworkImageHosts.has(url.hostname)) return !url.search;
  if (url.hostname !== 'www.clevelandart.org' || url.pathname !== '/_next/image') return false;
  const params = url.searchParams;
  if (
    params.size !== 3 ||
    params.get('w') !== '1920' ||
    params.get('q') !== '75' ||
    !params.has('url')
  )
    return false;
  try {
    const source = new URL(params.get('url')!);
    if (
      source.protocol !== 'https:' ||
      source.hostname !== 'piction.clevelandart.org' ||
      source.pathname !== '/cma/ump.di' ||
      source.username ||
      source.password ||
      source.port ||
      source.hash
    )
      return false;
    const patterns: Record<string, RegExp> = {
      e: /^[A-Fa-f0-9]{64}$/,
      s: /^[0-9]{1,12}$/,
      se: /^[0-9]{1,12}$/,
      v: /^[0-9]{1,3}$/,
      f: /^[A-Za-z0-9._\\-]+[.]jpg$/,
    };
    return (
      source.searchParams.size === 5 &&
      Object.entries(patterns).every(
        ([key, pattern]) =>
          source.searchParams.getAll(key).length === 1 &&
          pattern.test(source.searchParams.get(key)!),
      )
    );
  } catch {
    return false;
  }
}, 'Only reviewed museum image hosts are allowed');
const shortText = z.string().trim().min(1).max(1000);
const date = z.string().regex(/^\d{4}-\d{2}-\d{2}$/);
const provenance = z
  .object({
    id: z.string().min(1).max(100),
    title: shortText,
    url: safeUrl,
    publisher: shortText,
    checkedAt: date,
    license: z.enum([
      'public-domain',
      'original-commentary',
      'citation-only',
      'cc-by-3.0',
      'odbl-1.0',
    ]),
    licenseUrl: safeUrl.optional(),
    attribution: shortText.optional(),
  })
  .strict()
  .superRefine((value, context) => {
    if (
      ['cc-by-3.0', 'odbl-1.0'].includes(value.license) &&
      (!value.attribution || !value.licenseUrl)
    )
      context.addIssue({
        code: 'custom',
        message: 'Attribution licenses require attribution and a license URL',
      });
  });
const coordinates = z
  .object({
    latitude: z.number().min(-90).max(90),
    longitude: z.number().min(-180).max(180),
    certainty: z.enum(['verified', 'approximate', 'disputed']),
    sourceId: z.string().min(1),
    explanation: shortText,
  })
  .strict();
const base = z.object({
  id: z.string().regex(/^[a-z0-9][a-z0-9-]{1,100}$/),
  title: z.string().trim().min(1).max(160),
  summary: shortText,
  passages: z.array(passageSchema).min(1).max(12),
  spoilerEnd: z
    .object({
      book: z.string(),
      chapter: z.number().int().positive(),
      verse: z.number().int().positive(),
    })
    .strict(),
  version: z.string().min(1).max(100),
  reviewed: z.boolean(),
  rightsStatus: z.enum(['approved', 'pending', 'revoked']),
  relationship: z.enum(['direct', 'thematic']),
  provenance: z.array(provenance).min(1).max(10),
});
export const materialSchema = z
  .discriminatedUnion('kind', [
    base
      .extend({
        kind: z.literal('person'),
        details: z.object({ identityNote: shortText.optional() }).strict(),
      })
      .strict(),
    base
      .extend({
        kind: z.literal('place'),
        details: z
          .object({
            coordinates: coordinates.nullable(),
            identificationCertainty: z.enum(['confirmed', 'uncertain']),
            modernName: shortText.optional(),
          })
          .strict(),
      })
      .strict(),
    base
      .extend({
        kind: z.literal('artwork'),
        details: z
          .object({
            artist: shortText,
            yearLabel: shortText,
            collection: shortText,
            objectUrl: safeUrl,
            rightsStatement: shortText,
            media: z
              .object({
                url: imageUrl,
                rights: z.literal('public-domain'),
                rightsUrl: safeUrl,
                attribution: shortText,
                checkedAt: date,
              })
              .strict()
              .optional(),
          })
          .strict(),
      })
      .strict(),
  ])
  .superRefine((card, context) => {
    const end = { chapter: card.spoilerEnd.chapter, verse: card.spoilerEnd.verse };
    if (!passageSchema.safeParse({ book: card.spoilerEnd.book, start: end, end }).success)
      context.addIssue({ code: 'custom', message: 'Invalid spoiler endpoint' });
    if (
      card.passages.some((p) => p.book !== card.spoilerEnd.book) ||
      !card.passages.some((p) => compareVerse(p.start, end) <= 0)
    )
      context.addIssue({
        code: 'custom',
        message:
          'Card applicability must share the spoiler book and include an appearance by its endpoint',
      });
    const ids = card.provenance.map((p) => p.id);
    if (new Set(ids).size !== ids.length)
      context.addIssue({ code: 'custom', message: 'Duplicate provenance IDs' });
    if (
      card.kind === 'place' &&
      card.details.coordinates &&
      !ids.includes(card.details.coordinates.sourceId)
    )
      context.addIssue({
        code: 'custom',
        message: 'Coordinates require linked primary provenance',
      });
  });
export type MaterialCard = z.infer<typeof materialSchema>;
export function materialVisible(
  card: MaterialCard,
  target: Passage,
  spoilerAllowed: boolean,
): boolean {
  if (!card.reviewed || card.rightsStatus !== 'approved') return false;
  if (
    !card.passages.some(
      (p) =>
        p.book === target.book &&
        compareVerse(p.start, target.end) <= 0 &&
        compareVerse(target.start, p.end) <= 0,
    )
  )
    return false;
  return (
    spoilerAllowed ||
    (card.spoilerEnd.book === target.book && compareVerse(card.spoilerEnd, target.end) <= 0)
  );
}

/** Association metadata can itself reveal later scenes, so trim it before sending a card. */
export function projectMaterial(
  card: MaterialCard,
  target: Passage,
  spoilerAllowed: boolean,
): MaterialCard {
  if (spoilerAllowed) return structuredClone(card);
  return {
    ...structuredClone(card),
    passages: card.passages
      .filter((p) => p.book === target.book && compareVerse(p.start, target.end) <= 0)
      .map((p) => ({ ...p, end: compareVerse(p.end, target.end) > 0 ? { ...target.end } : p.end })),
  };
}
