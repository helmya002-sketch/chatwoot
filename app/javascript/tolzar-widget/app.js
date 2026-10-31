/* eslint-disable @intlify/vue-i18n/no-dynamic-keys -- t() here is our own widget i18n, not vue-i18n */
// Tolzar widget app (inside the iframe). Plain DOM, no framework: header, message list, composer. It loads the
// conversation, sends messages, follows the live channel, and speaks the loader's message contract.
import { Api } from './api';
import { Bridge } from './bridge';
import { Cable, cableUrl } from './cable';
import { formatMessage } from './format';
import { createStore, upsert, markFailed, countUnread, TYPE } from './store';
import { t, direction } from './i18n';
import {
  awayNode,
  attachmentNodes,
  attachButton,
  fileTooBig,
  prechatNeeded,
  renderPrechat,
} from './extras';
import { pickCampaign, armCampaign, csatNode, transcriptNode } from './engage';
import { sourcesNode, pageContext } from './context';
import { isOpen as inHours } from './hours';

const el = (doc, tag, cls, text) => {
  const node = doc.createElement(tag);
  if (cls) node.className = cls;
  if (text != null) node.textContent = text;
  return node;
};

export class WidgetApp {
  constructor({ config, root, doc = document, win = window, api, cable } = {}) {
    this.config = config;
    this.channel = config.channel || {};
    this.root = root;
    this.doc = doc;
    this.win = win;
    this.locale = config.locale || this.channel.locale || 'en';
    this.store = createStore();
    this.open = false;
    this.seenAt = Date.now() / 1000;
    this.api =
      api ||
      new Api({
        websiteToken: this.channel.websiteToken,
        authToken: config.authToken,
        locale: this.locale,
      });
    this.cable =
      cable ||
      new Cable({
        url: cableUrl(win.location.href),
        pubsubToken: config.pubsubToken,
        onEvent: msg => this.onLive(msg),
      });
    this.bridge = new Bridge({ win, handlers: this.loaderHandlers() });
    this.typingTimer = null;
  }

  async start() {
    this.render();
    this.bridge.start();
    this.cable.start();
    this.bridge.send('loaded', {
      config: {
        authToken: this.config.authToken,
        channelConfig: { widgetColor: this.channel.widgetColor },
      },
    });
    await this.load();
  }

  async load() {
    try {
      upsert(this.store, await this.api.messages());
      this.paint();
      this.maybePrechat();
    } catch {
      this.showError(t(this.locale, 'LOAD_FAILED'));
    }
  }

  // The inbox's pre-chat form, before the visitor's first message (extras.js).
  maybePrechat() {
    if (this.prechatDone || !prechatNeeded(this)) return;
    if (this.root.querySelector('.tz-prechat')) return;
    this.composer.hidden = true;
    this.list.after(renderPrechat(this));
  }

  // An ongoing campaign for the page the visitor is on (engage.js): its message shows after the wait and opens
  // the conversation for the team; the loader is told so it can show the unread bubble.
  async onPage(pageUrl) {
    if (this.cancelCampaign) this.cancelCampaign();
    this.pageUrl = pageUrl;
    if (!this.campaigns)
      this.campaigns = await this.api.campaigns().catch(() => []);
    const ch = this.channel;
    const campaign = pickCampaign(this.campaigns, {
      pageUrl,
      inOfficeHours: inHours({
        enabled: ch.workingHoursEnabled,
        hours: ch.workingHours,
        timeZone: ch.timezone,
      }),
      hasMessages: this.store.messages.length > 0,
    });
    this.cancelCampaign = armCampaign(campaign, c => this.fireCampaign(c), {
      set: (fn, ms) => this.win.setTimeout(fn, ms),
      clear: id => this.win.clearTimeout(id),
    });
  }

  async fireCampaign(campaign) {
    if (this.store.messages.length) return;
    try {
      await this.api.triggerCampaign(campaign.id, this.pageUrl);
      if (!this.open) this.bridge.send('setUnreadMode', {});
      await this.load();
      this.updateUnread();
    } catch {
      // A campaign that cannot start stays silent; the visitor can still write.
    }
  }

  async rate(message, rating) {
    try {
      await this.api.rate(message.id, rating);
      message.content_attributes = {
        ...(message.content_attributes || {}),
        submitted_values: { csat_survey_response: { rating } },
      };
      this.paint();
    } catch {
      this.showError(t(this.locale, 'FAILED'));
    }
  }

