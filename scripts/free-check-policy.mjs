export const PERIOD_MS = 12 * 60 * 60 * 1000;
export function nextDeadline(now) {
  if (!Number.isFinite(now)) throw Error('Invalid verification clock');
  return new Date((Math.floor(now / PERIOD_MS) + 1) * PERIOD_MS).toISOString();
}
export async function checkAndRenew({readContracts, readSettings, renew, halt, clock = Date.now}) {
  try {
    const rows = await readContracts();
    if (!Array.isArray(rows)) throw Error('Contracts unavailable');
    const plans = rows.map(r => ({id:r.rate_plan?.id,name:r.rate_plan?.public_name,state:r.state}));
    if (plans.some(r => !r.id || !r.name || (/workers?/i.test(r.id+' '+r.name) && !/free/i.test(r.id+' '+r.name)))) throw Error('Free contract not established');
    const settings = await readSettings();
    const bindings = settings?.bindings;
    if (!Array.isArray(bindings)) throw Error('Bindings unavailable');
    const text = name => bindings.find(b => b.name===name && b.type==='plain_text')?.text;
    const models = JSON.parse(text('CONNECTED_MODELS'));
    if (!Array.isArray(models) || models.length!==1 || models[0]!=='@cf/google/gemma-4-26b-a4b-it' || !bindings.some(b => b.name==='AI' && b.type==='ai') || text('AI_BUDGET_MODE')!=='free-provider-hard-stop') throw Error('Route not established');
    const now = clock();
    return await renew({plans,models,verifiedAt:new Date(now).toISOString(),expiresAt:nextDeadline(now)});
  } catch {
    let revoked = false;
    try { await halt(); revoked = true; } catch { /* Worker independently enforces the UTC deadline. */ }
    throw Error(revoked ? 'Free verification failed; current evidence revoked' : 'Free verification failed; revocation unreachable; Worker deadline remains enforced');
  }
}
