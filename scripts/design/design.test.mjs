import test from 'node:test';
import assert from 'node:assert/strict';
import { contrast, luminance, violations, checkDesign } from './check-design.mjs';
import { tokens, generated } from './generate-tokens.mjs';

test('WCAG sRGB math is independently anchored', () => {
  assert.equal(luminance('#000000'),0);
  assert.equal(luminance('#FFFFFF'),1);
  assert.equal(contrast('#FFFFFF','#000000'),21);
  assert.equal(contrast('#777777','#777777'),1);
  assert.ok(Math.abs(contrast('#FFFFFF','#777777')-4.478089)<0.000001);
});
test('light and dark semantic tokens preserve full role parity', () => {
  assert.deepEqual(Object.keys(tokens.colors), ['canvas','surface','inset','textPrimary','textSecondary','accent','border','danger']);
  for (const pair of Object.values(tokens.colors)) assert.deepEqual(Object.keys(pair),['light','dark']);
  assert.match(generated, /increasedContrast/);
});
test('guard rejects ad-hoc feature styles', () => {
  for (const sample of ['Color(red: 1, green: 0, blue: 0)','Color.white','.foregroundStyle(.gray)','.font(.system(size: 12))','.background(.ultraThinMaterial)','.glassEffect()','.toolbarBackground(.hidden, for: .tabBar)','RoundedRectangle(cornerRadius: 8)','VStack(spacing: 4)','.padding(.horizontal, 20)','.animation(.spring(), value: visible)','.dynamicTypeSize(.large)','WKWebView()']) assert.ok(violations(sample).length, sample);
});
test('guard allows semantic primitives and standard native controls', () => {
  const source='Text(title).bibleTextStyle(.heading).bibleForeground(.textPrimary)\nVStack(spacing: BibleTheme.Space.lg) {}\nButton("Open") {}.buttonStyle(.borderedProminent)\nNavigationStack { TabView {} }.sheet(isPresented: $open) {}';
  assert.equal(violations(source).length,0);
  assert.equal(violations('// Color.white\n/* .font(.body) */').length,0);
});
test('checked-in design contract and feature boundaries pass', () => {
  assert.deepEqual(checkDesign().errors,[]);
});
