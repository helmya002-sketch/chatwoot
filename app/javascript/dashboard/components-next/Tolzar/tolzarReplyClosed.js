// Tolzar: the bar shown when no reply can go out on this conversation (owner, 31 Oct: "this message bar needs to fit
// the style of our design"). One clear sentence per channel saying why and what to do next, instead of the old
// split "You cannot reply due to / 24 hour message window restriction".
//   kind     meta | whatsapp | tiktok | api | other
//   returns  { key, params } for TOLZAR_INBOX.REPLY_CLOSED.<key>, or { text } for an API inbox's own message
export function closedNotice({
  kind,
  humanAgent = false,
  apiMessage = '',
  apiHours = null,
}) {
  switch (kind) {
    case 'meta':
      return { key: humanAgent ? 'META_7_DAYS' : 'META_24_HOURS', params: {} };
    case 'whatsapp':
      return { key: 'WHATSAPP', params: {} };
    case 'tiktok':
      return { key: 'TIKTOK', params: {} };
    case 'api':
      if (apiMessage) return { text: String(apiMessage) };
      return apiHours
        ? { key: 'API_HOURS', params: { hours: Number(apiHours) } }
        : { key: 'OTHER', params: {} };
    default:
      return { key: 'OTHER', params: {} };
  }
}
