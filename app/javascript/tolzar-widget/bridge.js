// Tolzar widget: the message bridge between the iframe app and the loader on the customer's page. It speaks
// the loader's existing contract (a "chattz-widget:" prefix + JSON {event, ...}) so today's snippets keep
// working. Only messages from the parent window are read; we post to the parent only.

export const PREFIX = 'chattz-widget:';

export function encode(event, payload = {}) {
  return `${PREFIX}${JSON.stringify({ event, ...payload })}`;
}

export function decode(data) {
  if (typeof data !== 'string' || !data.startsWith(PREFIX)) return null;
  try {
    const msg = JSON.parse(data.slice(PREFIX.length));
    return msg && typeof msg.event === 'string' ? msg : null;
  } catch {
    return null;
  }
}

export class Bridge {
  constructor({ win = window, handlers = {} } = {}) {
    this.win = win;
    this.handlers = handlers;
    this.listener = e => this.receive(e);
  }

  start() {
    this.win.addEventListener('message', this.listener);
  }

  stop() {
    this.win.removeEventListener('message', this.listener);
  }

  receive(e) {
    if (e.source !== this.win.parent) return;
    const msg = decode(e.data);
    if (!msg) return;
    const fn = this.handlers[msg.event];
    if (typeof fn === 'function') fn(msg);
  }

  // The loader runs on the customer's origin, which the iframe cannot know in advance: '*' is the contract's
  // target. Nothing secret is posted except the visitor's own token, which the loader stores as its cookie.
  send(event, payload) {
    if (this.win.parent && this.win.parent !== this.win) {
      this.win.parent.postMessage(encode(event, payload), '*');
    }
  }
}
