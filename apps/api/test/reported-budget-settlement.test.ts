import {it,expect}from'vitest';import{reportedBudgetConsumption,reserveBudget,settleBudget}from'../src/budget';import{testEnv,seedUser}from'./helpers/db';
const model='@cf/google/gemma-4-26b-a4b-it';
it('accepts plausible provider metering, rejects fabricated/unknown usage and rounds conservatively',()=>{
 expect(reportedBudgetConsumption(model,{inputTokens:2035,outputTokens:82,providerNeurons:20.7363643646})).toBe(21);
 for(const value of [null,{inputTokens:2035,outputTokens:82},{inputTokens:2035,outputTokens:82,providerNeurons:0},{inputTokens:2035,outputTokens:82,providerNeurons:1},{inputTokens:0,outputTokens:0,providerNeurons:1},{inputTokens:2035,outputTokens:82,providerNeurons:NaN}])expect(reportedBudgetConsumption(model,value)).toBeNull();
});
it('settles one reservation once without borrowing another user allowance; unknown usage stays conservative',async()=>{
 const env=testEnv(),a=await seedUser(env),b=await seedUser(env);await reserveBudget(env,a.id,'measured',162);await reserveBudget(env,b.id,'unknown',162);
 await settleBudget(env,'measured',21);await settleBudget(env,'measured',0);await settleBudget(env,'unknown',null);
 const rows=await env.DB.prepare('SELECT user_id,reserved,consumed FROM user_budget_days ORDER BY user_id').all<{user_id:string;reserved:number;consumed:number}>();
 expect(rows.results.find(r=>r.user_id===a.id)?.consumed).toBe(21);expect(rows.results.find(r=>r.user_id===b.id)?.consumed).toBe(162);
 expect((await env.DB.prepare('SELECT reserved,consumed FROM budget_days').first())).toEqual({reserved:0,consumed:183});
});
