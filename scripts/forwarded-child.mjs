import { spawn } from 'node:child_process';
/** Keep local CLI cancellation attached to its child, rather than abandoning a live database writer. */
export function runForwardedChild(command, args, options, parent = process) {
  return new Promise((resolve) => {
    const child = spawn(command, args, options);
    let requestedSignal = null;
    const forward = (signal) => {
      if (child.exitCode === null && child.signalCode === null) {
        requestedSignal = signal;
        child.kill(signal);
      }
    };
    const interrupt = () => forward('SIGINT');
    const terminate = () => forward('SIGTERM');
    parent.on('SIGINT', interrupt);
    parent.on('SIGTERM', terminate);
    const cleanup = () => {
      parent.off('SIGINT', interrupt);
      parent.off('SIGTERM', terminate);
    };
    child.once('error', (error) => {
      cleanup();
      resolve({ code: null, signal: null, error });
    });
    child.once('close', (code, signal) => {
      cleanup();
      resolve({ code: requestedSignal ? null : code, signal: requestedSignal ?? signal });
    });
  });
}
