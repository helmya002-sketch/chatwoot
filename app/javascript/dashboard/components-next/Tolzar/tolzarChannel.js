// Tolzar: the channel a contact really writes on. Mirror traffic (respond.io → Chatwoot) all
// lands in one API inbox, so the real source travels as `rio_channel_source` (on the contact
// and on each mirror conversation). Returns an inbox-like object for ChannelIcon.
const SOURCE_RULES = [
  [/whatsapp/, 'Channel::Whatsapp', 'WhatsApp'],
  [/instagram/, 'Channel::Instagram', 'Instagram'],
  [/facebook|messenger/, 'Channel::FacebookPage', 'Messenger'],
  [/tiktok/, 'Channel::Tiktok', 'TikTok'],
  [/telegram/, 'Channel::Telegram', 'Telegram'],
  [/line/, 'Channel::Line', 'LINE'],
  [/sms|twilio|viber/, 'Channel::Sms', 'SMS'],
  [/mail|gmail|outlook/, 'Channel::Email', 'Email'],
  [/web|site|widget|live_?chat/, 'Channel::WebWidget', 'Website chat'],
];

export const channelFromSource = source => {
  const s = String(source || '').toLowerCase();
  if (!s) return null;
  const hit = SOURCE_RULES.find(([re]) => re.test(s));
  return hit ? { channel_type: hit[1], name: hit[2] } : null;
};

// Contact (raw store record): the mirror's source channel first, else its last real inbox.
export const contactChannel = raw => {
  const fromSource = channelFromSource(
    raw?.additional_attributes?.rio_channel_source
  );
  if (fromSource) return fromSource;
  const list = raw?.contact_inboxes || [];
  return list.length ? list[list.length - 1].inbox : null;
};

// Conversation (API payload): the mirror's source channel first, else its inbox channel.
export const conversationChannel = conv =>
  channelFromSource(conv?.additional_attributes?.rio_channel_source) ||
  (conv?.meta?.channel ? { channel_type: conv.meta.channel, name: '' } : null);
