<script setup>
import {
  ref,
  reactive,
  computed,
  watch,
  watchEffect,
  onMounted,
  onBeforeUnmount,
} from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useLocale } from 'shared/composables/useLocale';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import ShadowBadge from 'dashboard/components-next/Tolzar/ShadowBadge.vue';
import BrainNotice from 'dashboard/components-next/Tolzar/settings/BrainNotice.vue';
import TrustPanel from 'dashboard/components-next/Tolzar/settings/TrustPanel.vue';
import ChannelsPanel from 'dashboard/components-next/Tolzar/settings/ChannelsPanel.vue';
import AiLimitsPanel from 'dashboard/components-next/Tolzar/settings/AiLimitsPanel.vue';
import QuotasPanel from 'dashboard/components-next/Tolzar/settings/QuotasPanel.vue';
import DocumentsPanel from 'dashboard/components-next/Tolzar/settings/DocumentsPanel.vue';
import WorkspacePanel from 'dashboard/components-next/Tolzar/settings/WorkspacePanel.vue';
import GoLivePanel from 'dashboard/components-next/Tolzar/settings/GoLivePanel.vue';
import PipelinePanel from 'dashboard/components-next/Tolzar/settings/PipelinePanel.vue';
import MetaAppPanel from 'dashboard/components-next/Tolzar/settings/MetaAppPanel.vue';
import WhatsappListenOnlyPanel from 'dashboard/components-next/Tolzar/settings/WhatsappListenOnlyPanel.vue';
import {
  BTN,
  BTN_GHOST,
  INPUT,
  LABEL,
  CHECK,
  TONE_WARN,
  TONE_OK,
} from 'dashboard/components-next/Tolzar/settings/tzClasses';
import { fmtAt } from 'dashboard/components-next/Tolzar/tolzarTime';
import { formatCount } from 'dashboard/components-next/Tolzar/tolzarUsage';
import {
  STAGES,
  applyPipelineStages,
} from 'dashboard/components-next/Tolzar/tolzarStages';
import {
  isSection,
  filterSections,
  EXPORT_POLL_MS,
  EXPORT_POLL_MAX,
  exportArrived,
  audienceFields,
  isStageField,
} from 'dashboard/components-next/Tolzar/tolzarSettingsHub';
import {
  MEDIA_MODES,
  VIDEO_FRAMES,
  getMedia,
  saveMedia as saveMediaConfig,
  mediaConfig,
} from 'dashboard/components-next/Tolzar/tolzarMedia';
import {
  brainErrors,
  isOwnerOnly,
} from 'dashboard/components-next/Tolzar/tolzarBrainApi';

// Tolzar Settings hub (approved mock settings-hub-v1): one home for what Tolzar does for this
// workspace. Every section reads/writes the brain through the admin proxy; AI features run in
// Shadow. Generic for any business.
const accountId = useMapGetter('getCurrentAccountId');
const getAccount = useMapGetter('accounts/getAccount');
const { t: $t } = useI18n();
const { resolvedLocale } = useLocale();
const route = useRoute();
const router = useRouter();
const base = computed(() => `/api/v1/accounts/${accountId.value}/tolzar`);
const get = (feature, params = {}) =>
  window.axios.get(`${base.value}/brain/${feature}`, { params }).then(r => r.data);
// A refusal (Owner-only, invalid, brain unreachable) comes back as its body, never as "Saved".
const failed = e => e?.response?.data || { ok: false, error: 'brain_unreachable' };
const post = (feature, body = {}) =>
  window.axios
    .post(`${base.value}/brain/${feature}`, body)
    .then(r => r.data)
    .catch(failed);
const problems = r =>
  isOwnerOnly(r) ? [$t('TOLZAR_SETTINGS.R1.OWNER_ONLY')] : brainErrors(r);

// The pipeline's stages follow the account setting (Settings → Pipeline), like every other page.
watchEffect(() =>
  applyPipelineStages(getAccount.value(accountId.value)?.settings)
);

const SECTIONS = [
  ['workspace', ['workspace_settings', 'pipeline', 'usage', 'roles', 'audit', 'export', 'go_live']],
  ['trust', ['disclosure', 'retention', 'privacy']],
  ['channels', ['whatsapp_listen', 'meta_app', 'sms', 'crm', 'commerce']],
  ['team', ['sla', 'qa']],
  ['ai', ['media', 'documents', 'recovery', 'learned', 'brief', 'ask', 'negotiation', 'agent_teams', 'tuning']],
  ['contacts', ['dedupe']],
  ['growth', ['links', 'broadcasts']],
  ['developers', ['connections', 'mcp']],
];
// Round 1 panels load their own data (one component per group).
const TRUST = ['disclosure', 'retention', 'privacy'];
const CHANNELS = ['sms', 'crm', 'commerce'];
const AI_LIMITS = ['negotiation', 'agent_teams', 'tuning'];
const current = ref('usage');
const usageDays = ref(30);
const data = ref({});
const loading = ref(false);
const loadFailed = ref(false);
// One flag per action, so a double click never sends twice and each button shows its own state.
const busy = reactive({});
// What the brain said back for the open section (BrainNotice: refusal or "Saved").
const result = ref(null);
const saved = ref('');
const search = ref('');
const attributes = ref([]); // the workspace's custom attribute definitions (broadcast audience)

const sectionText = k =>
  `${$t(`TOLZAR_SETTINGS.NAV.${k}`)} ${$t(`TOLZAR_SETTINGS.HINT.${k}`)}`;
const visibleSections = computed(() =>
  filterSections(SECTIONS, search.value, sectionText)
);
const zone = () => {
  try {
    return Intl.DateTimeFormat().resolvedOptions().timeZone || 'UTC';
  } catch {
    return 'UTC';
  }
};
const at = iso => fmtAt(iso, resolvedLocale.value);
const count = v => formatCount(v, resolvedLocale.value);

const loadAttributes = () =>
  window.axios
    .get(`/api/v1/accounts/${accountId.value}/custom_attribute_definitions`)
    .then(r => (Array.isArray(r.data) ? r.data : r.data?.payload || []))
    .catch(() => []);

// Export: the job runs in the background; while it does, this page asks GET /export every 15 s
// (10 minutes at most) and stops as soon as a new file is listed. Leaving the section stops it.
let exportTimer = null;
let exportPolls = 0;
const exportPending = ref(false);
const exportTimedOut = ref(false);
function stopExportPoll() {
  clearTimeout(exportTimer);
  exportTimer = null;
  exportPending.value = false;
  exportTimedOut.value = false;
}

