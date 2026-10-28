import { channelFromSource, contactChannel } from './tolzarChannel';
import { DEFAULT_STAGE, STAGES, stageOf } from './tolzarStages';

// Tolzar smoke tests (roadmap A2) for the helpers the Contacts and Inbox pages use.
describe('tolzarChannel', () => {
  it('maps respond.io sources to a channel', () => {
    expect(channelFromSource('whatsapp_business').name).toBe('WhatsApp');
    expect(channelFromSource('other_email').name).toBe('Email');
    expect(channelFromSource('instagram').name).toBe('Instagram');
    expect(channelFromSource('')).toBeNull();
  });

  it('prefers the mirror source over the inbox', () => {
    const raw = {
      additional_attributes: { rio_channel_source: 'facebook' },
      contact_inboxes: [{ inbox: { channel_type: 'Channel::Api', name: 'Mirror' } }],
    };
    expect(contactChannel(raw).name).toBe('Messenger');
  });
});

describe('tolzarStages', () => {
  it('has a default stage among the stages and resolves unknown keys', () => {
    expect(STAGES.map(s => s.key)).toContain(DEFAULT_STAGE);
    expect(stageOf('no such stage')).toBeTruthy();
  });
});
