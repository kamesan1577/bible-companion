import { validateAuthConfig } from '../../../packages/core/src/auth-config';
import { Hono } from 'hono';
import { getCookie, setCookie, deleteCookie } from 'hono/cookie';
import {
  generateAuthenticationOptions,
  generateRegistrationOptions,
  verifyAuthenticationResponse,
  verifyRegistrationResponse,
  type AuthenticationResponseJSON,
  type RegistrationResponseJSON,
  type AuthenticatorTransport,
} from '@simplewebauthn/server';
import { z } from 'zod';
import { base64url, decode64, randomToken, sha256 } from '@bible/core';
import type { AppEnv, Env, User } from './types';
import { body, fail, now } from './http';
import { authPage } from './auth-page';
const cookieName = 'bible_auth_flow';
type Flow = {
  id_hash: string;
  state: string;
  pkce_challenge: string;
  challenge: string | null;
  mode: string | null;
  pending_user_id: string | null;
  expires_at: number;
};
export { validateAuthConfig } from '../../../packages/core/src/auth-config';
export const auth = new Hono<AppEnv>();
auth.use('*', async (c, next) => {
  validateAuthConfig(c.env);
  c.header('Cache-Control', 'no-store');
  c.header('Referrer-Policy', 'no-referrer');
  if (c.req.method === 'POST' && c.req.path !== '/auth/token') {
    if (c.req.header('Origin') !== c.env.AUTH_ORIGIN)
      fail(403, 'origin_rejected', 'Authentication requires the configured origin');
  }
  await next();
});
auth.get('/authorize', async (c) => {
  const params = z
    .object({
      state: z.string().regex(/^[A-Za-z0-9_-]{22,128}$/),
      code_challenge: z.string().regex(/^[A-Za-z0-9_-]{43}$/),
      code_challenge_method: z.literal('S256'),
    })
    .safeParse({
      state: c.req.query('state'),
      code_challenge: c.req.query('code_challenge'),
      code_challenge_method: c.req.query('code_challenge_method'),
    });
  if (!params.success)
    fail(400, 'invalid_authorization', 'Valid state and S256 PKCE challenge required');
  const token = randomToken();
  await c.env.DB.prepare(
    'INSERT INTO auth_flows(id_hash,state,pkce_challenge,expires_at) VALUES(?,?,?,?)',
  )
    .bind(await sha256(token), params.data.state, params.data.code_challenge, now() + 300)
    .run();
  setCookie(c, cookieName, token, {
    httpOnly: true,
    secure: new URL(c.env.AUTH_ORIGIN).protocol === 'https:',
    sameSite: 'Strict',
    path: '/auth',
    maxAge: 300,
  });
  c.header(
    'Content-Security-Policy',
    "default-src 'none'; script-src 'self'; style-src 'self'; connect-src 'self'; base-uri 'none'; form-action 'self'; frame-ancestors 'none'",
  );
  return c.html(authPage);
});
auth.get('/client.js', (c) => {
  c.header('Content-Type', 'text/javascript; charset=utf-8');
  return c.body(clientScript);
});
auth.get('/style.css', (c) => {
  c.header('Content-Type', 'text/css; charset=utf-8');
  return c.body(
    'body{font:18px system-ui;max-width:32rem;margin:10vh auto;padding:1.5rem;background:#f7f5ef;color:#243127}button,input{font:inherit;padding:.8rem;margin:.5rem 0;box-sizing:border-box;width:100%}button{border:0;border-radius:1rem;background:#405a45;color:white}label{display:block}#status{min-height:3rem}',
  );
});
async function flow(c: Parameters<typeof body>[0]): Promise<Flow> {
  const token = getCookie(c, cookieName);
  if (!token) fail(401, 'flow_missing', 'Restart login from the app');
  const row = await c.env.DB.prepare('SELECT * FROM auth_flows WHERE id_hash=? AND expires_at>?')
    .bind(await sha256(token), now())
    .first<Flow>();
  if (!row) fail(401, 'flow_expired', 'Restart login from the app');
  return row;
}
auth.post('/options', async (c) => {
  const input = await body(c, z.object({ mode: z.enum(['login', 'register']) }).strict());
  const f = await flow(c);
  const userId = crypto.randomUUID();
  const options =
    input.mode === 'register'
      ? await generateRegistrationOptions({
          rpName: '聖書読書コンパニオン',
          rpID: c.env.RP_ID,
          userID: new TextEncoder().encode(userId),
          userName: 'Bible reader',
          attestationType: 'none',
          authenticatorSelection: { residentKey: 'required', userVerification: 'required' },
        })
      : await generateAuthenticationOptions({ rpID: c.env.RP_ID, userVerification: 'required' });
  await c.env.DB.prepare(
    'UPDATE auth_flows SET challenge=?,mode=?,pending_user_id=? WHERE id_hash=? AND expires_at>?',
  )
    .bind(
      options.challenge,
      input.mode,
      input.mode === 'register' ? userId : null,
      f.id_hash,
      now(),
    )
    .run();
  return c.json({ options });
});
auth.post('/verify', async (c) => {
  const input = await body(
    c,
    z
      .object({
        response: z.record(z.string(), z.unknown()),
        invitation: z.string().max(200).optional(),
        displayName: z.string().trim().min(1).max(60).optional(),
      })
      .strict(),
  );
  const f = await flow(c);
  if (!f.challenge) fail(409, 'challenge_consumed', 'Request a fresh challenge');
  // Consume BEFORE verification: simultaneous/replayed assertions can never create two sessions.
  const claimed = await c.env.DB.prepare(
    'UPDATE auth_flows SET challenge=NULL WHERE id_hash=? AND challenge=? AND expires_at>? RETURNING id_hash',
  )
    .bind(f.id_hash, f.challenge, now())
    .first();
  if (!claimed) fail(409, 'challenge_consumed', 'Request a fresh challenge');
  let userId: string;
  try {
    if (f.mode === 'register') {
      if (!input.invitation || !f.pending_user_id)
        fail(403, 'invitation_required', 'Registration requires an invitation');
      const verified = await verifyRegistrationResponse({
        response: input.response as unknown as RegistrationResponseJSON,
        expectedChallenge: f.challenge,
        expectedOrigin: c.env.AUTH_ORIGIN,
        expectedRPID: c.env.RP_ID,
        requireUserVerification: true,
      });
      if (!verified.verified || !verified.registrationInfo)
        fail(401, 'invalid_passkey', 'Passkey verification failed');
      const invitationHash = await sha256(input.invitation);
      const invite = await c.env.DB.prepare(
        'SELECT role FROM invitations WHERE token_hash=? AND expires_at>?',
      )
        .bind(invitationHash, now())
        .first<{ role: 'owner' | 'member' }>();
      if (!invite) fail(403, 'invalid_invitation', 'Invitation is invalid or expired');
      userId = f.pending_user_id;
      const info = verified.registrationInfo;
      const credential = info.credential;
      await c.env.DB.batch([
        c.env.DB.prepare(
          'INSERT INTO users(id,display_name,role,created_at) SELECT ?,?,role,? FROM invitations WHERE token_hash=? AND expires_at>?',
        ).bind(userId, input.displayName ?? '読書する人', now(), invitationHash, now()),
        c.env.DB.prepare(
          'INSERT INTO credentials(id,user_id,public_key,counter,transports_json,device_type,backed_up,created_at) VALUES(?,?,?,?,?,?,?,?)',
        ).bind(
          credential.id,
          userId,
          base64url(credential.publicKey),
          credential.counter,
          JSON.stringify(credential.transports ?? []),
          info.credentialDeviceType,
          info.credentialBackedUp ? 1 : 0,
          now(),
        ),
        c.env.DB.prepare('DELETE FROM invitations WHERE token_hash=?').bind(invitationHash),
      ]);
    } else if (f.mode === 'login') {
      const id = input.response.id;
      if (typeof id !== 'string') fail(401, 'invalid_passkey', 'Passkey verification failed');
      const credential = await c.env.DB.prepare('SELECT * FROM credentials WHERE id=?')
        .bind(id)
        .first<{
          id: string;
          user_id: string;
          public_key: string;
          counter: number;
          transports_json: string;
        }>();
      if (!credential) fail(401, 'invalid_passkey', 'Passkey verification failed');
      const verified = await verifyAuthenticationResponse({
        response: input.response as unknown as AuthenticationResponseJSON,
        expectedChallenge: f.challenge,
        expectedOrigin: c.env.AUTH_ORIGIN,
        expectedRPID: c.env.RP_ID,
        requireUserVerification: true,
        credential: {
          id: credential.id,
          publicKey: new Uint8Array(decode64(credential.public_key)),
          counter: credential.counter,
          transports: JSON.parse(credential.transports_json) as AuthenticatorTransport[],
        },
      });
      if (!verified.verified) fail(401, 'invalid_passkey', 'Passkey verification failed');
      const updated = await c.env.DB.prepare(
        'UPDATE credentials SET counter=? WHERE id=? AND counter=? RETURNING user_id',
      )
        .bind(verified.authenticationInfo.newCounter, id, credential.counter)
        .first();
      if (!updated) fail(409, 'concurrent_assertion', 'Please retry login');
      userId = credential.user_id;
    } else fail(400, 'invalid_flow', 'Request a fresh challenge');
  } catch (error) {
    if (error instanceof Error && error.name === 'HTTPException') throw error;
    fail(401, 'invalid_passkey', 'Passkey verification failed');
  }
  const code = randomToken();
  await c.env.DB.batch([
    c.env.DB.prepare(
      'INSERT INTO auth_codes(code_hash,user_id,pkce_challenge,expires_at) VALUES(?,?,?,?)',
    ).bind(await sha256(code), userId, f.pkce_challenge, now() + 60),
    c.env.DB.prepare('DELETE FROM auth_flows WHERE id_hash=?').bind(f.id_hash),
  ]);
  deleteCookie(c, cookieName, { path: '/auth' });
  const url = new URL(c.env.NATIVE_CALLBACK);
  url.searchParams.set('code', code);
  url.searchParams.set('state', f.state);
  return c.json({ callback: url.href });
});
auth.post('/token', async (c) => {
  const input = await body(
    c,
    z
      .object({
        code: z.string().regex(/^[A-Za-z0-9_-]{43}$/),
        codeVerifier: z.string().regex(/^[A-Za-z0-9._~-]{43,128}$/),
      })
      .strict(),
  );
  const row = await c.env.DB.prepare(
    'DELETE FROM auth_codes WHERE code_hash=? AND pkce_challenge=? AND expires_at>? RETURNING user_id',
  )
    .bind(await sha256(input.code), await sha256(input.codeVerifier), now())
    .first<{ user_id: string }>();
  if (!row) fail(401, 'invalid_code', 'The login code expired or was already used');
  const token = randomToken();
  const expiresAt = now() + 30 * 86400;
  await c.env.DB.prepare(
    'INSERT INTO sessions(token_hash,user_id,expires_at,created_at) VALUES(?,?,?,?)',
  )
    .bind(await sha256(token), row.user_id, expiresAt, now())
    .run();
  const user = await c.env.DB.prepare('SELECT id,display_name,role FROM users WHERE id=?')
    .bind(row.user_id)
    .first<User>();
  return c.json({ accessToken: token, tokenType: 'Bearer', expiresAt, user });
});
const clientScript = `const $=id=>document.getElementById(id);const decode=s=>Uint8Array.from(atob(s.replace(/-/g,'+').replace(/_/g,'/')),c=>c.charCodeAt(0));const encode=b=>btoa(String.fromCharCode(...new Uint8Array(b))).replace(/\\+/g,'-').replace(/\\//g,'_').replace(/=+$/,'');async function post(path,data){const r=await fetch(path,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(data)});const j=await r.json();if(!r.ok)throw new Error(j.error?.message||'ログインできませんでした');return j;}async function run(mode){$('status').textContent='パスキーを確認しています…';for(const b of document.querySelectorAll('button'))b.disabled=true;try{const {options}=await post('/auth/options',{mode});options.challenge=decode(options.challenge);if(options.user)options.user.id=decode(options.user.id);if(options.allowCredentials)options.allowCredentials=options.allowCredentials.map(c=>({...c,id:decode(c.id)}));const cred=await navigator.credentials[mode==='register'?'create':'get']({publicKey:options});if(!cred)throw new Error('キャンセルされました');const response={id:cred.id,rawId:encode(cred.rawId),type:cred.type,clientExtensionResults:cred.getClientExtensionResults(),response:{clientDataJSON:encode(cred.response.clientDataJSON)}};if(mode==='register'){response.response.attestationObject=encode(cred.response.attestationObject);response.response.transports=cred.response.getTransports?.()||[];}else{response.response.authenticatorData=encode(cred.response.authenticatorData);response.response.signature=encode(cred.response.signature);response.response.userHandle=cred.response.userHandle?encode(cred.response.userHandle):null;}const out=await post('/auth/verify',{response,...(mode==='register'?{invitation:$('invitation').value,displayName:$('name').value||'読書する人'}:{})});$('status').textContent='ログインしました。アプリへ戻ります。';location.href=out.callback;}catch(e){$('status').textContent=e.name==='NotAllowedError'?'キャンセルされました。もう一度試せます。':e.message;}finally{for(const b of document.querySelectorAll('button'))b.disabled=false;}}$('login').onclick=()=>run('login');$('register').onclick=()=>run('register');`;
