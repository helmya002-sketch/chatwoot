/*! Tolzar website chat loader. Plain JavaScript, no dependencies, no third-party requests.
 * <script src="https://app.tolzar.com/tz/widget.js" defer></script>
 * <script>window.addEventListener('load',function(){tolzar.run({websiteToken:'…',baseUrl:'https://app.tolzar.com'})})</script>
 * Compatible with existing snippets: window.chatwootSDK.run(...), window.$chatwoot.* and the chatwoot:* events.
 * It draws the launcher, creates the chat iframe only when needed (first open, or a returning visitor), and talks to
 * it with postMessage, accepting messages only from that iframe and its origin. */
(function () {
  'use strict';
  if (window.tolzar && window.tolzar.__loaded) return;

  var PREFIX = 'chattz-widget:';
  var COOKIE = 'cw_conversation';
  var state = { baseUrl: '', websiteToken: '', origin: '', iframe: null, holder: null, bubble: null, open: false,
    ready: false, queue: [], color: '#3E63DD', position: 'right', locale: '', user: null, unread: 0 };

  function readCookie(name) {
    var m = document.cookie.match(new RegExp('(?:^|; )' + name + '=([^;]*)'));
    return m ? decodeURIComponent(m[1]) : '';
  }

  function writeCookie(name, value) {
    var secure = location.protocol === 'https:' ? '; Secure' : '';
    document.cookie = name + '=' + encodeURIComponent(value) + '; Path=/; Max-Age=' + 60 * 60 * 24 * 365 + '; SameSite=Lax' + secure;
  }

  function emit(name, data) {
    try {
      window.dispatchEvent(new CustomEvent(name, { detail: data }));
      if (name.indexOf('chatwoot:') === 0) window.dispatchEvent(new CustomEvent('tolzar:' + name.slice(9), { detail: data }));
    } catch (e) { /* old browsers: no events */ }
  }

  function send(event, payload) {
    var msg = PREFIX + JSON.stringify(Object.assign({ event: event }, payload || {}));
    if (state.ready && state.iframe) state.iframe.contentWindow.postMessage(msg, state.origin);
    else state.queue.push(msg);
  }

  function css() {
    if (document.getElementById('tz-loader-css')) return;
    var s = document.createElement('style');
    s.id = 'tz-loader-css';
    s.textContent = '.tz-l-bubble{position:fixed;bottom:20px;z-index:2147483000;width:56px;height:56px;border-radius:50%;border:0;' +
      'cursor:pointer;box-shadow:0 12px 30px -10px rgba(30,50,120,.5);color:#fff;display:flex;align-items:center;justify-content:center}' +
      '.tz-l-bubble:focus-visible{outline:3px solid #0f172a;outline-offset:3px}' +
      '.tz-l-dot{position:absolute;top:4px;right:4px;width:12px;height:12px;border-radius:50%;background:#d1363b;border:2px solid #fff;display:none}' +
      '.tz-l-unread .tz-l-dot{display:block}' +
      '.tz-l-holder{position:fixed;bottom:88px;z-index:2147483000;width:380px;height:min(640px,calc(100vh - 110px));border-radius:16px;' +
      'overflow:hidden;box-shadow:0 20px 50px -18px rgba(30,50,120,.4);display:none;background:#fff}' +
      '.tz-l-holder.tz-l-open{display:block}.tz-l-holder iframe{width:100%;height:100%;border:0}' +
      '@media (max-width:480px){.tz-l-holder{inset:0;width:100%;height:100%;border-radius:0;bottom:0}}' +
      '@media (prefers-reduced-motion:no-preference){.tz-l-bubble{transition:transform .15s}.tz-l-bubble:hover{transform:scale(1.05)}}';
    document.head.appendChild(s);
  }

  function side(el) {
    el.style[state.position === 'left' ? 'left' : 'right'] = '20px';
  }

  function bubble() {
    if (state.bubble) return;
    var b = document.createElement('button');
    b.type = 'button';
    b.className = 'tz-l-bubble';
    b.setAttribute('aria-label', 'Open chat');
    b.setAttribute('aria-expanded', 'false');
    b.style.background = state.color;
    b.innerHTML = '<svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">' +
      '<path d="M21 12a8 8 0 0 1-11.6 7.1L4 20l1-4.4A8 8 0 1 1 21 12z"/></svg><span class="tz-l-dot"></span>';
    b.addEventListener('click', function () { toggle(); });
    side(b);
    document.body.appendChild(b);
    state.bubble = b;
  }

  function frame() {
    if (state.iframe) return;
    var holder = document.createElement('div');
    holder.className = 'tz-l-holder';
    side(holder);
    var f = document.createElement('iframe');
    var url = state.baseUrl + '/widget?website_token=' + encodeURIComponent(state.websiteToken);
    var token = readCookie(COOKIE);
    if (token) url += '&cw_conversation=' + encodeURIComponent(token);
    f.src = url;
    f.title = 'Chat';
    f.setAttribute('allow', 'clipboard-write');
    holder.appendChild(f);
    document.body.appendChild(holder);
    state.iframe = f;
    state.holder = holder;
  }

  function toggle(force) {
    var open = typeof force === 'boolean' ? force : !state.open;
    frame();
    state.open = open;
    state.holder.className = 'tz-l-holder' + (open ? ' tz-l-open' : '');
    if (state.bubble) {
      state.bubble.setAttribute('aria-expanded', String(open));
      state.bubble.setAttribute('aria-label', open ? 'Close chat' : 'Open chat');
      if (open) state.bubble.className = 'tz-l-bubble';
    }
    send('toggle-open', { isOpen: open });
    send('toggle-close-button', { isMobile: window.innerWidth <= 480 });
  }

  // Messages from the chat iframe: only from our iframe window and our origin.
  var handlers = {
    loaded: function (m) {
      if (m.config && m.config.authToken) writeCookie(COOKIE, m.config.authToken);
      if (m.config && m.config.channelConfig && m.config.channelConfig.widgetColor) {
        state.color = m.config.channelConfig.widgetColor;
        if (state.bubble) state.bubble.style.background = state.color;
      }
      state.ready = true;
      var q = state.queue; state.queue = [];
      q.forEach(function (msg) { state.iframe.contentWindow.postMessage(msg, state.origin); });
      send('config-set', { locale: state.locale, position: state.position });
      if (state.user) send('set-user', state.user);
      emit('chatwoot:ready', {});
    },
    setAuthCookie: function (m) { if (m.data && m.data.widgetAuthToken) writeCookie(COOKIE, m.data.widgetAuthToken); },
    closeWindow: function () { toggle(false); if (state.bubble) state.bubble.focus(); },
    setUnreadMode: function () { if (!state.open && state.bubble) state.bubble.className = 'tz-l-bubble tz-l-unread'; },
    resetUnreadMode: function () { if (state.bubble) state.bubble.className = 'tz-l-bubble'; },
    handleNotificationDot: function (m) {
      state.unread = Number(m.unreadMessageCount) || 0;
      if (state.bubble) state.bubble.className = 'tz-l-bubble' + (state.unread && !state.open ? ' tz-l-unread' : '');
    },
    onEvent: function (m) { if (m.eventIdentifier) emit(m.eventIdentifier, m.data); },
    error: function (m) { emit('chatwoot:error', m.data); },
    playAudio: function () {}
  };

  window.addEventListener('message', function (e) {
    if (!state.iframe || e.source !== state.iframe.contentWindow || e.origin !== state.origin) return;
    if (typeof e.data !== 'string' || e.data.indexOf(PREFIX) !== 0) return;
    var m;
    try { m = JSON.parse(e.data.slice(PREFIX.length)); } catch (err) { return; }
    if (m && typeof handlers[m.event] === 'function') handlers[m.event](m);
  });

  function run(opts) {
    opts = opts || {};
    if (!opts.websiteToken || !opts.baseUrl) return;
    var base = String(opts.baseUrl).replace(/\/+$/, '');
    try { state.origin = new URL(base).origin; } catch (e) { return; }
    state.baseUrl = base;
    state.websiteToken = String(opts.websiteToken);
    var s = window.chatwootSettings || window.tolzarSettings || {};
    state.position = (opts.position || s.position) === 'left' ? 'left' : 'right';
    state.locale = opts.locale || s.locale || document.documentElement.lang || '';
    css();
    if (!s.hideMessageBubble) bubble();
    if (readCookie(COOKIE)) frame(); // a returning visitor: load quietly so new replies show the unread dot
  }

  var api = {
    __loaded: true,
    run: run,
    toggle: function (s) { toggle(s === 'open' ? true : s === 'close' ? false : undefined); },
    setUser: function (identifier, user) { state.user = { identifier: identifier, user: user || {} }; send('set-user', state.user); },
    setCustomAttributes: function (attrs) { send('set-custom-attributes', { customAttributes: attrs || {} }); },
    deleteCustomAttribute: function (key) { send('delete-custom-attribute', { customAttribute: key }); },
    setConversationCustomAttributes: function (attrs) { send('set-conversation-custom-attributes', { customAttributes: attrs || {} }); },
    deleteConversationCustomAttribute: function (key) { send('delete-conversation-custom-attribute', { customAttribute: key }); },
    setLabel: function (label) { send('set-label', { label: label }); },
    removeLabel: function (label) { send('remove-label', { label: label }); },
    setLocale: function (locale) { state.locale = locale; send('set-locale', { locale: locale }); },
    setColorScheme: function (mode) { send('set-color-scheme', { darkMode: mode }); },
    reset: function () {
      document.cookie = COOKIE + '=; Path=/; Max-Age=0';
      if (state.holder) state.holder.parentNode.removeChild(state.holder);
      state.iframe = null; state.holder = null; state.ready = false; state.open = false; state.user = null;
    },
    popoutChatWindow: function () { toggle(true); }
  };

  window.tolzar = api;
  if (!window.$chatwoot) window.$chatwoot = api;
  if (!window.chatwootSDK) window.chatwootSDK = { run: run };
})();
