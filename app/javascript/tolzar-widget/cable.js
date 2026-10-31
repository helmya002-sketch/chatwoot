// Tolzar widget: a small client for the app's live channel (the ActionCable wire protocol: welcome,
// subscribe, confirm_subscription, ping, message). One subscription (RoomChannel with the contact's pubsub
// token). The server pings every 3 s; with no frame for PING_TIMEOUT the socket is replaced, with backoff.

export const PING_TIMEOUT = 10000;
const BACKOFF = [1000, 2000, 5000, 10000, 30000];

export function cableUrl(base) {
  const url = new URL('/cable', base);
  url.protocol = url.protocol === 'https:' ? 'wss:' : 'ws:';
  return url.href;
}

export class Cable {
  constructor({ url, pubsubToken, onEvent, WebSocketImpl, timers } = {}) {
    this.url = url;
    this.identifier = JSON.stringify({
      channel: 'RoomChannel',
      pubsub_token: pubsubToken,
    });
    this.onEvent = onEvent || (() => {});
    this.WS = WebSocketImpl || window.WebSocket;
    this.timers = timers || { set: setTimeout, clear: clearTimeout };
    this.attempt = 0;
    this.stopped = false;
    this.connected = false;
  }

  start() {
    this.stopped = false;
    this.open();
  }

  stop() {
    this.stopped = true;
    this.timers.clear(this.watchdog);
    this.timers.clear(this.retry);
    if (this.ws) this.ws.close();
  }

  open() {
    this.ws = new this.WS(this.url, ['actioncable-v1-json']);
    this.ws.onmessage = e => this.receive(e.data);
    this.ws.onclose = () => this.dropped();
    this.ws.onerror = () => {};
    this.arm();
  }

  arm() {
    this.timers.clear(this.watchdog);
    this.watchdog = this.timers.set(() => this.reconnect(), PING_TIMEOUT);
  }

  receive(raw) {
    this.arm();
    let frame;
    try {
      frame = JSON.parse(raw);
    } catch {
      return;
    }
    if (frame.type === 'welcome') {
      this.ws.send(
        JSON.stringify({ command: 'subscribe', identifier: this.identifier })
      );
    } else if (frame.type === 'confirm_subscription') {
      this.attempt = 0;
      this.connected = true;
      this.onEvent({ event: 'tz.connected' });
    } else if (frame.type === 'disconnect') {
      this.reconnect();
    } else if (!frame.type && frame.message && frame.message.event) {
      this.onEvent(frame.message);
    }
  }

  reconnect() {
    if (this.ws) {
      this.ws.onclose = null;
      this.ws.close();
    }
    this.dropped();
  }

  dropped() {
    this.connected = false;
    this.timers.clear(this.watchdog);
    if (this.stopped) return;
    const wait = BACKOFF[Math.min(this.attempt, BACKOFF.length - 1)];
    this.attempt += 1;
    this.timers.clear(this.retry);
    this.retry = this.timers.set(() => this.open(), wait);
  }
}