// A section's answer only lands if it is still the open section (a slower earlier one is dropped).
let openSeq = 0;
async function open(key, { push = true } = {}) {
  const section = isSection(SECTIONS, key) ? key : 'usage';
  openSeq += 1;
  const seq = openSeq;
  current.value = section;
  result.value = null;
  saved.value = '';
  loadFailed.value = false;
  loading.value = true;
  stopExportPoll();
  if (push && route.query.section !== section) {
    router.replace({ query: { ...route.query, section } });
  }
  let out = {};
  try {
    if (section === 'usage') out = await get('usage', { days: usageDays.value });
    if (section === 'audit') out = (await window.axios.get(`${base.value}/audit`)).data;
    if (section === 'export') out = (await window.axios.get(`${base.value}/export`)).data;
    if (section === 'sla') out = await get('sla');
    if (section === 'qa') out = await get('qa');
    if (section === 'media') {
      const m = await getMedia(accountId.value);
      out = { ...m, config: mediaConfig(m.config) };
    }
    if (section === 'recovery') out = await get('recovery');
    if (section === 'learned') out = await get('learned');
    if (section === 'brief') out = await get('brief');
    if (section === 'ask') out = { answer: null, question: '' };
    if (section === 'dedupe') out = await get('dedupe');
    if (section === 'links') {
      const [ch, at0] = await Promise.all([get('channels'), get('attribution')]);
      out = { channels: ch.channels || {}, refs: at0.refs || [], campaign: '', greeting: '', made: null };
    }
    if (section === 'broadcasts') {
      const [b, defs] = await Promise.all([get('broadcasts'), loadAttributes()]);
      attributes.value = defs;
      const first = audienceFields(defs)[0];
      out = {
        list: b.broadcasts || [],
        draft: { name: '', audience: { field: first ? first.key : '', value: '' }, text: { en: '' } },
        preview: null,
      };
    }
    if (section === 'mcp') out = { token: '' };
    if (section === 'connections') out = (await window.axios.get(`${base.value}/meta/status`)).data;
    if (section === 'roles') {
      const [members, r] = await Promise.all([
        window.axios.get(`/api/v1/accounts/${accountId.value}/agents`).then(x => x.data),
        get('roles'),
      ]);
      // H3: the account owner is always an Owner; other admins are Managers unless promoted.
      const table = r.roles || {};
      const ownerId = r.owner_user_id;
      out = {
        ownerId,
        members: (members || []).map(m => {
          let tolzar = 'agent';
          if (m.role === 'administrator') {
            tolzar = m.id === ownerId ? 'owner' : table[String(m.id)] || 'manager';
          }
          return { ...m, tolzar };
        }),
      };
    }
    if (seq === openSeq) data.value = out;
  } catch (e) {
    if (seq !== openSeq) return;
    loadFailed.value = true;
    result.value = failed(e);
  } finally {
    if (seq === openSeq) loading.value = false;
  }
}

// Shows the brain's refusal, else `msg`; true when the request went through.
const notice = (r, msg = $t('TOLZAR_UI.SAVED')) => {
  result.value = r;
  const why = problems(r);
  saved.value = why.length ? '' : msg;
  return !why.length;
};
// One in-flight request per action name; a thrown error becomes a notice, never a silent catch.
async function act(name, fn) {
  if (busy[name]) return;
  busy[name] = true;
  result.value = null;
  saved.value = '';
  try {
    await fn();
  } catch (e) {
    result.value = failed(e);
  } finally {
    busy[name] = false;
  }
}

const saveSla = () =>
  act('sla', async () => {
    const r = await post('sla', data.value.config);
    if (notice(r)) data.value = { ...data.value, ...r };
  });
const saveMedia = () =>
  act('media', async () => {
    notice(await saveMediaConfig(accountId.value, data.value.config));
  });
// Recovery touch days as typed ("1, 3, 7"): up to three day counts.
const touchDays = computed({
  get: () => (data.value.config?.touch_days || [1, 3, 7]).join(', '),
  set: v => {
    data.value.config.touch_days = String(v)
      .split(',')
      .map(x => parseInt(x, 10))
      .filter(n => Number.isFinite(n) && n >= 0)
      .slice(0, 3);
  },
});
const saveRecovery = () =>
  act('recovery', async () => {
    const r = await post('recovery', data.value.config);
    if (notice(r) && r.config) data.value.config = r.config;
  });

async function pollExport(before) {
  exportPolls += 1;
  try {
    const r = (await window.axios.get(`${base.value}/export`)).data;
    if (current.value !== 'export' || !exportPending.value) return;
    if (exportArrived(before, r.exports)) {
      data.value = r;
      exportPending.value = false;
      saved.value = $t('TOLZAR_SETTINGS_UI.EXPORT.READY');
      return;
    }
  } catch (e) {
    /* one failed poll is not the end: the next tick asks again */
  }
  if (!exportPending.value) return;
  if (exportPolls >= EXPORT_POLL_MAX) {
    exportPending.value = false;
    exportTimedOut.value = true;
    return;
  }
  exportTimer = setTimeout(() => pollExport(before), EXPORT_POLL_MS);
}
const startExport = () =>
  act('export', async () => {
    const before = data.value.exports || [];
    const r = await window.axios
      .post(`${base.value}/export`)
      .then(x => x.data)
      .catch(failed);
    if (!notice(r, $t('TOLZAR_SETTINGS_UI.EXPORT.PREPARING'))) return;
    exportPolls = 0;
    exportTimedOut.value = false;
    exportPending.value = true;
    exportTimer = setTimeout(() => pollExport(before), EXPORT_POLL_MS);
  });
const download = x =>
  act(`download:${x.token}`, async () => {
    // The API authenticates with headers, so fetch the file and hand it to the browser.
    try {
      const r = await window.axios.get(`${base.value}/export/download`, {
        params: { token: x.token },
        responseType: 'blob',
      });
      const a = document.createElement('a');
      a.href = URL.createObjectURL(r.data);
      a.download = x.filename || 'tolzar-export.tar.gz';
      a.click();
      URL.revokeObjectURL(a.href);
    } catch (e) {
      // A 404 means the link expired (7 days) or the token is unknown: say so, offer a new export.
      result.value = {
        ok: false,
        error: $t('TOLZAR_SETTINGS_UI.EXPORT.DOWNLOAD_FAILED'),
      };
    }
  });
onBeforeUnmount(stopExportPoll);

const refreshDedupe = () =>
  act('dedupe', async () => {
    const r = await post('dedupe_refresh');
    if (notice(r, '')) data.value = r;
  });
const saveChannels = () =>
  act('channels', async () => {
    notice(await post('channels', data.value.channels));
  });
const makeLinks = () =>
  act('links', async () => {
    const r = await post('links', { campaign: data.value.campaign, greeting: data.value.greeting });
    if (notice(r, '')) data.value.made = r;
  });

