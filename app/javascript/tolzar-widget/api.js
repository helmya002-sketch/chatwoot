// Tolzar widget: the widget API (/api/v1/widget/*) with the visitor's token (X-Auth-Token) and the
// website token. Same-origin only: the app runs on the widget's own host.

export class Api {
  constructor({ websiteToken, authToken, fetchImpl, locale } = {}) {
    this.websiteToken = websiteToken;
    this.authToken = authToken;
    this.fetch = fetchImpl || window.fetch.bind(window);
    this.locale = locale;
  }

  url(path, query = {}) {
    const params = new URLSearchParams({
      website_token: this.websiteToken,
      ...(this.locale ? { locale: this.locale } : {}),
      ...query,
    });
    return `/api/v1/widget/${path}?${params}`;
  }

  async request(method, path, { query, body } = {}) {
    const isForm = typeof FormData !== 'undefined' && body instanceof FormData;
    const res = await this.fetch(this.url(path, query), {
      method,
      credentials: 'same-origin',
      headers: {
        'X-Auth-Token': this.authToken,
        Accept: 'application/json',
        ...(body && !isForm ? { 'Content-Type': 'application/json' } : {}),
      },
      body: body && !isForm ? JSON.stringify(body) : body,
    });
    const data = await res.json().catch(() => ({}));
    if (!res.ok) {
      const err = new Error(`widget api ${res.status}`);
      err.status = res.status;
      err.data = data;
      throw err;
    }
    return data;
  }

  messages(before) {
    return this.request('GET', 'messages', {
      query: before ? { before } : {},
    }).then(d => d.payload || []);
  }

  conversation() {
    return this.request('GET', 'conversations').then(d => d || {});
  }

  sendText(content, echoId) {
    return this.request('POST', 'messages', {
      body: {
        message: {
          content,
          echo_id: echoId,
          timestamp: new Date().toString(),
          referer_url: document.referrer || '',
        },
      },
    });
  }

  // The pre-chat form's submit: creates the conversation with the visitor's details and first message.
  startConversation(body) {
    return this.request('POST', 'conversations', { body });
  }

  sendFile(file, echoId) {
    const form = new FormData();
    form.append('message[attachments][]', file, file.name);
    form.append('message[echo_id]', echoId);
    form.append('message[timestamp]', new Date().toString());
    form.append('message[referer_url]', document.referrer || '');
    return this.request('POST', 'messages', { body: form });
  }

  campaigns() {
    return this.request('GET', 'campaigns').then(d =>
      Array.isArray(d) ? d : []
    );
  }

  triggerCampaign(campaignId, pageUrl) {
    return this.request('POST', 'events', {
      body: {
        name: 'campaign.triggered',
        event_info: { campaign_id: campaignId, referer: pageUrl },
      },
    });
  }

  rate(messageId, rating, feedback = '') {
    return this.request('PATCH', `messages/${encodeURIComponent(messageId)}`, {
      body: {
        message: {
          submitted_values: {
            csat_survey_response: { rating, feedback_message: feedback },
          },
        },
      },
    });
  }

  transcript() {
    return this.request('POST', 'conversations/transcript');
  }

  typing(on) {
    return this.request('POST', 'conversations/toggle_typing', {
      body: { typing_status: on ? 'on' : 'off' },
    }).catch(() => {});
  }

  seen() {
    return this.request('POST', 'conversations/update_last_seen').catch(
      () => {}
    );
  }

  setUser(identifier, user) {
    return this.request('PATCH', 'contact/set_user', {
      body: { identifier, ...user },
    });
  }

  setCustomAttributes(customAttributes) {
    return this.request('PATCH', 'contact', {
      body: { custom_attributes: customAttributes },
    });
  }

  deleteCustomAttribute(key) {
    return this.request('POST', 'contact/destroy_custom_attributes', {
      body: { custom_attributes: [key] },
    });
  }

  setConversationAttributes(customAttributes) {
    return this.request('POST', 'conversations/set_custom_attributes', {
      body: { custom_attributes: customAttributes },
    });
  }

  deleteConversationAttribute(key) {
    return this.request('POST', 'conversations/destroy_custom_attributes', {
      body: { custom_attribute: [key] },
    });
  }

  addLabel(label) {
    return this.request('POST', 'labels', { body: { label } });
  }

  removeLabel(label) {
    return this.request('DELETE', `labels/${encodeURIComponent(label)}`);
  }
}
