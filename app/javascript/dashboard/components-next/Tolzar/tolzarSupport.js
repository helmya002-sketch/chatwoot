// Tolzar: "Contact Tolzar" in the profile menu (readiness gap G). Opens Tolzar's own website chat (the
// widget of Tolzar's sales & support inbox, CHATWOOT_INBOX_TOKEN in Super Admin > Settings) for the person
// who is signed in, with their name and e-mail, so the Tolzar team knows who is asking. The widget script
// is loaded only on the first click; nothing is loaded for anyone who never opens it.
let loading = null;

const sdk = () => window.$tolzar || window.$chatwoot;

const load = (baseUrl, websiteToken, locale) => {
  if (loading) return loading;
  loading = new Promise((resolve, reject) => {
    window.tolzarSettings = { hideMessageBubble: true, locale: locale || 'en' };
    const script = document.createElement('script');
    script.src = `${baseUrl}/packs/js/sdk.js`;
    script.async = true;
    script.onload = () => {
      window.tolzarSDK.run({ websiteToken, baseUrl });
      window.addEventListener('chatwoot:ready', () => resolve(sdk()), {
        once: true,
      });
    };
    script.onerror = () => {
      loading = null;
      reject(new Error('support widget unavailable'));
    };
    document.body.appendChild(script);
  });
  return loading;
};

export const openTolzarSupport = async ({
  baseUrl,
  websiteToken,
  user,
  locale,
}) => {
  const widget = await load(baseUrl, websiteToken, locale);
  if (user && user.email) {
    widget.setUser(`tolzar-user-${user.id}`, {
      name: user.name,
      email: user.email,
    });
  }
  widget.toggle('open');
};