// Broadcast audience: a stage field takes one of the pipeline's stages; a list attribute its
// values; anything else is typed.
const fields = computed(() => audienceFields(attributes.value));
const fieldValues = computed(
  () =>
    fields.value.find(f => f.key === data.value.draft?.audience?.field)?.values || []
);
const resetAudienceValue = () => {
  if (data.value.draft) data.value.draft.audience.value = '';
};
const previewBroadcast = () =>
  act('broadcast_preview', async () => {
    const r = await post('broadcasts_preview', { broadcast: data.value.draft });
    if (notice(r, '')) data.value.preview = r;
  });
const saveBroadcast = () =>
  act('broadcast_save', async () => {
    const r = await post('broadcasts', { broadcast: data.value.draft });
    if (notice(r)) {
      await open('broadcasts');
      saved.value = $t('TOLZAR_UI.SAVED');
    }
  });
const runBroadcast = id =>
  act(`broadcast_run:${id}`, async () => {
    const r = await post('broadcasts_run', { id });
    notice(
      r,
      $t('TOLZAR_SETTINGS_UI.BROADCASTS.SHADOW_RUN', { n: r.run?.would_send ?? 0 })
    );
  });
const decide = (qt, status) =>
  act(`decide:${qt}`, async () => {
    const r = await post('learned_status', { question_type: qt, status });
    if (notice(r)) {
      await open('learned');
      saved.value = $t('TOLZAR_UI.SAVED');
    }
  });
const buildBrief = () =>
  act('brief', async () => {
    const r = await post('brief_build');
    if (notice(r, '')) data.value = r;
  });
const askInbox = () =>
  act('ask', async () => {
    const r = await post('ask', { question: data.value.question });
    if (notice(r, '')) data.value.answer = r;
  });
const setRole = m =>
  act(`role:${m.id}`, async () => {
    const r = await post('roles', { user_id: m.id, role: m.tolzar });
    if (problems(r).length) await open('roles'); // put the select back to what is stored
    notice(r);
  });
const metaConnect = () =>
  act('meta_connect', async () => {
    const r = (await window.axios.post(`${base.value}/meta/connect_url`)).data;
    if (r.url) window.location.href = r.url;
    else notice(r.ok === false ? r : { ok: false, error: r.error || 'error' });
  });
const metaSave = () =>
  act('meta_save', async () => {
    const r = (await window.axios.post(`${base.value}/meta/select`, { pages: data.value.pages })).data;
    data.value = r;
    notice(r, $t('TOLZAR_UI.SAVED'));
  });
const metaDisconnect = () =>
  act('meta_disconnect', async () => {
    const r = (await window.axios.post(`${base.value}/meta/disconnect`)).data;
    data.value = r;
    notice(r, $t('TOLZAR_SETTINGS_UI.CONNECTIONS.DISCONNECTED'));
  });
const newToken = (revoke = false) =>
  act(revoke ? 'mcp_revoke' : 'mcp_create', async () => {
    const r = await post('mcp_token', revoke ? { revoke: true } : {});
    // A refusal never shows an empty token box: check the answer first.
    if (!notice(r, $t(revoke ? 'TOLZAR_SETTINGS_UI.MCP.REVOKED' : 'TOLZAR_SETTINGS_UI.MCP.CREATED')))
      return;
    data.value.token = revoke ? '' : r.token || '';
  });
const maxY = rows => Math.max(1, ...(rows || []).map(r => r.y || 0));
const changesOf = e =>
  Array.isArray(e.changes) ? e.changes.slice(0, 3).join(' · ') : Object.keys(e.changes || {}).join(', ');

// ?section=<key> is the open section: links from the Getting started checklist, the back button
// and "copy link to this setting" all work through it.
watch(
  () => route.query.section,
  s => {
    if (isSection(SECTIONS, s) && s !== current.value) open(s, { push: false });
  }
);
onMounted(() => {
  const wanted = String(route.query.section || '');
  open(isSection(SECTIONS, wanted) ? wanted : 'usage');
});
</script>

