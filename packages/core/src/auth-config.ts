export interface AuthConfig {
  ENVIRONMENT: string;
  AUTH_ORIGIN: string;
  RP_ID: string;
  NATIVE_CALLBACK: string;
}
export function validateAuthConfig(env: AuthConfig): void {
  const origin = new URL(env.AUTH_ORIGIN);
  const local = env.ENVIRONMENT === 'development' && origin.hostname === 'localhost';
  if (
    (!local &&
      (env.RP_ID === 'localhost' ||
        /^\d+\.\d+\.\d+\.\d+$/.test(env.RP_ID) ||
        env.RP_ID.includes(':') ||
        !env.RP_ID.includes('.'))) ||
    origin.origin !== env.AUTH_ORIGIN ||
    (origin.protocol !== 'https:' && !(local && origin.protocol === 'http:')) ||
    (origin.hostname !== env.RP_ID && !origin.hostname.endsWith('.' + env.RP_ID)) ||
    env.RP_ID.includes('/') ||
    !env.RP_ID
  )
    throw new Error('Invalid stable authentication origin/RP configuration');
  const callback = new URL(env.NATIVE_CALLBACK);
  if (
    callback.protocol !== 'biblecompanion:' ||
    callback.host !== 'auth' ||
    callback.pathname !== '/callback' ||
    callback.search ||
    callback.hash ||
    callback.username ||
    callback.password
  )
    throw new Error('Invalid native callback');
}
