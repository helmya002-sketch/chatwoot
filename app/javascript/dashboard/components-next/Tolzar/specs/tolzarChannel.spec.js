import {
  channelFromSource,
  contactChannel,
  conversationChannel,
} from '../tolzarChannel';

describe('tolzarChannel', () => {
  it.each([
    ['whatsapp_business', 'Channel::Whatsapp'],
    ['whatsapp', 'Channel::Whatsapp'],
    ['instagram', 'Channel::Instagram'],
    ['facebook', 'Channel::FacebookPage'],
    ['other_email', 'Channel::Email'],
    ['gmail', 'Channel::Email'],
    ['telegram', 'Channel::Telegram'],
    ['tiktok', 'Channel::Tiktok'],
    ['website_chat', 'Channel::WebWidget'],
  ])('maps respond.io source %s to %s', (source, type) => {
    expect(channelFromSource(source).channel_type).toBe(type);
  });

  it('returns null for unknown or empty sources', () => {
    expect(channelFromSource('old_channel')).toBeNull();
    expect(channelFromSource('')).toBeNull();
    expect(channelFromSource(undefined)).toBeNull();
  });

  it('prefers the mirror source over the shared API inbox for contacts', () => {
    const raw = {
      additional_attributes: { rio_channel_source: 'whatsapp_business' },
      contact_inboxes: [
        { inbox: { channel_type: 'Channel::Api', name: 'Mirror' } },
      ],
    };
    expect(contactChannel(raw)).toEqual({
      channel_type: 'Channel::Whatsapp',
      name: 'WhatsApp',
    });
  });

  it('falls back to the last inbox, or null', () => {
    const api = { channel_type: 'Channel::Api', name: 'Mirror' };
    expect(contactChannel({ contact_inboxes: [{ inbox: api }] })).toBe(api);
    expect(contactChannel({})).toBeNull();
  });

  it('reads the source on conversations, else the inbox channel', () => {
    expect(
      conversationChannel({
        additional_attributes: { rio_channel_source: 'other_email' },
        meta: { channel: 'Channel::Api' },
      }).channel_type
    ).toBe('Channel::Email');
    expect(
      conversationChannel({ meta: { channel: 'Channel::Api' } }).channel_type
    ).toBe('Channel::Api');
    expect(conversationChannel({})).toBeNull();
  });
});
