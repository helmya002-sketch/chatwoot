import { describe, it, expect, vi } from 'vitest';
import { Cable, cableUrl, PING_TIMEOUT } from '../cable';

class FakeWS {
  static all = [];

  constructor(url, protocols) {
    this.url = url;
    this.protocols = protocols;
    this.sent = [];
    FakeWS.all.push(this);
  }

  send(data) {
    this.sent.push(JSON.parse(data));
  }

  close() {
    this.closed = true;
    if (this.onclose) this.onclose();
  }

  frame(obj) {
    this.onmessage({ data: JSON.stringify(obj) });
  }
}

const start = () => {
  FakeWS.all = [];
  const events = [];
  const cable = new Cable({
    url: 'wss://chat.example.com/cable',
    pubsubToken: 'pub-1',
    onEvent: e => events.push(e),
    WebSocketImpl: FakeWS,
  });
  cable.start();
  return { cable, events, ws: FakeWS.all[0] };
};

describe('tolzar widget cable', () => {
  it('builds the socket URL from the page', () => {
    expect(cableUrl('https://app.tolzar.com/widget?x=1')).toBe(
      'wss://app.tolzar.com/cable'
    );
    expect(cableUrl('http://localhost:3000/widget')).toBe(
      'ws://localhost:3000/cable'
    );
  });

  it('subscribes after welcome and passes channel events on', () => {
    const { events, ws } = start();
    ws.frame({ type: 'welcome' });
    expect(ws.sent[0]).toEqual({
      command: 'subscribe',
      identifier: JSON.stringify({
        channel: 'RoomChannel',
        pubsub_token: 'pub-1',
      }),
    });
    ws.frame({ type: 'confirm_subscription' });
    ws.frame({ type: 'ping', message: 1 });
    ws.frame({
      identifier: 'x',
      message: { event: 'message.created', data: { id: 7 } },
    });
    expect(events.map(e => e.event)).toEqual([
      'tz.connected',
      'message.created',
    ]);
  });

  it('reconnects with backoff when pings stop or the socket closes', () => {
    vi.useFakeTimers();
    const { cable, ws } = start();
    vi.advanceTimersByTime(PING_TIMEOUT + 1);
    expect(ws.closed).toBe(true);
    vi.advanceTimersByTime(1000);
    expect(FakeWS.all).toHaveLength(2);
    FakeWS.all[1].close();
    vi.advanceTimersByTime(1999);
    expect(FakeWS.all).toHaveLength(2);
    vi.advanceTimersByTime(1);
    expect(FakeWS.all).toHaveLength(3);
    cable.stop();
    vi.useRealTimers();
  });
});