  // --- the loader's messages (the customer's page -> us) ---------------------------------------------------
  loaderHandlers() {
    return {
      'config-set': msg => this.applyConfig(msg),
      'toggle-open': ({ isOpen }) => this.setOpen(Boolean(isOpen)),
      'set-user': ({ identifier, user }) => this.setUser(identifier, user),
      'set-custom-attributes': ({ customAttributes }) =>
        this.api.setCustomAttributes(customAttributes).catch(() => {}),
      'delete-custom-attribute': ({ customAttribute }) =>
        this.api.deleteCustomAttribute(customAttribute).catch(() => {}),
      'set-conversation-custom-attributes': ({ customAttributes }) =>
        this.api.setConversationAttributes(customAttributes).catch(() => {}),
      'delete-conversation-custom-attribute': ({ customAttribute }) =>
        this.api.deleteConversationAttribute(customAttribute).catch(() => {}),
      'set-label': ({ label }) => this.api.addLabel(label).catch(() => {}),
      'remove-label': ({ label }) =>
        this.api.removeLabel(label).catch(() => {}),
      'set-locale': ({ locale }) => this.setLocale(locale),
      'set-color-scheme': ({ darkMode }) => this.setScheme(darkMode),
      'toggle-close-button': ({ isMobile }) =>
        this.root.classList.toggle('tz-mobile', Boolean(isMobile)),
      'change-url': ({ referrerURL }) => this.onPage(referrerURL),
      'push-event': () => {},
    };
  }

  applyConfig(msg) {
    if (msg.locale) this.setLocale(msg.locale);
    if (msg.darkMode) this.setScheme(msg.darkMode);
  }

  setOpen(isOpen) {
    this.open = isOpen;
    if (isOpen) {
      this.seenAt = Date.now() / 1000;
      this.api.seen();
      this.updateUnread();
      this.input?.focus();
    }
  }

  setLocale(locale) {
    if (!locale) return;
    this.locale = String(locale).replace('_', '-').split('-')[0];
    this.api.locale = this.locale;
    this.render();
    this.paint();
  }

  setScheme(mode) {
    this.root.dataset.scheme = ['light', 'dark', 'auto'].includes(mode)
      ? mode
      : 'auto';
  }

  async setUser(identifier, user = {}) {
    try {
      const out = await this.api.setUser(identifier, user);
      if (out.widget_auth_token) {
        this.api.authToken = out.widget_auth_token;
        this.bridge.send('setAuthCookie', {
          data: { widgetAuthToken: out.widget_auth_token },
        });
        await this.load();
      }
    } catch (e) {
      this.bridge.send('error', {
        errorType: 'SET_USER_ERROR',
        data: { status: e.status },
      });
    }
  }

  // --- live events (the server -> us) ----------------------------------------------------------------------
  onLive({ event, data }) {
    if (event === 'message.created' || event === 'message.updated') {
      upsert(this.store, [data]);
      this.paint();
      const fromTeam =
        Number(data.message_type) === TYPE.OUTGOING ||
        Number(data.message_type) === TYPE.TEMPLATE;
      if (event === 'message.created' && fromTeam) {
        this.bridge.send('onEvent', {
          eventIdentifier: 'chatwoot:on-message',
          data,
        });
        if (!this.open) {
          this.bridge.send('setUnreadMode', {});
          this.bridge.send('playAudio', {});
        }
        this.updateUnread();
      }
    } else if (
      event === 'conversation.typing_on' ||
      event === 'conversation.typing_off'
    ) {
      if (!data?.is_private) this.setTyping(event === 'conversation.typing_on');
    } else if (event === 'conversation.status_changed') {
      this.store.status = data?.status || this.store.status;
      this.paint();
    } else if (event === 'tz.connected') {
      this.load();
    }
  }

  updateUnread() {
    const unread = this.open ? 0 : countUnread(this.store, this.seenAt);
    this.store.unread = unread;
    this.bridge.send('handleNotificationDot', { unreadMessageCount: unread });
    if (!unread) this.bridge.send('resetUnreadMode', {});
  }

  setTyping(on) {
    this.store.typing = on;
    if (this.typingEl) this.typingEl.hidden = !on;
  }

  // --- sending ----------------------------------------------------------------------------------------------
  async send(text) {
    const content = text.trim();
    if (!content) return;
    const echoId = `tz-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 8)}`;
    upsert(this.store, [
      {
        echo_id: echoId,
        content,
        message_type: TYPE.INCOMING,
        created_at: Date.now() / 1000,
        pending: true,
      },
    ]);
    this.paint();
    try {
      const saved = await this.api.sendText(content, echoId);
      upsert(this.store, [{ ...saved, echo_id: echoId }]);
      this.tagPage();
    } catch {
      markFailed(this.store, echoId);
    }
    this.paint();
  }

  // Page-aware context (context.js): the page the visitor writes from, on the conversation, once per page.
  tagPage() {
    const ctx = pageContext(this.pageUrl);
    if (!ctx || this.taggedPage === ctx.tolzar_page) return;
    this.taggedPage = ctx.tolzar_page;
    this.api.setConversationAttributes(ctx).catch(() => {
      this.taggedPage = null;
    });
  }

  async sendFile(file) {
    if (fileTooBig(file, this.config.maxFileMb)) {
      this.showError(t(this.locale, 'TOO_BIG'));
      return;
    }
    this.showError('');
    const echoId = `tz-${Date.now().toString(36)}-f`;
    upsert(this.store, [
      {
        echo_id: echoId,
        content: file.name,
        message_type: TYPE.INCOMING,
        created_at: Date.now() / 1000,
        pending: true,
      },
    ]);
    this.paint();
    try {
      const saved = await this.api.sendFile(file, echoId);
      upsert(this.store, [{ ...saved, echo_id: echoId }]);
    } catch {
      markFailed(this.store, echoId);
    }
    this.paint();
  }