<template>
  <div class="overflow-auto flex-1 bg-n-background" data-tz-build="settings-hub-2">
    <div class="mx-auto max-w-[1180px] px-5 pb-16 pt-7 md:px-6">
      <div class="flex flex-wrap gap-3 justify-between items-center">
        <h1 class="m-0 text-[22px] font-extrabold tracking-tight text-n-slate-12">{{ $t('TOLZAR_SETTINGS.TITLE') }}</h1>
        <router-link :to="{ name: 'tolzar_onboarding' }" :class="BTN" class="!mt-0 no-underline">{{ $t('TOLZAR_ONBOARDING.OPEN') }}</router-link>
      </div>
      <p class="mt-1 text-sm text-n-slate-11">{{ $t('TOLZAR_SETTINGS.LEAD') }}</p>

      <!-- under md: one select instead of 31 stacked buttons -->
      <div class="mt-4 md:hidden">
        <label :class="LABEL" class="!mt-0" for="tz-section-select">{{ $t('TOLZAR_SETTINGS_UI.NAV.SECTION') }}</label>
        <select id="tz-section-select" :class="INPUT" :value="current" @change="open($event.target.value)">
          <optgroup v-for="[group, keys] in SECTIONS" :key="group" :label="$t(`TOLZAR_SETTINGS.GROUP.${group}`)">
            <option v-for="k in keys" :key="k" :value="k">{{ $t(`TOLZAR_SETTINGS.NAV.${k}`) }}</option>
          </optgroup>
        </select>
      </div>

      <div class="grid gap-4 mt-5 md:grid-cols-[220px_minmax(0,1fr)] lg:grid-cols-[270px_minmax(0,1fr)]">
        <nav class="hidden p-1.5 rounded-xl border md:block bg-n-solid-1 border-n-weak h-fit" :aria-label="$t('TOLZAR_SETTINGS_UI.NAV.ARIA')">
          <input
            v-model="search"
            type="search"
            :class="INPUT"
            class="mb-1"
            :placeholder="$t('TOLZAR_SETTINGS_UI.NAV.SEARCH')"
            :aria-label="$t('TOLZAR_SETTINGS_UI.NAV.SEARCH')"
          />
          <template v-for="[group, keys] in visibleSections" :key="group">
            <div class="px-2.5 pt-2.5 pb-1 text-[11px] font-semibold uppercase tracking-wide text-n-slate-10">{{ $t(`TOLZAR_SETTINGS.GROUP.${group}`) }}</div>
            <button
              v-for="k in keys"
              :key="k"
              type="button"
              class="block px-2.5 py-2 w-full text-left rounded-lg text-[13.5px]"
              :class="current === k ? 'font-semibold text-n-brand bg-n-brand/10' : 'text-n-slate-11 hover:bg-n-alpha-1'"
              :aria-current="current === k ? 'page' : null"
              @click="open(k)"
            >
              <span class="block">{{ $t(`TOLZAR_SETTINGS.NAV.${k}`) }}</span>
              <span class="hidden lg:block mt-0.5 text-[11px] font-normal leading-snug text-n-slate-10 line-clamp-2">{{ $t(`TOLZAR_SETTINGS.HINT.${k}`) }}</span>
            </button>
          </template>
          <p v-if="!visibleSections.length" class="px-2.5 py-3 m-0 text-xs text-n-slate-10">{{ $t('TOLZAR_SETTINGS_UI.NAV.NO_MATCH') }}</p>
        </nav>

        <section class="p-5 rounded-xl border bg-n-solid-1 border-n-weak min-h-[300px]">
          <h2 class="mt-0 mb-1 text-[17px] font-bold text-n-slate-12">{{ $t(`TOLZAR_SETTINGS.NAV.${current}`) }}</h2>
          <p class="mt-0 mb-4 text-[13px] text-n-slate-10">{{ $t(`TOLZAR_SETTINGS.HINT.${current}`) }}</p>
          <BrainNotice :result="result" :saved="saved" />
          <div v-if="loading" class="flex gap-2 items-center my-3 text-[13px] text-n-slate-10" role="status">
            <Spinner :size="16" />
            <span>{{ $t('TOLZAR_UI.LOADING') }}</span>
          </div>
          <div v-if="loadFailed" class="my-3">
            <p class="m-0 text-[13px] text-n-slate-11">{{ $t('TOLZAR_UI.LOAD_FAILED') }}</p>
            <button type="button" :class="BTN_GHOST" @click="open(current)">{{ $t('TOLZAR_UI.RETRY') }}</button>
          </div>

          <!-- usage -->
          <div v-if="current === 'usage'" class="flex gap-1 mb-3">
            <button
              v-for="d in [7, 30, 90]"
              :key="d"
              type="button"
              class="px-2.5 py-1 text-xs rounded-full border"
              :class="usageDays === d ? 'border-n-brand bg-n-brand text-white' : 'border-n-weak text-n-slate-11'"
              :aria-pressed="usageDays === d"
              @click="usageDays = d; open('usage')"
            >
              {{ $t('TOLZAR_SETTINGS.USAGE.DAYS', { n: d }) }}
            </button>
          </div>
          <div v-if="current === 'usage' && data.total" class="grid grid-cols-2 gap-2 md:grid-cols-5">
            <div v-for="(v, k) in data.total" :key="k" class="p-3 rounded-lg bg-n-alpha-1">
              <div class="text-xl font-bold text-n-slate-12">{{ count(v) }}</div>
              <div class="text-xs text-n-slate-10">{{ $t(`TOLZAR_SETTINGS.USAGE.${k}`) }}</div>
            </div>
          </div>

          <QuotasPanel v-if="current === 'usage'" />
          <TrustPanel v-if="TRUST.includes(current)" :key="current" :section="current" />
          <ChannelsPanel v-if="CHANNELS.includes(current)" :key="current" :section="current" />
          <WhatsappListenOnlyPanel v-if="current === 'whatsapp_listen'" />
          <AiLimitsPanel v-if="AI_LIMITS.includes(current)" :key="current" :section="current" />
          <DocumentsPanel v-if="current === 'documents'" />
          <WorkspacePanel v-if="current === 'workspace_settings'" />
          <GoLivePanel v-if="current === 'go_live'" />
          <PipelinePanel v-if="current === 'pipeline'" />
          <MetaAppPanel v-if="current === 'meta_app'" />

          <template v-if="!loading && !loadFailed">
            <!-- roles -->
            <div v-if="current === 'roles'">
              <table class="w-full text-[13px]">
                <tbody>
                  <tr v-for="m in data.members || []" :key="m.id" class="border-t border-n-weak">
                    <td class="py-2">{{ m.name }}<div class="text-xs text-n-slate-10">{{ m.email }}</div></td>
                    <td class="w-[180px]">
                      <select
                        v-if="m.role === 'administrator'"
                        v-model="m.tolzar"
                        :class="INPUT"
                        :disabled="m.id === data.ownerId || busy[`role:${m.id}`]"
                        :aria-label="$t('TOLZAR_SETTINGS_UI.ROLES.ROLE_OF', { name: m.name })"
                        @change="setRole(m)"
                      >
                        <option value="owner">{{ $t('TOLZAR_SETTINGS.ROLES.owner') }}</option>
                        <option value="manager">{{ $t('TOLZAR_SETTINGS.ROLES.manager') }}</option>
                      </select>
                      <span v-else class="text-n-slate-11">{{ $t('TOLZAR_SETTINGS.ROLES.agent') }}</span>
                    </td>
                  </tr>
                </tbody>
              </table>
              <ul class="mt-4 text-xs text-n-slate-10"><li>{{ $t('TOLZAR_SETTINGS.ROLES.RULE_OWNER') }}</li><li>{{ $t('TOLZAR_SETTINGS.ROLES.RULE_MANAGER') }}</li><li>{{ $t('TOLZAR_SETTINGS.ROLES.RULE_AGENT') }}</li></ul>
            </div>

            <!-- audit -->
            <div v-if="current === 'audit'">
              <table class="w-full text-[13px]">
                <thead>
                  <tr class="text-left text-xs text-n-slate-10">
                    <th class="py-1 font-semibold">{{ $t('TOLZAR_SETTINGS_UI.AUDIT.WHEN') }}</th>
                    <th class="px-2 font-semibold">{{ $t('TOLZAR_SETTINGS_UI.AUDIT.WHO') }}</th>
                    <th class="px-2 font-semibold">{{ $t('TOLZAR_SETTINGS_UI.AUDIT.ACTION') }}</th>
                    <th class="font-semibold">{{ $t('TOLZAR_SETTINGS_UI.AUDIT.CHANGES') }}</th>
                  </tr>
                </thead>
                <tbody>
                  <tr v-for="(e, i) in data.entries || []" :key="i" class="border-t border-n-weak">
                    <td class="py-2 whitespace-nowrap text-n-slate-10">{{ at(e.at) }}</td>
                    <td class="px-2">{{ e.actor }}</td>
                    <td class="px-2 font-semibold">{{ e.action }}</td>
                    <td class="text-n-slate-11">{{ changesOf(e) }}</td>
                  </tr>
                </tbody>
              </table>
              <p v-if="!(data.entries || []).length" class="text-[13px] text-n-slate-10">{{ $t('TOLZAR_SETTINGS.NONE_YET') }}</p>
              <p class="mt-2 text-xs text-n-slate-10">{{ $t('TOLZAR_UI.YOUR_TIME_ZONE', { zone: zone() }) }}</p>
            </div>

            <!-- export -->
            <div v-if="current === 'export'">
              <button type="button" :class="BTN" :disabled="busy.export || exportPending" @click="startExport">
                {{ busy.export ? $t('TOLZAR_UI.SAVING') : $t('TOLZAR_SETTINGS.EXPORT.PREPARE') }}
              </button>
              <p v-if="exportPending" class="flex gap-2 items-center mt-2 text-xs text-n-slate-10" role="status">
                <Spinner :size="14" />
                <span>{{ $t('TOLZAR_SETTINGS_UI.EXPORT.POLLING') }}</span>
              </p>
              <p v-if="exportTimedOut" class="p-2 mt-2 text-xs rounded-lg" :class="TONE_WARN">{{ $t('TOLZAR_SETTINGS_UI.EXPORT.TIMED_OUT') }}</p>
              <table v-if="(data.exports || []).length" class="mt-4 w-full text-[13px]">
                <tbody>
                  <tr v-for="x in data.exports" :key="x.token" class="border-t border-n-weak">
                    <td class="py-2">{{ at(x.created_at) }}</td>
                    <td>{{ $t('TOLZAR_SETTINGS_UI.EXPORT.SIZE_MB', { n: (x.size / 1048576).toFixed(1) }) }}</td>
                    <td>
                      <button type="button" class="text-n-brand disabled:opacity-50" :disabled="busy[`download:${x.token}`]" @click="download(x)">
                        {{ busy[`download:${x.token}`] ? $t('TOLZAR_UI.LOADING') : $t('TOLZAR_SETTINGS.EXPORT.DOWNLOAD') }}
                      </button>
                    </td>
                  </tr>
                </tbody>
              </table>
              <p v-else class="mt-4 text-[13px] text-n-slate-10">{{ $t('TOLZAR_SETTINGS.NONE_YET') }}</p>
              <p class="mt-2 text-xs text-n-slate-10">{{ $t('TOLZAR_UI.YOUR_TIME_ZONE', { zone: zone() }) }}</p>
            </div>

            <!-- SLA -->
            <div v-if="current === 'sla' && data.config" class="max-w-[440px]">
              <label :class="CHECK" class="!mt-0">
                <input v-model="data.config.enabled" type="checkbox" class="accent-n-brand" />
                {{ $t('TOLZAR_SETTINGS_UI.ENABLED') }}
                <ShadowBadge state="shadow" :hint="$t('TOLZAR_SETTINGS_UI.SHADOW_DETAIL.sla')" />
              </label>
              <label :class="LABEL">{{ $t('TOLZAR_SETTINGS.SLA.MINUTES') }}</label>
              <input v-model.number="data.config.first_reply_minutes" type="number" min="1" :class="INPUT" />
              <label :class="CHECK"><input v-model="data.config.working_hours_only" type="checkbox" class="accent-n-brand" /> {{ $t('TOLZAR_SETTINGS.SLA.WORKING_HOURS') }}</label>
              <label :class="CHECK" class="!mt-2"><input v-model="data.config.mention_assignee" type="checkbox" class="accent-n-brand" /> {{ $t('TOLZAR_SETTINGS.SLA.MENTION') }}</label>
              <p class="text-xs text-n-slate-10">{{ $t('TOLZAR_SETTINGS.SLA.COUNTS', { late: (data.counts || {}).sla_breach || 0, ok: (data.counts || {}).sla_ok || 0 }) }}</p>
              <button type="button" :class="BTN" :disabled="busy.sla" @click="saveSla">{{ busy.sla ? $t('TOLZAR_UI.SAVING') : $t('TOLZAR_SETTINGS.SAVE') }}</button>
            </div>

            <!-- QA -->
            <div v-if="current === 'qa'">
              <div v-for="c in data.coaching || []" :key="c.who" class="p-3 mb-2 rounded-lg border border-n-weak">
                <div class="flex justify-between"><b>{{ c.who }}</b><span>{{ $t('TOLZAR_SETTINGS_UI.QA.SCORE_LINE', { score: c.score, n: c.conversations }) }}</span></div>
                <div v-if="(c.strengths || []).length" class="text-xs text-n-teal-11">{{ $t('TOLZAR_SETTINGS_UI.QA.STRENGTHS', { list: c.strengths.join(' · ') }) }}</div>
                <div v-if="(c.work_on || []).length" class="text-xs text-n-amber-11">{{ $t('TOLZAR_SETTINGS_UI.QA.WORK_ON', { list: c.work_on.join(' · ') }) }}</div>
              </div>
              <p v-if="!(data.coaching || []).length" class="text-n-slate-10">{{ $t('TOLZAR_SETTINGS.NONE_YET') }}</p>
              <h3 class="mt-4 text-sm font-semibold">{{ $t('TOLZAR_SETTINGS.QA.RUBRIC') }}</h3>
              <ul class="text-[13px] text-n-slate-11"><li v-for="r in data.rubric || []" :key="r.key">{{ $t('TOLZAR_SETTINGS_UI.QA.RUBRIC_ROW', { description: r.description, n: r.weight }) }}</li></ul>
            </div>

            <!-- media -->
            <div v-if="current === 'media' && data.config" class="max-w-[520px]">
              <label :class="LABEL">{{ $t('TOLZAR_SETTINGS.MEDIA.VOICE') }}</label>
              <select v-model="data.config.voice" :class="INPUT"><option v-for="m in MEDIA_MODES" :key="m" :value="m">{{ $t(`TOLZAR_SETTINGS.MODES.${m}`) }}</option></select>
              <label :class="LABEL">{{ $t('TOLZAR_SETTINGS.MEDIA.IMAGES') }}</label>
              <select v-model="data.config.images" :class="INPUT"><option v-for="m in MEDIA_MODES" :key="m" :value="m">{{ $t(`TOLZAR_SETTINGS.MODES.${m}`) }}</option></select>
              <label :class="LABEL">{{ $t('TOLZAR_SETTINGS.MEDIA.FIELDS') }}</label>
              <div v-for="(f, i) in data.config.image_fields || []" :key="i" class="flex gap-1 mb-1">
                <input v-model="f.key" :class="INPUT" class="!w-[140px]" :placeholder="$t('TOLZAR_SETTINGS_UI.MEDIA.FIELD_KEY_PLACEHOLDER')" :aria-label="$t('TOLZAR_SETTINGS_UI.MEDIA.FIELD_KEY')" />
                <input v-model="f.description" :class="INPUT" :placeholder="$t('TOLZAR_SETTINGS_UI.MEDIA.FIELD_DESC_PLACEHOLDER')" :aria-label="$t('TOLZAR_SETTINGS_UI.MEDIA.FIELD_DESC')" />
                <button type="button" class="px-1 text-n-slate-9 hover:text-n-ruby-11" :aria-label="$t('TOLZAR_SETTINGS_UI.MEDIA.REMOVE_FIELD')" @click="data.config.image_fields.splice(i, 1)">
                  <span class="i-lucide-x size-3.5" aria-hidden="true" />
                </button>
              </div>
              <button type="button" class="text-xs text-n-brand" @click="(data.config.image_fields = data.config.image_fields || []).push({ key: '', description: '' })">{{ $t('TOLZAR_SETTINGS_UI.MEDIA.ADD_FIELD') }}</button>
              <label :class="LABEL">{{ $t('TOLZAR_SETTINGS.MEDIA.VIDEO') }}</label>
              <select v-model="data.config.video" :class="INPUT"><option v-for="m in MEDIA_MODES" :key="m" :value="m">{{ $t(`TOLZAR_SETTINGS.MODES.${m}`) }}</option></select>
              <label :class="LABEL">{{ $t('TOLZAR_SETTINGS.MEDIA.VIDEO_FRAMES') }}</label>
              <input v-model.number="data.config.video_frames" type="number" :min="VIDEO_FRAMES.min" :max="VIDEO_FRAMES.max" :class="INPUT" class="!w-[100px]" />
              <p class="text-xs text-n-amber-11">{{ $t('TOLZAR_SETTINGS.MEDIA.VIDEO_NOTE') }}</p>
              <label :class="LABEL">{{ $t('TOLZAR_SETTINGS.MEDIA.RETENTION') }}</label>
              <input v-model.number="data.config.retention_days" type="number" min="1" :class="INPUT" />
              <p class="text-xs text-n-slate-10">{{ $t('TOLZAR_SETTINGS.MEDIA.PRIVACY') }}</p>
              <button type="button" :class="BTN" :disabled="busy.media" @click="saveMedia">{{ busy.media ? $t('TOLZAR_UI.SAVING') : $t('TOLZAR_SETTINGS.SAVE') }}</button>
            </div>

            <!-- recovery -->
            <div v-if="current === 'recovery' && data.config" class="max-w-[520px]">
              <label :class="CHECK" class="!mt-0">
                <input v-model="data.config.enabled" type="checkbox" class="accent-n-brand" />
                {{ $t('TOLZAR_SETTINGS_UI.ENABLED') }}
                <ShadowBadge state="shadow" :hint="$t('TOLZAR_SETTINGS_UI.SHADOW_DETAIL.recovery')" />
              </label>
              <label :class="LABEL">{{ $t('TOLZAR_SETTINGS.RECOVERY.QUIET') }}</label>
              <input v-model.number="data.config.quiet_hours" type="number" min="6" :class="INPUT" />
              <label :class="LABEL">{{ $t('TOLZAR_SETTINGS.RECOVERY.TOUCH_DAYS') }}</label>
              <input v-model="touchDays" :class="INPUT" :placeholder="$t('TOLZAR_SETTINGS_UI.RECOVERY.TOUCH_DAYS_PLACEHOLDER')" />
              <label :class="LABEL">{{ $t('TOLZAR_SETTINGS.RECOVERY.MAX_PER_RUN') }}</label>
              <input v-model.number="data.config.max_per_run" type="number" min="1" max="50" :class="INPUT" />
              <p class="text-xs text-n-slate-10">{{ $t('TOLZAR_SETTINGS.RECOVERY.PLANNED', { n: data.planned || 0 }) }}</p>
              <ul v-if="(data.recent || []).length" class="pl-4 mt-1 text-xs text-n-slate-11">
                <li v-for="(r, i) in data.recent.slice(0, 10)" :key="i">
                  {{ $t('TOLZAR_SETTINGS_UI.RECOVERY.PLAN_ROW', { at: at(r.planned_at), n: (r.touches || []).length, lang: r.language || '' }) }}
                </li>
              </ul>
              <p v-if="(data.recent || []).length" class="mt-1 text-xs text-n-slate-10">{{ $t('TOLZAR_UI.YOUR_TIME_ZONE', { zone: zone() }) }}</p>
              <button type="button" :class="BTN" :disabled="busy.recovery" @click="saveRecovery">{{ busy.recovery ? $t('TOLZAR_UI.SAVING') : $t('TOLZAR_SETTINGS.SAVE') }}</button>
            </div>

            <!-- learned -->
            <div v-if="current === 'learned'">
              <p class="mt-0 mb-2 text-xs text-n-slate-10">{{ $t('TOLZAR_SETTINGS.LEARNED.APPROVE_NOTE') }}</p>
              <div v-for="ty in data.types || []" :key="ty.question_type" class="p-3 mb-2 rounded-lg border border-n-weak">
                <div class="flex flex-wrap gap-2 justify-between items-center">
                  <b class="text-[13.5px]">{{ ty.question_type }}</b>
                  <span class="text-xs text-n-slate-10">{{ $t('TOLZAR_SETTINGS_UI.LEARNED.STATS', { n: ty.count, pct: Math.round(ty.consistency * 100), status: ty.status }) }}{{ ty.never_list_topic ? ` · ${ty.never_list_topic}` : '' }}</span>
                </div>
                <div v-if="(ty.examples || [])[0]" class="mt-1 text-xs text-n-slate-11">{{ $t('TOLZAR_SETTINGS_UI.QUOTED', { text: ty.examples[0].staff_answer }) }}</div>
                <div v-if="ty.status === 'proposed'" class="flex gap-2 mt-2">
                  <button type="button" :class="BTN" class="!h-7" :disabled="busy[`decide:${ty.question_type}`]" @click="decide(ty.question_type, 'shadow')">{{ $t('TOLZAR_SETTINGS.LEARNED.APPROVE') }}</button>
                  <button type="button" :class="BTN_GHOST" class="!h-7" :disabled="busy[`decide:${ty.question_type}`]" @click="decide(ty.question_type, 'rejected')">{{ $t('TOLZAR_SETTINGS.LEARNED.REJECT') }}</button>
                </div>
              </div>
              <p v-if="!(data.types || []).length" class="text-n-slate-10">{{ $t('TOLZAR_SETTINGS.NONE_YET') }}</p>
            </div>

            <!-- brief -->
            <div v-if="current === 'brief'">
              <button type="button" :class="BTN" :disabled="busy.brief" @click="buildBrief">{{ busy.brief ? $t('TOLZAR_UI.LOADING') : $t('TOLZAR_SETTINGS.BRIEF.BUILD') }}</button>
              <p v-if="data.brief && !data.brief.summary" class="mt-3 text-[13px] text-n-slate-10">
                {{ $t('TOLZAR_SETTINGS.BRIEF.EMPTY', { week: data.brief.week || '', n: (data.brief.stats && data.brief.stats.conversations) || 0 }) }}
              </p>
              <div v-if="data.brief && data.brief.summary" class="grid gap-3 mt-4 md:grid-cols-2">
                <div v-for="(items, k) in data.brief.summary" :key="k" class="p-3 rounded-lg bg-n-alpha-1">
                  <div class="text-xs font-semibold uppercase text-n-slate-10">{{ $t(`TOLZAR_SETTINGS.BRIEF.${k}`) }}</div>
                  <ul class="pl-4 my-1 text-[13px]"><li v-for="x in items" :key="x">{{ x }}</li></ul>
                </div>
              </div>
            </div>

            <!-- ask -->
            <div v-if="current === 'ask'">
              <div class="flex gap-2 items-end">
                <input v-model="data.question" :class="INPUT" :placeholder="$t('TOLZAR_SETTINGS.ASK.PLACEHOLDER')" :aria-label="$t('TOLZAR_SETTINGS.ASK.GO')" @keyup.enter="askInbox" />
                <button type="button" :class="BTN" class="!mt-0 shrink-0" :disabled="busy.ask" @click="askInbox">{{ busy.ask ? $t('TOLZAR_UI.LOADING') : $t('TOLZAR_SETTINGS.ASK.GO') }}</button>
              </div>
              <div v-if="data.answer && data.answer.rows" class="mt-4">
                <b>{{ data.answer.title }}</b>
                <div v-for="r in data.answer.rows" :key="r.x" class="flex gap-2 items-center mt-1.5 text-[13px]">
                  <span class="w-[160px] truncate text-n-slate-11">{{ r.x }}</span>
                  <span class="h-3 rounded bg-n-brand" :style="{ width: `${Math.max(2, (r.y / maxY(data.answer.rows)) * 60)}%` }" />
                  <span>{{ r.y }}</span>
                </div>
              </div>
            </div>

            <!-- dedupe -->
            <div v-if="current === 'dedupe'">
              <button type="button" :class="BTN" :disabled="busy.dedupe" @click="refreshDedupe">{{ busy.dedupe ? $t('TOLZAR_UI.LOADING') : $t('TOLZAR_SETTINGS.DEDUPE.REFRESH') }}</button>
              <p v-if="data.at && !(data.groups || []).length" class="mt-3 text-[13px] text-n-slate-10">{{ $t('TOLZAR_SETTINGS.DEDUPE.NONE') }}</p>
              <div v-for="(g, i) in (data.groups || []).slice(0, 50)" :key="i" class="flex flex-wrap gap-2 justify-between py-2 border-t border-n-weak text-[13px]">
                <span>{{ g.contacts.map(c => c.name || `#${c.id}`).join(' · ') }}</span>
                <span class="text-n-slate-10">{{ g.matched_on.join(', ') }}</span>
                <router-link :to="`/app/accounts/${accountId}/contacts/${g.contacts[0].id}`" class="text-n-brand">{{ $t('TOLZAR_SETTINGS.DEDUPE.REVIEW') }}</router-link>
              </div>
            </div>

            <!-- links -->
            <div v-if="current === 'links' && data.channels" class="max-w-[620px]">
              <div class="grid gap-2 md:grid-cols-3">
                <input v-model="data.channels.whatsapp" :class="INPUT" :placeholder="$t('TOLZAR_SETTINGS_UI.LINKS.WHATSAPP_PLACEHOLDER')" :aria-label="$t('TOLZAR_SETTINGS_UI.LINKS.WHATSAPP')" />
                <input v-model="data.channels.messenger" :class="INPUT" :placeholder="$t('TOLZAR_SETTINGS_UI.LINKS.MESSENGER_PLACEHOLDER')" :aria-label="$t('TOLZAR_SETTINGS_UI.LINKS.MESSENGER')" />
                <input v-model="data.channels.instagram" :class="INPUT" :placeholder="$t('TOLZAR_SETTINGS_UI.LINKS.INSTAGRAM_PLACEHOLDER')" :aria-label="$t('TOLZAR_SETTINGS_UI.LINKS.INSTAGRAM')" />
              </div>
              <button type="button" :class="BTN_GHOST" :disabled="busy.channels" @click="saveChannels">{{ busy.channels ? $t('TOLZAR_UI.SAVING') : $t('TOLZAR_SETTINGS.SAVE') }}</button>
              <label :class="LABEL">{{ $t('TOLZAR_SETTINGS.LINKS.CAMPAIGN') }}</label>
              <input v-model="data.campaign" :class="INPUT" />
              <label :class="LABEL">{{ $t('TOLZAR_SETTINGS.LINKS.GREETING') }}</label>
              <input v-model="data.greeting" :class="INPUT" />
              <button type="button" :class="BTN" :disabled="busy.links" @click="makeLinks">{{ busy.links ? $t('TOLZAR_UI.LOADING') : $t('TOLZAR_SETTINGS.LINKS.CREATE') }}</button>
              <div v-if="data.made" class="mt-3">
                <div v-for="(url, ch) in data.made.links" :key="ch" class="flex flex-wrap gap-3 items-center py-2 border-t border-n-weak">
                  <!-- eslint-disable-next-line vue/no-v-html -->
                  <span class="w-[110px]" v-html="data.made.qr[ch]" />
                  <code class="flex-1 text-xs break-all">{{ url }}</code>
                </div>
              </div>
              <table v-if="(data.refs || []).length" class="mt-3 w-full text-[13px]">
                <thead>
                  <tr class="text-left text-xs text-n-slate-10">
                    <th class="py-1 font-semibold">{{ $t('TOLZAR_SETTINGS.LINKS.CAMPAIGN') }}</th>
                    <th class="font-semibold">{{ $t('TOLZAR_SETTINGS_UI.LINKS.CODE') }}</th>
                    <th class="font-semibold">{{ $t('TOLZAR_SETTINGS.USAGE.conversations') }}</th>
                  </tr>
                </thead>
                <tbody>
                  <tr v-for="r in data.refs" :key="r.code" class="border-t border-n-weak"><td class="py-1.5">{{ r.campaign || '—' }}</td><td>{{ r.code }}</td><td>{{ r.conversations }}</td></tr>
                </tbody>
              </table>
            </div>

            <!-- broadcasts -->
            <div v-if="current === 'broadcasts' && data.draft" class="max-w-[620px]">
              <ShadowBadge state="shadow" :hint="$t('TOLZAR_SETTINGS_UI.SHADOW_DETAIL.broadcasts')" />
              <p class="mt-1 mb-2 text-xs text-n-slate-10">{{ $t('TOLZAR_SETTINGS_UI.SHADOW_DETAIL.broadcasts') }}</p>
              <label :class="LABEL" class="!mt-0">{{ $t('TOLZAR_SETTINGS.BROADCASTS.NAME') }}</label>
              <input v-model="data.draft.name" :class="INPUT" />
              <div class="grid gap-2 md:grid-cols-2">
                <div>
                  <label :class="LABEL">{{ $t('TOLZAR_SETTINGS_UI.BROADCASTS.AUDIENCE_FIELD') }}</label>
                  <select v-model="data.draft.audience.field" :class="INPUT" @change="resetAudienceValue">
                    <option v-for="f in fields" :key="f.key" :value="f.key">{{ f.label }}</option>
                  </select>
                </div>
                <div>
                  <label :class="LABEL">{{ $t('TOLZAR_SETTINGS_UI.BROADCASTS.AUDIENCE_VALUE') }}</label>
                  <select v-if="isStageField(data.draft.audience.field)" v-model="data.draft.audience.value" :class="INPUT">
                    <option value="">{{ $t('TOLZAR_SETTINGS_UI.BROADCASTS.PICK_STAGE') }}</option>
                    <option v-for="s in STAGES" :key="s.key" :value="s.key">{{ s.label }}</option>
                  </select>
                  <select v-else-if="fieldValues.length" v-model="data.draft.audience.value" :class="INPUT">
                    <option value="">{{ $t('TOLZAR_SETTINGS_UI.BROADCASTS.PICK_VALUE') }}</option>
                    <option v-for="v in fieldValues" :key="v" :value="v">{{ v }}</option>
                  </select>
                  <input v-else v-model="data.draft.audience.value" :class="INPUT" :placeholder="$t('TOLZAR_SETTINGS_UI.BROADCASTS.VALUE_PLACEHOLDER')" />
                </div>
              </div>
              <label :class="LABEL">{{ $t('TOLZAR_SETTINGS.BROADCASTS.MESSAGE') }}</label>
              <textarea v-model="data.draft.text.en" rows="3" :class="INPUT" />
              <div class="flex flex-wrap gap-2">
                <button type="button" :class="BTN_GHOST" :disabled="busy.broadcast_preview" @click="previewBroadcast">{{ busy.broadcast_preview ? $t('TOLZAR_UI.LOADING') : $t('TOLZAR_SETTINGS.BROADCASTS.PREVIEW') }}</button>
                <button type="button" :class="BTN" :disabled="busy.broadcast_save" @click="saveBroadcast">{{ busy.broadcast_save ? $t('TOLZAR_UI.SAVING') : $t('TOLZAR_SETTINGS.SAVE') }}</button>
              </div>
              <p v-if="data.preview" class="p-2 mt-3 text-[13px] rounded-lg" :class="TONE_OK">
                <b>{{ $t('TOLZAR_SETTINGS.BROADCASTS.WOULD', { n: data.preview.audience }) }}</b>
                <span class="block mt-1">{{ $t('TOLZAR_SETTINGS_UI.QUOTED', { text: (data.preview.messages || {}).en }) }}</span>
              </p>
              <div v-for="b in data.list" :key="b.id" class="flex flex-wrap gap-2 justify-between items-center py-2 border-t border-n-weak text-[13px]">
                <span>
                  {{ b.name }}
                  <span class="text-n-slate-10">{{ (b.runs || [])[0] ? $t('TOLZAR_SETTINGS_UI.BROADCASTS.LAST_RUN', { n: b.runs[0].would_send ?? 0 }) : $t('TOLZAR_SETTINGS_UI.BROADCASTS.NO_RUN') }}</span>
                </span>
                <button type="button" :class="BTN" class="!mt-0 !h-7" :disabled="busy[`broadcast_run:${b.id}`]" @click="runBroadcast(b.id)">{{ $t('TOLZAR_SETTINGS.BROADCASTS.RUN') }}</button>
              </div>
            </div>

            <!-- connections (Facebook & Instagram; hidden until the Tolzar Meta app exists) -->
            <div v-if="current === 'connections'" class="max-w-[640px]">
              <p v-if="!data.app_configured" class="p-2 text-xs rounded-lg" :class="TONE_WARN">{{ $t('TOLZAR_SETTINGS.CONNECTIONS.PARKED') }}</p>
              <template v-else>
                <button v-if="!data.connected" type="button" :class="BTN" :disabled="busy.meta_connect" @click="metaConnect">{{ $t('TOLZAR_SETTINGS.CONNECTIONS.CONNECT') }}</button>
                <template v-else>
                  <p class="text-sm">{{ $t('TOLZAR_SETTINGS.CONNECTIONS.CONNECTED', { who: data.user_name, status: data.status }) }}</p>
                  <div v-for="p in data.pages || []" :key="p.id" class="flex flex-wrap gap-2 items-center py-2 border-t border-n-weak text-[13px]">
                    <input v-model="p.selected" type="checkbox" class="accent-n-brand" :aria-label="p.name" />
                    <span class="flex-1">{{ p.name }}<span v-if="p.ig_username" class="text-n-slate-10"> · {{ $t('TOLZAR_SETTINGS_UI.CONNECTIONS.INSTAGRAM', { name: p.ig_username }) }}</span></span>
                    <input v-model="p.team" :class="INPUT" class="!w-[140px]" :placeholder="$t('TOLZAR_SETTINGS.CONNECTIONS.TEAM')" :aria-label="$t('TOLZAR_SETTINGS.CONNECTIONS.TEAM')" />
                  </div>
                  <div class="flex gap-2">
                    <button type="button" :class="BTN" :disabled="busy.meta_save" @click="metaSave">{{ busy.meta_save ? $t('TOLZAR_UI.SAVING') : $t('TOLZAR_SETTINGS.SAVE') }}</button>
                    <button type="button" :class="BTN_GHOST" :disabled="busy.meta_disconnect" @click="metaDisconnect">{{ $t('TOLZAR_SETTINGS.CONNECTIONS.DISCONNECT') }}</button>
                  </div>
                </template>
              </template>
            </div>

            <!-- mcp -->
            <div v-if="current === 'mcp'" class="max-w-[620px]">
              <p class="p-2 text-xs rounded-lg" :class="TONE_WARN">{{ $t('TOLZAR_SETTINGS.MCP.NOT_PUBLIC') }}</p>
              <div class="flex gap-2">
                <button type="button" :class="BTN" :disabled="busy.mcp_create" @click="newToken(false)">{{ $t('TOLZAR_SETTINGS.MCP.CREATE') }}</button>
                <button type="button" :class="BTN_GHOST" :disabled="busy.mcp_revoke" @click="newToken(true)">{{ $t('TOLZAR_SETTINGS.MCP.REVOKE') }}</button>
              </div>
              <template v-if="data.token">
                <p class="mt-3 mb-1 text-xs text-n-amber-11">{{ $t('TOLZAR_SETTINGS_UI.MCP.SHOWN_ONCE') }}</p>
                <code class="block p-2 text-xs break-all rounded bg-n-alpha-1">{{ data.token }}</code>
              </template>
            </div>
          </template>
        </section>
      </div>
    </div>
  </div>
</template>
