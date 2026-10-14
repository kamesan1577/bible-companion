import { readFileSync, readdirSync } from 'node:fs';
import { relative, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { generated, output, tokens } from './generate-tokens.mjs';
const root = fileURLToPath(new URL('../../', import.meta.url));
export function luminance(hex) {
  const channels = [1,3,5].map(i => parseInt(hex.slice(i,i+2),16) / 255).map(x => x <= 0.04045 ? x / 12.92 : ((x+0.055)/1.055)**2.4);
  return channels[0]*0.2126 + channels[1]*0.7152 + channels[2]*0.0722;
}
export function contrast(a,b) { const x=luminance(a), y=luminance(b); return (Math.max(x,y)+0.05)/(Math.min(x,y)+0.05); }
export function stripComments(source) { return source.replace(/\/\*[\s\S]*?\*\//g, '').replace(/\/\/[^\n]*/g, ''); }
export const rules = [
  ['literal-color', /\bColor\s*\(\s*(?:\.(?:sRGB|displayP3)|red\s*:|white\s*:|hue\s*:|"|hex\s*:)/g],
  ['named-color', /\bColor\.(?:black|white|gray|red|orange|yellow|green|blue|purple|pink|brown|cyan|mint|indigo)\b/g],
  ['literal-color-style', /\.(?:foregroundStyle|foregroundColor|background|tint)\s*\(\s*\.(?:black|white|gray|red|orange|yellow|green|blue|purple|pink|brown|cyan|mint|indigo)\b/g],
  ['feature-font', /\.font\s*\(/g],
  ['custom-material', /\.(?:ultraThinMaterial|thinMaterial|regularMaterial|thickMaterial|ultraThickMaterial)\b|\.glassEffect\s*\(|\.blur\s*\(/g],
  ['custom-navigation-background', /\.(?:toolbarBackground|toolbarColorScheme)\s*\(/g],
  ['literal-radius', /(?:cornerRadius\s*:\s*\d|\.cornerRadius\s*\(\s*\d)/g],
  ['literal-spacing', /(?:spacing\s*:\s*\d|\.padding\s*\(\s*(?:\.[A-Za-z]+\s*,\s*)?\d)/g],
  ['literal-motion', /\.(?:spring|interactiveSpring|easeIn|easeOut|easeInOut|linear)\s*\(/g],
  ['clamped-dynamic-type', /\.dynamicTypeSize\s*\(/g],
  ['fake-native-glass', /\b(?:WKWebView|UIVisualEffectView|UIGlassEffect)\b/g]
];
export function violations(source) {
  const clean = stripComments(source);
  return rules.flatMap(([rule, regex]) => [...clean.matchAll(regex)].map(match => ({ rule, line: clean.slice(0,match.index).split('\n').length })));
}
function swiftFiles(dir) {
  return readdirSync(dir, {withFileTypes:true}).flatMap(entry => entry.isDirectory() ? swiftFiles(join(dir,entry.name)) : entry.name.endsWith('.swift') ? [join(dir,entry.name)] : []);
}
export function checkDesign() {
  const errors=[], ratios=[];
  if (readFileSync(output,'utf8') !== generated) errors.push('Generated Swift tokens are stale.');
  for (const [name,pair] of Object.entries(tokens.colors)) {
    for (const scheme of ['light','dark']) if (!/^#[0-9A-F]{6}$/.test(pair[scheme])) errors.push(`Invalid ${name}.${scheme}`);
  }
  for (const scheme of ['light','dark']) for (const rule of tokens.contrastRequirements) for (const background of rule.backgrounds) {
    const ratio=contrast(tokens.colors[rule.foreground][scheme],tokens.colors[background][scheme]);
    ratios.push({scheme,foreground:rule.foreground,background,ratio:Number(ratio.toFixed(2)),minimum:rule.minimum});
    if (ratio < rule.minimum) errors.push(`${scheme} ${rule.foreground}/${background}: ${ratio.toFixed(2)} < ${rule.minimum}`);
  }
  if (tokens.layout.minimumTouchTarget < 44) errors.push('Touch target must be at least 44 pt.');
  const exceptions=JSON.parse(readFileSync(join(root,'docs/design/exceptions.json'),'utf8'));
  const seen=new Set();
  for (const file of swiftFiles(join(root,'apps/ios'))) {
    const name=relative(root,file).replaceAll('\\','/');
    if (name.includes('/DesignSystem/') || name.includes('/Tests/')) continue;
    for (const violation of violations(readFileSync(file,'utf8'))) {
      const key=`${name}:${violation.rule}`;
      const exception=exceptions.find(x => x.file===name && x.rule===violation.rule && x.rationale && x.adr);
      if (exception) seen.add(key); else errors.push(`${name}:${violation.line} violates ${violation.rule}`);
    }
  }
  for (const exception of exceptions) if (!seen.has(`${exception.file}:${exception.rule}`)) errors.push(`Stale or invalid exception: ${exception.file}:${exception.rule}`);
  return {errors,ratios};
}
if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const {errors,ratios}=checkDesign();
  if (process.argv.includes('--report')) console.table(ratios);
  if (errors.length) { console.error(errors.join('\n')); process.exitCode=1; }
  else console.log(`Design contract passed: ${ratios.length} contrast pairs, generated tokens, and native feature architecture.`);
}
