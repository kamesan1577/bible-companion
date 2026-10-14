import { existsSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
/** Never rewrite an applied migration. Check existing output or create an explicitly new file. */
export function generatedMigration(defaultName, sql) {
  const args = process.argv.slice(2),
    index = args.indexOf('--output');
  const name = index >= 0 ? args[index + 1] : defaultName;
  if (!/^\d{4}_[a-z0-9_]+\.sql$/.test(name ?? ''))
    throw Error('Expected a numbered migration basename.');
  if (
    args.some(
      (arg, i) => arg !== '--check' && arg !== '--output' && !(index >= 0 && i === index + 1),
    )
  )
    throw Error('Unknown generator argument.');
  const path = new URL('../apps/api/migrations/' + name, import.meta.url);
  if (args.includes('--check')) {
    if (!existsSync(path) || readFileSync(path, 'utf8') !== sql)
      throw Error(
        'Generated seed differs from its declared migration. Create a new numbered migration for content changes.',
      );
    console.log('Verified generated migration ' + name);
    return;
  }
  if (existsSync(path))
    throw Error(
      'Refusing to rewrite an existing migration. Use --check or --output with a new numbered filename.',
    );
  const latest = Math.max(
    ...readdirSync(new URL('../apps/api/migrations/', import.meta.url))
      .filter((x) => /^\d{4}_.*\.sql$/.test(x))
      .map((x) => Number(x.slice(0, 4))),
  );
  if (Number(name.slice(0, 4)) <= latest)
    throw Error('New migrations must have a later sequence number.');
  writeFileSync(fileURLToPath(path), sql, { flag: 'wx' });
  console.log('Created new migration ' + name + '; no database was changed.');
}
