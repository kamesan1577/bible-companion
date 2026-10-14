/* Local verification preload. Fail before any non-loopback Node DNS/TCP/TLS/HTTP request. */
const net = require('node:net');
const dns = require('node:dns');
const tls = require('node:tls');
const fs = require('node:fs');
let reported = false;
function check(host, port) {
  if (host === undefined || ['localhost', '127.0.0.1', '::1', '[::1]'].includes(host)) return;
  const error = new Error('OFFLINE_VERIFICATION_EXTERNAL_NETWORK_REFUSED');
  if (!reported && process.env.BIBLE_NETWORK_DIAGNOSTIC) {
    reported = true;
    const destination = /^[a-zA-Z0-9.:[\]-]{1,253}$/.test(String(host))
      ? String(host)
      : '<redacted-non-host>';
    const fd = fs.openSync(
      process.env.BIBLE_NETWORK_DIAGNOSTIC,
      fs.constants.O_WRONLY |
        fs.constants.O_APPEND |
        fs.constants.O_CREAT |
        fs.constants.O_NOFOLLOW,
      0o600,
    );
    try {
      fs.writeSync(
        fd,
        JSON.stringify({
          host: destination,
          port: Number.isSafeInteger(Number(port)) ? Number(port) : null,
          stack: error.stack,
        }) + '\n',
      );
    } finally {
      fs.closeSync(fd);
    }
  }
  throw error;
}
function connection(args) {
  if (Array.isArray(args[0])) return connection(args[0]);
  if (args[0] && typeof args[0] === 'object')
    check(args[0].host || args[0].hostname || args[0].servername, args[0].port);
  else if (typeof args[1] === 'string') check(args[1], args[0]);
}
const connect = net.Socket.prototype.connect;
net.Socket.prototype.connect = function (...args) {
  connection(args);
  return connect.apply(this, args);
};
for (const key of [
  'lookup',
  'resolve',
  'resolve4',
  'resolve6',
  'resolveAny',
  'resolveCname',
  'resolveMx',
  'resolveNs',
  'resolvePtr',
  'resolveSoa',
  'resolveSrv',
  'resolveTxt',
  'reverse',
]) {
  if (typeof dns[key] === 'function') {
    const original = dns[key];
    dns[key] = function (host, ...args) {
      check(host);
      return original.call(this, host, ...args);
    };
  }
  if (typeof dns.promises[key] === 'function') {
    const original = dns.promises[key];
    dns.promises[key] = function (host, ...args) {
      check(host);
      return original.call(this, host, ...args);
    };
  }
}
const secure = tls.connect;
tls.connect = function (...args) {
  connection(args);
  return secure.apply(this, args);
};
const originalFetch = globalThis.fetch;
globalThis.fetch = function (input, ...args) {
  check(new URL(typeof input === 'string' || input instanceof URL ? input : input.url).hostname);
  return originalFetch.call(this, input, ...args);
};