  onInput() {
    this.api.typing(true);
    this.win.clearTimeout(this.typingTimer);
    this.typingTimer = this.win.setTimeout(() => this.api.typing(false), 2000);
  }

  // --- rendering --------------------------------------------------------------------------------------------
  render() {
    const { doc } = this;
    this.root.textContent = '';
    this.root.dir = direction(this.locale);
    this.root.lang = this.locale;
    this.root.style.setProperty(
      '--tz-accent',
      this.channel.widgetColor || '#3E63DD'
    );

    const header = el(doc, 'header', 'tz-header');
    const title = el(
      doc,
      'div',
      'tz-title',
      this.channel.welcomeTitle || this.channel.websiteName || ''
    );
    const sub = el(
      doc,
      'div',
      'tz-sub',
      this.channel.welcomeTagline || t(this.locale, 'REPLY_TIME')
    );
    const close = el(doc, 'button', 'tz-close', '×');
    close.type = 'button';
    close.setAttribute('aria-label', t(this.locale, 'CLOSE'));
    close.addEventListener('click', () => this.bridge.send('closeWindow', {}));
    header.append(el(doc, 'div', 'tz-head-text'), close);
    header.firstChild.append(title, sub);

    this.list = el(doc, 'ol', 'tz-list');
    this.list.setAttribute('aria-live', 'polite');
    this.list.setAttribute('aria-label', t(this.locale, 'MESSAGES'));
    this.typingEl = el(doc, 'div', 'tz-typing', t(this.locale, 'TYPING'));
    this.typingEl.hidden = !this.store.typing;
    this.errorEl = el(doc, 'div', 'tz-error');
    this.errorEl.setAttribute('role', 'alert');
    this.errorEl.hidden = true;

    const form = el(doc, 'form', 'tz-composer');
    this.input = el(doc, 'textarea', 'tz-input');
    this.input.rows = 1;
    this.input.placeholder = t(this.locale, 'PLACEHOLDER');
    this.input.setAttribute('aria-label', t(this.locale, 'PLACEHOLDER'));
    this.input.maxLength = 10000;
    const sendBtn = el(doc, 'button', 'tz-send', t(this.locale, 'SEND'));
    sendBtn.type = 'submit';
    this.input.addEventListener('input', () => this.onInput());
    this.input.addEventListener('keydown', e => {
      if (e.key === 'Enter' && !e.shiftKey && !e.isComposing) {
        e.preventDefault();
        if (form.requestSubmit) form.requestSubmit();
        else form.dispatchEvent(new Event('submit', { cancelable: true }));
      }
    });
    form.addEventListener('submit', e => {
      e.preventDefault();
      const text = this.input.value;
      this.input.value = '';
      this.send(text);
    });
    const canAttach = this.channel.enabledFeatures?.attachments !== false;
    form.append(
      ...(canAttach ? [attachButton(this)] : []),
      this.input,
      sendBtn
    );
    this.composer = form;

    const away = awayNode(this);
    this.root.append(
      ...[header, away, this.list, this.typingEl, this.errorEl, form].filter(
        Boolean
      )
    );
  }

  paint() {
    const { doc } = this;
    if (!this.list) return;
    this.list.textContent = '';
    this.store.messages.forEach(m => {
      const mine = m.type === TYPE.INCOMING;
      let side = mine ? 'tz-mine' : 'tz-theirs';
      if (m.type === TYPE.ACTIVITY) side = 'tz-activity';
      const li = el(doc, 'li', `tz-msg ${side}`);
      if (!mine && m.sender?.name && m.type !== TYPE.ACTIVITY)
        li.append(el(doc, 'div', 'tz-sender', m.sender.name));
      const bubble = el(doc, 'div', 'tz-bubble');
      if (m.content && !(m.attachments.length && m.pending)) {
        bubble.append(formatMessage(m.content, doc));
      }
      bubble.append(...attachmentNodes(doc, m.attachments, this.locale));
      const src = sourcesNode(doc, m.content_attributes, this.locale);
      if (src) bubble.append(src);
      if (m.contentType === 'input_csat') bubble.append(csatNode(this, m));
      li.append(bubble);
      if (m.pending || m.failed)
        li.append(
          el(
            doc,
            'div',
            'tz-state',
            t(this.locale, m.failed ? 'FAILED' : 'SENDING')
          )
        );
      this.list.append(li);
    });
    if (this.store.status === 'resolved')
      this.list.append(
        el(doc, 'li', 'tz-msg tz-activity', t(this.locale, 'RESOLVED'))
      );
    if (
      this.store.status === 'resolved' &&
      this.channel.enabledFeatures?.email_transcript !== false
    ) {
      const li = el(doc, 'li', 'tz-msg tz-activity');
      li.append(transcriptNode(this));
      this.list.append(li);
    }
    this.list.scrollTop = this.list.scrollHeight;
  }

  showError(text) {
    if (!this.errorEl) return;
    this.errorEl.textContent = text;
    this.errorEl.hidden = !text;
  }
}
