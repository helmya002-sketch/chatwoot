<script setup>
import { ref, computed, onMounted, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { useLocale } from 'shared/composables/useLocale';
import ShadowBadge from '../ShadowBadge.vue';
import BrainNotice from './BrainNotice.vue';
import { BTN, BTN_GHOST, INPUT, LABEL } from './tzClasses';
import { fmtClock } from '../tolzarTime';

// Settings hub → Channels → Meta app (Owner): the workspace's OWN Meta app for Facebook Messenger,
// Instagram DMs and comments (TolzarController#meta_app*). The app secret is write-only; the verify
// token is shown once, when the app is first saved. Pages connect listen-only: Tolzar receives, staff
// keep answering in Meta Business Suite, nothing is sent from Tolzar.
const { t } = useI18n();
const { resolvedLocale } = useLocale();
const store = useStore();
const accountId = useMapGetter('getCurrentAccountId');
const url = computed(() => `/api/v1/accounts/${accountId.value}/tolzar/meta_app`);

const view = ref(null);
const pages = ref([]);
const form = ref({ app_id: '', app_secret: '' });
const page = ref({ page_id: '', access_token: '', inbox_name: '' });
// The verify token, shown once right after the app is first saved; removed from the page when the
// Owner says it is copied, after 5 minutes, or when the panel closes.
const verifyToken = ref('');
let tokenTimer = null;
function hideToken() {
  verifyToken.value = '';
  clearTimeout(tokenTimer);
}
onBeforeUnmount(hideToken);
const result = ref(null);
const saved = ref('');
const busy = ref(false);

const fail = e => e?.response?.data || { ok: false, error: 'brain_unreachable' };

// App Review test send: a 60-minute window for ONE message to the Owner's own account.
const testOpenUntil = ref('');
const test = ref({ conversation_id: '', text: '', confirm_name: '', instagram_username: '' });
const showUntil = iso => fmtClock(iso, resolvedLocale.value);

async function load() {
  try {
    const { data } = await window.axios.get(url.value);
    view.value = data.app || null;
    pages.value = data.pages || [];
    form.value.app_id = data.app?.app_id || '';
    testOpenUntil.value = showUntil(data.test_open_until);
  } catch (e) {
    result.value = fail(e);
  }
}

async function run(fn, okText) {
  busy.value = true;
  saved.value = '';
  result.value = null;
  try {
    const data = await fn();
    result.value = data;
    saved.value = okText;
    return data;
  } catch (e) {
    result.value = fail(e);
    return null;
  } finally {
    busy.value = false;
  }
}

async function saveApp() {
  const data = await run(
    () => window.axios.post(url.value, form.value).then(r => r.data),
    t('TOLZAR_META_APP.SAVED')
  );
  if (!data) return;
  form.value.app_secret = '';
  if (data.verify_token) {
    verifyToken.value = data.verify_token;
    // Off the page after 5 minutes at most; it is never fetched again (the API returns it once).
    tokenTimer = setTimeout(hideToken, 5 * 60 * 1000);
  }
  await load();
}

// A new verify token, set in Meta by Tolzar (nothing to copy or paste).
async function rotateToken() {
  await run(
    () => window.axios.post(`${url.value}/verify_token`).then(r => r.data),
    t('TOLZAR_META_APP.ROTATED')
  );
}

async function openTestWindow() {
  const data = await run(
    () => window.axios.post(`${url.value}/test_send/window`).then(r => r.data),
    ''
  );
  testOpenUntil.value = showUntil(data?.open_until);
}
async function closeTestWindow() {
  await run(
    () => window.axios.post(`${url.value}/test_send/window`, { close: true }).then(r => r.data),
    t('TOLZAR_META_APP.TEST.CLOSED')
  );
  testOpenUntil.value = '';
}
async function sendTest() {
  const data = await run(
    () => window.axios.post(`${url.value}/test_send`, test.value).then(r => r.data),
    t('TOLZAR_META_APP.TEST.SENT')
  );
  // The server says whether the window is still open: Meta's answer closes it, a failed check does not.
  if (data) test.value = { conversation_id: '', text: '', confirm_name: '', instagram_username: '' };
  await load();
}

async function connectPage() {
  const data = await run(
    () => window.axios.post(`${url.value}/pages`, page.value).then(r => r.data),
    t('TOLZAR_META_APP.CONNECTED')
  );
  if (!data) return;
  page.value = { page_id: '', access_token: '', inbox_name: '' };
  store.dispatch('inboxes/get').catch(() => {});
  await load();
}

onMounted(load);
</script>

<template>
  <div data-tz-meta-app>
    <ShadowBadge state="shadow" :hint="t('TOLZAR_META_APP.LISTEN_ONLY')" />
    <p class="mt-1 mb-0 text-xs text-n-slate-10">{{ t('TOLZAR_SETTINGS_UI.SHADOW_DETAIL.meta_app') }}</p>
    <p class="mt-2 text-[13px] text-n-slate-11">{{ t('TOLZAR_META_APP.INTRO') }}</p>

    <h3 class="mt-4 mb-0 text-[14px] font-semibold text-n-slate-12">{{ t('TOLZAR_META_APP.APP') }}</h3>
    <label :class="LABEL">{{ t('TOLZAR_META_APP.APP_ID') }}</label>
    <input v-model="form.app_id" :class="INPUT" inputmode="numeric" autocomplete="off" />
    <label :class="LABEL">{{ t('TOLZAR_META_APP.APP_SECRET') }}</label>
    <input
      v-model="form.app_secret"
      :class="INPUT"
      type="password"
      autocomplete="new-password"
      :placeholder="view ? t('TOLZAR_META_APP.SECRET_SAVED', { last4: view.secret_last4 }) : ''"
    />
    <button type="button" :class="BTN" :disabled="busy || !form.app_id" @click="saveApp">
      {{ t('TOLZAR_META_APP.SAVE') }}
    </button>

    <div v-if="view" class="p-3 mt-3 text-[13px] rounded-lg bg-n-alpha-1">
      <div>{{ t('TOLZAR_META_APP.WEBHOOK_URL') }}</div>
      <code class="block mt-1 break-all">{{ view.webhook_url }}</code>
      <button type="button" :class="BTN_GHOST" class="!mt-2 !h-7" :disabled="busy" @click="rotateToken">
        {{ t('TOLZAR_META_APP.ROTATE') }}
      </button>
      <div v-if="verifyToken" class="mt-2">
        {{ t('TOLZAR_META_APP.VERIFY_TOKEN') }}
        <code class="block mt-1 break-all">{{ verifyToken }}</code>
        <span class="text-xs text-n-amber-11">{{ t('TOLZAR_META_APP.VERIFY_ONCE') }}</span>
        <button type="button" :class="BTN_GHOST" class="ml-2 !mt-1 !h-7" @click="hideToken">
          {{ t('TOLZAR_META_APP.VERIFY_DONE') }}
        </button>
      </div>
    </div>

    <template v-if="view">
      <h3 class="mt-5 mb-0 text-[14px] font-semibold text-n-slate-12">{{ t('TOLZAR_META_APP.PAGES') }}</h3>
      <ul v-if="pages.length" class="pl-4 mt-1 text-[13px]">
        <li v-for="p in pages" :key="p.page_id">
          {{ p.name }} · {{ p.page_id }}<span v-if="p.instagram_id"> · {{ t('TOLZAR_SETTINGS_UI.CONNECTIONS.INSTAGRAM', { name: p.instagram_id }) }}</span>
        </li>
      </ul>
      <p v-else class="mt-1 text-xs text-n-slate-10">{{ t('TOLZAR_META_APP.NO_PAGES') }}</p>
      <label :class="LABEL">{{ t('TOLZAR_META_APP.PAGE_ID') }}</label>
      <input v-model="page.page_id" :class="INPUT" inputmode="numeric" autocomplete="off" />
      <label :class="LABEL">{{ t('TOLZAR_META_APP.TOKEN') }}</label>
      <input v-model="page.access_token" :class="INPUT" type="password" autocomplete="new-password" />
      <label :class="LABEL">{{ t('TOLZAR_META_APP.INBOX_NAME') }}</label>
      <input v-model="page.inbox_name" :class="INPUT" />
      <button
        type="button"
        :class="BTN"
        :disabled="busy || !page.page_id || !page.access_token"
        @click="connectPage"
      >
        {{ t('TOLZAR_META_APP.CONNECT') }}
      </button>
      <button type="button" :class="BTN_GHOST" class="ms-2" :disabled="busy" @click="load">
        {{ t('TOLZAR_META_APP.RELOAD') }}
      </button>

      <!-- App Review: one test message to the Owner's own account (Tolzar::MetaTestSend) -->
      <details v-if="pages.length" class="p-3 mt-5 rounded-lg border border-n-weak">
        <summary class="cursor-pointer text-[13px] font-semibold text-n-slate-12">{{ t('TOLZAR_META_APP.TEST.TITLE') }}</summary>
        <p class="mt-2 text-xs text-n-slate-11">{{ t('TOLZAR_META_APP.TEST.HINT') }}</p>
        <button v-if="!testOpenUntil" type="button" :class="BTN_GHOST" :disabled="busy" @click="openTestWindow">
          {{ t('TOLZAR_META_APP.TEST.OPEN') }}
        </button>
        <template v-else>
          <p class="text-xs text-n-amber-11">{{ t('TOLZAR_META_APP.TEST.OPEN_UNTIL', { at: testOpenUntil }) }}</p>
          <label :class="LABEL">{{ t('TOLZAR_META_APP.TEST.CONVERSATION') }}</label>
          <input v-model="test.conversation_id" :class="INPUT" inputmode="numeric" />
          <label :class="LABEL">{{ t('TOLZAR_META_APP.TEST.TEXT') }}</label>
          <input v-model="test.text" :class="INPUT" maxlength="300" />
          <label :class="LABEL">{{ t('TOLZAR_META_APP.TEST.CONFIRM') }}</label>
          <input v-model="test.confirm_name" :class="INPUT" autocomplete="off" />
          <label :class="LABEL">{{ t('TOLZAR_META_APP.TEST.INSTAGRAM') }}</label>
          <input v-model="test.instagram_username" :class="INPUT" autocomplete="off" />
          <button type="button" :class="BTN" :disabled="busy || !test.conversation_id || !test.text || !test.confirm_name" @click="sendTest">
            {{ t('TOLZAR_META_APP.TEST.SEND') }}
          </button>
          <button type="button" :class="BTN_GHOST" class="ml-2" :disabled="busy" @click="closeTestWindow">
            {{ t('TOLZAR_META_APP.TEST.CLOSE') }}
          </button>
        </template>
      </details>
    </template>
    <BrainNotice :result="result" :saved="saved" />
  </div>
</template>
