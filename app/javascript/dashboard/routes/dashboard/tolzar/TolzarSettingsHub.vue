<script setup>
import { ref, computed, onMounted } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
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
import { MEDIA_MODES, VIDEO_FRAMES, getMedia, saveMedia as saveMediaConfig, mediaConfig } from 'dashboard/components-next/Tolzar/tolzarMedia';
import { brainErrors, isOwnerOnly } from 'dashboard/components-next/Tolzar/tolzarBrainApi';

// Tolzar Settings hub (approved mock settings-hub-v1): one home for what Tolzar does for this
// workspace. Every section reads/writes the brain through the admin proxy; AI features run in
// Shadow. Generic for any business.
const accountId = useMapGetter('getCurrentAccountId');
const { t: $t } = useI18n();
const base = computed(() => `/api/v1/accounts/${accountId.value}/tolzar`);
const get = (feature, params = {}) =>
  window.axios.get(`${base.value}/brain/${feature}`, { params }).then(r => r.data);
// A refusal (Owner-only, invalid, brain unreachable) comes back as its body, never as "Saved".
const post = (feature, body = {}) =>
  window.axios
    .post(`${base.value}/brain/${feature}`, body)
    .then(r => r.data)
    .catch(e => e?.response?.data || { ok: false, error: 'brain_unreachable' });
const problems = r =>
  isOwnerOnly(r) ? [$t('TOLZAR_SETTINGS.R1.OWNER_ONLY')] : brainErrors(r);

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
const busy = ref(false);
const note = ref('');

async function open(key) {
  current.value = key;
  note.value = '';
  busy.value = true;
  try {
    if (key === 'usage') data.value = await get('usage', { days: usageDays.value });
    if (key === 'audit') data.value = (await window.axios.get(`${base.value}/audit`)).data;
    if (key === 'export') data.value = (await window.axios.get(`${base.value}/export`)).data;
    if (key === 'sla') data.value = await get('sla');
    if (key === 'qa') data.value = await get('qa');
    if (key === 'media') {
      const m = await getMedia(accountId.value);
      data.value = { ...m, config: mediaConfig(m.config) };
    }
    if (key === 'recovery') data.value = await get('recovery');
    if (key === 'learned') data.value = await get('learned');
    if (key === 'brief') data.value = await get('brief');
    if (key === 'ask') data.value = { answer: null, question: '' };
    if (key === 'dedupe') data.value = await get('dedupe');
    if (key === 'links') {
      const [ch, at] = await Promise.all([get('channels'), get('attribution')]);
      data.value = { channels: ch.channels || {}, refs: at.refs || [], campaign: '', greeting: '', made: null };
    }
    if (key === 'broadcasts') {
      const b = await get('broadcasts');
      data.value = { list: b.broadcasts || [], draft: { name: '', audience: { field: 'lifecycle_stage', value: '' }, text: { en: '' } }, preview: null };
    }
    if (key === 'mcp') data.value = { token: '' };
    if (key === 'connections') data.value = (await window.axios.get(`${base.value}/meta/status`)).data;
    if (key === 'roles') {
      const [members, r] = await Promise.all([
        window.axios.get(`/api/v1/accounts/${accountId.value}/agents`).then(x => x.data),
        get('roles'),
      ]);
      // H3: the account owner is always an Owner; other admins are Managers unless promoted.
      const table = r.roles || {};
      const ownerId = r.owner_user_id;
      data.value = {
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
  } catch (e) {
    const why = problems(e?.response?.data);
    note.value = why.length ? why.join(' · ') : String(e);
  } finally {
    busy.value = false;
  }
}
const done = msg => {
  note.value = msg;
};
// Shows the brain's refusal, else `msg`; true when the request went through.
const report = (r, msg = $t('TOLZAR_SETTINGS.R1.SAVED')) => {
  const why = problems(r);
  done(why.length ? why.join(' · ') : msg);
  return !why.length;
};

async function saveSla() {
  const r = await post('sla', data.value.config);
  if (report(r)) data.value = { ...data.value, ...r };
}
async function saveMedia() {
  const r = await saveMediaConfig(accountId.value, data.value.config);
  const errors = brainErrors(r);
  done(errors.length ? errors.join(' · ') : $t('TOLZAR_SETTINGS.R1.SAVED'));
}
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
async function saveRecovery() {
  const r = await post('recovery', data.value.config);
  if (report(r) && r.config) data.value.config = r.config;
}
async function startExport() {
  const r = await window.axios
    .post(`${base.value}/export`)
    .then(x => x.data)
    .catch(e => e?.response?.data || { ok: false, error: 'brain_unreachable' });
  report(r, 'Preparing: refresh in a few minutes.');
}
async function download(x) {
  // The API authenticates with headers, so fetch the file and hand it to the browser.
  const r = await window.axios.get(`${base.value}/export/download`, { params: { token: x.token }, responseType: 'blob' });
  const a = document.createElement('a');
  a.href = URL.createObjectURL(r.data);
  a.download = x.filename || 'tolzar-export.tar.gz';
  a.click();
  URL.revokeObjectURL(a.href);
}
async function refreshDedupe() {
  busy.value = true;
  const r = await post('dedupe_refresh');
  if (report(r, '')) data.value = r;
  busy.value = false;
}
async function saveChannels() {
  report(await post('channels', data.value.channels));
}
async function makeLinks() {
  const r = await post('links', { campaign: data.value.campaign, greeting: data.value.greeting });
  if (report(r, '')) data.value.made = r;
}
async function previewBroadcast() {
  const r = await post('broadcasts_preview', { broadcast: data.value.draft });
  if (report(r, '')) data.value.preview = r;
}
async function saveBroadcast() {
  if (report(await post('broadcasts', { broadcast: data.value.draft }))) open('broadcasts');
}
async function runBroadcast(id) {
  const r = await post('broadcasts_run', { id });
  report(r, `Shadow run: would send to ${r.run?.would_send ?? 0}`);
}
async function decide(qt, status) {
  if (report(await post('learned_status', { question_type: qt, status }))) open('learned');
}
async function buildBrief() {
  busy.value = true;
  const r = await post('brief_build');
  if (report(r, '')) data.value = r;
  busy.value = false;
}
async function askInbox() {
  busy.value = true;
  const r = await post('ask', { question: data.value.question });
  if (report(r, '')) data.value.answer = r;
  busy.value = false;
}
async function setRole(m) {
  const r = await post('roles', { user_id: m.id, role: m.tolzar });
  if (problems(r).length) await open('roles'); // put the select back to what is stored
  report(r);
}
async function metaConnect() {
  const r = (await window.axios.post(`${base.value}/meta/connect_url`)).data;
  if (r.url) window.location.href = r.url;
  else done(r.error || 'error');
}
async function metaSave() {
  data.value = (await window.axios.post(`${base.value}/meta/select`, { pages: data.value.pages })).data;
  done($t('TOLZAR_SETTINGS.SAVE'));
}
async function metaDisconnect() {
  data.value = (await window.axios.post(`${base.value}/meta/disconnect`)).data;
}
async function newToken(revoke = false) {
  const r = await post('mcp_token', revoke ? { revoke: true } : {});
  data.value.token = revoke ? '' : r.token;
  done(revoke ? 'Revoked' : '');
}
const maxY = rows => Math.max(1, ...(rows || []).map(r => r.y || 0));

// ?section=<key> opens that section (links from the Getting started checklist).
const route = useRoute();
onMounted(() => {
  const wanted = String(route.query.section || '');
  open(SECTIONS.some(([, keys]) => keys.includes(wanted)) ? wanted : 'usage');
});
</script>

<template>
  <div class="overflow-auto flex-1 bg-n-background" data-tz-build="settings-hub-1">
    <div class="mx-auto max-w-[1180px] px-5 pb-16 pt-7 md:px-6">
      <div class="flex flex-wrap gap-3 justify-between items-center">
        <h1 class="m-0 text-[22px] font-extrabold tracking-tight text-n-slate-12">{{ $t('TOLZAR_SETTINGS.TITLE') }}</h1>
        <router-link :to="{ name: 'tolzar_onboarding' }" class="tz-btn !mt-0 no-underline">{{ $t('TOLZAR_ONBOARDING.OPEN') }}</router-link>
      </div>
      <p class="mt-1 text-sm text-n-slate-11">{{ $t('TOLZAR_SETTINGS.LEAD') }}</p>
      <div class="grid gap-4 mt-5 md:grid-cols-[220px_minmax(0,1fr)]">
        <nav class="p-1.5 rounded-xl border bg-n-solid-1 border-n-weak h-fit">
          <template v-for="[group, keys] in SECTIONS" :key="group">
            <div class="px-2.5 pt-2.5 pb-1 text-[11px] font-semibold uppercase tracking-wide text-n-slate-10">{{ $t(`TOLZAR_SETTINGS.GROUP.${group}`) }}</div>
            <button
              v-for="k in keys"
              :key="k"
              type="button"
              class="block px-2.5 py-2 w-full text-left rounded-lg text-[13.5px]"
              :class="current === k ? 'font-semibold text-n-brand bg-n-brand/10' : 'text-n-slate-11 hover:bg-n-alpha-1'"
              @click="open(k)"
            >
              {{ $t(`TOLZAR_SETTINGS.NAV.${k}`) }}
            </button>
          </template>
        </nav>

        <section class="p-5 rounded-xl border bg-n-solid-1 border-n-weak min-h-[300px]">
          <h2 class="mt-0 mb-1 text-[17px] font-bold text-n-slate-12">{{ $t(`TOLZAR_SETTINGS.NAV.${current}`) }}</h2>
          <p class="mt-0 mb-4 text-[13px] text-n-slate-10">{{ $t(`TOLZAR_SETTINGS.HINT.${current}`) }}</p>
          <p v-if="note" class="p-2 mb-3 text-[13px] rounded-lg text-n-brand bg-n-brand/10">{{ note }}</p>
          <p v-if="busy" class="text-n-slate-10">…</p>

          <!-- usage -->
          <div v-if="current === 'usage'" class="flex gap-1 mb-3">
            <button
              v-for="d in [7, 30, 90]"
              :key="d"
              type="button"
              class="px-2.5 py-1 text-xs rounded-full border"
              :class="usageDays === d ? 'border-n-brand bg-n-brand text-white' : 'border-n-weak text-n-slate-11'"
              @click="usageDays = d; open('usage')"
            >
              {{ $t('TOLZAR_SETTINGS.USAGE.DAYS', { n: d }) }}
            </button>
          </div>
          <div v-if="current === 'usage' && data.total" class="grid grid-cols-2 gap-2 md:grid-cols-5">
            <div v-for="(v, k) in data.total" :key="k" class="p-3 rounded-lg bg-n-alpha-1">
              <div class="text-xl font-bold text-n-slate-12">{{ v.toLocaleString() }}</div>
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

          <!-- roles -->
          <div v-if="current === 'roles'">
            <table class="w-full text-[13px]">
              <tr v-for="m in data.members || []" :key="m.id" class="border-t border-n-weak">
                <td class="py-2">{{ m.name }}<div class="text-xs text-n-slate-10">{{ m.email }}</div></td>
                <td class="w-[180px]">
                  <select v-if="m.role === 'administrator'" v-model="m.tolzar" class="tz-in" :disabled="m.id === data.ownerId" @change="setRole(m)">
                    <option value="owner">{{ $t('TOLZAR_SETTINGS.ROLES.owner') }}</option>
                    <option value="manager">{{ $t('TOLZAR_SETTINGS.ROLES.manager') }}</option>
                  </select>
                  <span v-else class="text-n-slate-11">{{ $t('TOLZAR_SETTINGS.ROLES.agent') }}</span>
                </td>
              </tr>
            </table>
            <ul class="mt-4 text-xs text-n-slate-10"><li>{{ $t('TOLZAR_SETTINGS.ROLES.RULE_OWNER') }}</li><li>{{ $t('TOLZAR_SETTINGS.ROLES.RULE_MANAGER') }}</li><li>{{ $t('TOLZAR_SETTINGS.ROLES.RULE_AGENT') }}</li></ul>
          </div>

          <!-- audit -->
          <table v-if="current === 'audit'" class="w-full text-[13px]">
            <tr v-for="(e, i) in data.entries || []" :key="i" class="border-t border-n-weak">
              <td class="py-2 whitespace-nowrap text-n-slate-10">{{ String(e.at).slice(0, 16).replace('T', ' ') }}</td>
              <td class="px-2">{{ e.actor }}</td>
              <td class="px-2 font-semibold">{{ e.action }}</td>
              <td class="text-n-slate-11">{{ Array.isArray(e.changes) ? e.changes.slice(0, 3).join(' · ') : Object.keys(e.changes || {}).join(', ') }}</td>
            </tr>
          </table>

          <!-- export -->
          <div v-if="current === 'export'">
            <button type="button" class="tz-btn" @click="startExport">{{ $t('TOLZAR_SETTINGS.EXPORT.PREPARE') }}</button>
            <table class="mt-4 w-full text-[13px]">
              <tr v-for="x in data.exports || []" :key="x.token" class="border-t border-n-weak">
                <td class="py-2">{{ String(x.created_at).slice(0, 16).replace('T', ' ') }}</td>
                <td>{{ (x.size / 1048576).toFixed(1) }} MB</td>
                <td><button type="button" class="text-n-brand" @click="download(x)">{{ $t('TOLZAR_SETTINGS.EXPORT.DOWNLOAD') }}</button></td>
              </tr>
            </table>
          </div>

          <!-- SLA -->
          <div v-if="current === 'sla' && data.config" class="max-w-[440px]">
            <label class="flex gap-2 items-center text-sm"><input v-model="data.config.enabled" type="checkbox" /> {{ $t('TOLZAR_SETTINGS.ON_SHADOW') }}</label>
            <label class="tz-lab">{{ $t('TOLZAR_SETTINGS.SLA.MINUTES') }}</label>
            <input v-model.number="data.config.first_reply_minutes" type="number" min="1" class="tz-in" />
            <label class="flex gap-2 items-center mt-3 text-sm"><input v-model="data.config.working_hours_only" type="checkbox" /> {{ $t('TOLZAR_SETTINGS.SLA.WORKING_HOURS') }}</label>
            <label class="flex gap-2 items-center mt-2 text-sm"><input v-model="data.config.mention_assignee" type="checkbox" /> {{ $t('TOLZAR_SETTINGS.SLA.MENTION') }}</label>
            <p class="text-xs text-n-slate-10">{{ $t('TOLZAR_SETTINGS.SLA.COUNTS', { late: (data.counts || {}).sla_breach || 0, ok: (data.counts || {}).sla_ok || 0 }) }}</p>
            <button type="button" class="tz-btn" @click="saveSla">{{ $t('TOLZAR_SETTINGS.SAVE') }}</button>
          </div>

          <!-- QA -->
          <div v-if="current === 'qa'">
            <div v-for="c in data.coaching || []" :key="c.who" class="p-3 mb-2 rounded-lg border border-n-weak">
              <div class="flex justify-between"><b>{{ c.who }}</b><span>{{ c.score }}/100 · {{ c.conversations }}</span></div>
              <div v-if="c.strengths.length" class="text-xs text-emerald-600">+ {{ c.strengths.join(' · ') }}</div>
              <div v-if="c.work_on.length" class="text-xs text-amber-600">→ {{ c.work_on.join(' · ') }}</div>
            </div>
            <p v-if="!(data.coaching || []).length" class="text-n-slate-10">{{ $t('TOLZAR_SETTINGS.NONE_YET') }}</p>
            <h3 class="mt-4 text-sm font-semibold">{{ $t('TOLZAR_SETTINGS.QA.RUBRIC') }}</h3>
            <ul class="text-[13px] text-n-slate-11"><li v-for="r in data.rubric || []" :key="r.key">{{ r.description }} (×{{ r.weight }})</li></ul>
          </div>

          <!-- media -->
          <div v-if="current === 'media' && data.config" class="max-w-[520px]">
            <label class="tz-lab">{{ $t('TOLZAR_SETTINGS.MEDIA.VOICE') }}</label>
            <select v-model="data.config.voice" class="tz-in"><option v-for="m in MEDIA_MODES" :key="m" :value="m">{{ $t(`TOLZAR_SETTINGS.MODES.${m}`) }}</option></select>
            <label class="tz-lab">{{ $t('TOLZAR_SETTINGS.MEDIA.IMAGES') }}</label>
            <select v-model="data.config.images" class="tz-in"><option v-for="m in MEDIA_MODES" :key="m" :value="m">{{ $t(`TOLZAR_SETTINGS.MODES.${m}`) }}</option></select>
            <label class="tz-lab">{{ $t('TOLZAR_SETTINGS.MEDIA.FIELDS') }}</label>
            <div v-for="(f, i) in data.config.image_fields || []" :key="i" class="flex gap-1 mb-1">
              <input v-model="f.key" class="tz-in !w-[140px]" placeholder="order_number" />
              <input v-model="f.description" class="tz-in" />
              <button type="button" class="px-1 text-n-slate-9" @click="data.config.image_fields.splice(i, 1)">×</button>
            </div>
            <button type="button" class="text-xs text-n-brand" @click="(data.config.image_fields = data.config.image_fields || []).push({ key: '', description: '' })">+</button>
            <label class="tz-lab">{{ $t('TOLZAR_SETTINGS.MEDIA.VIDEO') }}</label>
            <select v-model="data.config.video" class="tz-in"><option v-for="m in MEDIA_MODES" :key="m" :value="m">{{ $t(`TOLZAR_SETTINGS.MODES.${m}`) }}</option></select>
            <label class="tz-lab">{{ $t('TOLZAR_SETTINGS.MEDIA.VIDEO_FRAMES') }}</label>
            <input v-model.number="data.config.video_frames" type="number" :min="VIDEO_FRAMES.min" :max="VIDEO_FRAMES.max" class="tz-in !w-[100px]" />
            <p class="text-xs text-amber-700">{{ $t('TOLZAR_SETTINGS.MEDIA.VIDEO_NOTE') }}</p>
            <label class="tz-lab">{{ $t('TOLZAR_SETTINGS.MEDIA.RETENTION') }}</label>
            <input v-model.number="data.config.retention_days" type="number" min="1" class="tz-in" />
            <p class="text-xs text-n-slate-10">{{ $t('TOLZAR_SETTINGS.MEDIA.PRIVACY') }}</p>
            <button type="button" class="tz-btn" @click="saveMedia">{{ $t('TOLZAR_SETTINGS.SAVE') }}</button>
          </div>

          <!-- recovery -->
          <div v-if="current === 'recovery' && data.config" class="max-w-[520px]">
            <label class="flex gap-2 items-center text-sm"><input v-model="data.config.enabled" type="checkbox" /> {{ $t('TOLZAR_SETTINGS.ON_SHADOW') }}</label>
            <label class="tz-lab">{{ $t('TOLZAR_SETTINGS.RECOVERY.QUIET') }}</label>
            <input v-model.number="data.config.quiet_hours" type="number" min="6" class="tz-in" />
            <label class="tz-lab">{{ $t('TOLZAR_SETTINGS.RECOVERY.TOUCH_DAYS') }}</label>
            <input v-model="touchDays" class="tz-in" placeholder="1, 3, 7" />
            <label class="tz-lab">{{ $t('TOLZAR_SETTINGS.RECOVERY.MAX_PER_RUN') }}</label>
            <input v-model.number="data.config.max_per_run" type="number" min="1" max="50" class="tz-in" />
            <p class="text-xs text-n-slate-10">{{ $t('TOLZAR_SETTINGS.RECOVERY.PLANNED', { n: data.planned || 0 }) }}</p>
            <ul v-if="(data.recent || []).length" class="pl-4 mt-1 text-xs text-n-slate-11">
              <li v-for="(r, i) in data.recent.slice(0, 10)" :key="i">
                {{ $t('TOLZAR_SETTINGS.RECOVERY.PLAN_ROW', { at: (r.planned_at || '').slice(0, 16).replace('T', ' '), n: (r.touches || []).length, lang: r.language || '' }) }}
              </li>
            </ul>
            <button type="button" class="tz-btn" @click="saveRecovery">{{ $t('TOLZAR_SETTINGS.SAVE') }}</button>
          </div>

          <!-- learned -->
          <div v-if="current === 'learned'">
            <p class="mt-0 mb-2 text-xs text-n-slate-10">{{ $t('TOLZAR_SETTINGS.LEARNED.APPROVE_NOTE') }}</p>
            <div v-for="t in data.types || []" :key="t.question_type" class="p-3 mb-2 rounded-lg border border-n-weak">
              <div class="flex flex-wrap gap-2 justify-between items-center">
                <b class="text-[13.5px]">{{ t.question_type }}</b>
                <span class="text-xs text-n-slate-10">{{ t.count }} · {{ Math.round(t.consistency * 100) }}% · {{ t.status }}{{ t.never_list_topic ? ` · ${t.never_list_topic}` : '' }}</span>
              </div>
              <div v-if="t.examples[0]" class="mt-1 text-xs text-n-slate-11">"{{ t.examples[0].staff_answer }}"</div>
              <div v-if="t.status === 'proposed'" class="flex gap-2 mt-2">
                <button type="button" class="tz-btn !h-7" @click="decide(t.question_type, 'shadow')">{{ $t('TOLZAR_SETTINGS.LEARNED.APPROVE') }}</button>
                <button type="button" class="tz-btn-ghost !h-7" @click="decide(t.question_type, 'rejected')">{{ $t('TOLZAR_SETTINGS.LEARNED.REJECT') }}</button>
              </div>
            </div>
            <p v-if="!(data.types || []).length" class="text-n-slate-10">{{ $t('TOLZAR_SETTINGS.NONE_YET') }}</p>
          </div>

          <!-- brief -->
          <div v-if="current === 'brief'">
            <button type="button" class="tz-btn" @click="buildBrief">{{ $t('TOLZAR_SETTINGS.BRIEF.BUILD') }}</button>
            <div v-if="data.brief && data.brief.summary" class="grid gap-3 mt-4 md:grid-cols-2">
              <div v-for="(items, k) in data.brief.summary" :key="k" class="p-3 rounded-lg bg-n-alpha-1">
                <div class="text-xs font-semibold uppercase text-n-slate-10">{{ $t(`TOLZAR_SETTINGS.BRIEF.${k}`) }}</div>
                <ul class="pl-4 my-1 text-[13px]"><li v-for="x in items" :key="x">{{ x }}</li></ul>
              </div>
            </div>
          </div>

          <!-- ask -->
          <div v-if="current === 'ask'">
            <div class="flex gap-2"><input v-model="data.question" class="tz-in" :placeholder="$t('TOLZAR_SETTINGS.ASK.PLACEHOLDER')" @keyup.enter="askInbox" /><button type="button" class="tz-btn" @click="askInbox">{{ $t('TOLZAR_SETTINGS.ASK.GO') }}</button></div>
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
            <button type="button" class="tz-btn" @click="refreshDedupe">{{ $t('TOLZAR_SETTINGS.DEDUPE.REFRESH') }}</button>
            <div v-for="(g, i) in (data.groups || []).slice(0, 50)" :key="i" class="flex flex-wrap gap-2 justify-between py-2 border-t border-n-weak text-[13px]">
              <span>{{ g.contacts.map(c => c.name || `#${c.id}`).join(' · ') }}</span>
              <span class="text-n-slate-10">{{ g.matched_on.join(', ') }}</span>
              <router-link :to="`/app/accounts/${accountId}/contacts/${g.contacts[0].id}`" class="text-n-brand">{{ $t('TOLZAR_SETTINGS.DEDUPE.REVIEW') }}</router-link>
            </div>
          </div>

          <!-- links -->
          <div v-if="current === 'links' && data.channels" class="max-w-[620px]">
            <div class="grid gap-2 md:grid-cols-3">
              <input v-model="data.channels.whatsapp" class="tz-in" placeholder="WhatsApp +20…" />
              <input v-model="data.channels.messenger" class="tz-in" placeholder="Messenger page" />
              <input v-model="data.channels.instagram" class="tz-in" placeholder="@instagram" />
            </div>
            <button type="button" class="mt-2 tz-btn-ghost" @click="saveChannels">{{ $t('TOLZAR_SETTINGS.SAVE') }}</button>
            <label class="tz-lab">{{ $t('TOLZAR_SETTINGS.LINKS.CAMPAIGN') }}</label>
            <input v-model="data.campaign" class="tz-in" />
            <label class="tz-lab">{{ $t('TOLZAR_SETTINGS.LINKS.GREETING') }}</label>
            <input v-model="data.greeting" class="tz-in" />
            <button type="button" class="mt-2 tz-btn" @click="makeLinks">{{ $t('TOLZAR_SETTINGS.LINKS.CREATE') }}</button>
            <div v-if="data.made" class="mt-3">
              <div v-for="(url, ch) in data.made.links" :key="ch" class="flex flex-wrap gap-3 items-center py-2 border-t border-n-weak">
                <!-- eslint-disable-next-line vue/no-v-html -->
                <span class="w-[110px]" v-html="data.made.qr[ch]" />
                <code class="flex-1 text-xs break-all">{{ url }}</code>
              </div>
            </div>
            <table class="mt-3 w-full text-[13px]">
              <tr v-for="r in data.refs" :key="r.code" class="border-t border-n-weak"><td class="py-1.5">{{ r.campaign || '—' }}</td><td>{{ r.code }}</td><td>{{ r.conversations }}</td></tr>
            </table>
          </div>

          <!-- broadcasts -->
          <div v-if="current === 'broadcasts' && data.draft" class="max-w-[620px]">
            <span class="inline-flex items-center px-2 py-0.5 mb-2 text-[11px] font-semibold rounded-full text-amber-700 bg-amber-500/10">{{ $t('TOLZAR_HONEST.BROADCASTS') }}</span>
            <input v-model="data.draft.name" class="tz-in" :placeholder="$t('TOLZAR_SETTINGS.BROADCASTS.NAME')" />
            <div class="flex gap-2 mt-2">
              <input v-model="data.draft.audience.field" class="tz-in" placeholder="lifecycle_stage" />
              <input v-model="data.draft.audience.value" class="tz-in" placeholder="Customer Won" />
            </div>
            <textarea v-model="data.draft.text.en" rows="3" class="mt-2 tz-in" :placeholder="$t('TOLZAR_SETTINGS.BROADCASTS.MESSAGE')" />
            <div class="flex gap-2 mt-2">
              <button type="button" class="tz-btn-ghost" @click="previewBroadcast">{{ $t('TOLZAR_SETTINGS.BROADCASTS.PREVIEW') }}</button>
              <button type="button" class="tz-btn" @click="saveBroadcast">{{ $t('TOLZAR_SETTINGS.SAVE') }}</button>
            </div>
            <p v-if="data.preview" class="text-[13px]">{{ $t('TOLZAR_SETTINGS.BROADCASTS.WOULD', { n: data.preview.audience }) }} — "{{ (data.preview.messages || {}).en }}"</p>
            <div v-for="b in data.list" :key="b.id" class="flex justify-between items-center py-2 border-t border-n-weak text-[13px]">
              <span>{{ b.name }} <span class="text-n-slate-10">({{ (b.runs[0] || {}).would_send ?? '—' }})</span></span>
              <button type="button" class="tz-btn !h-7" @click="runBroadcast(b.id)">{{ $t('TOLZAR_SETTINGS.BROADCASTS.RUN') }}</button>
            </div>
          </div>

          <!-- connections (Facebook & Instagram; hidden until the Tolzar Meta app exists) -->
          <div v-if="current === 'connections'" class="max-w-[640px]">
            <p v-if="!data.app_configured" class="p-2 text-xs rounded-lg text-amber-700 bg-amber-500/10">{{ $t('TOLZAR_SETTINGS.CONNECTIONS.PARKED') }}</p>
            <template v-else>
              <button v-if="!data.connected" type="button" class="tz-btn" @click="metaConnect">{{ $t('TOLZAR_SETTINGS.CONNECTIONS.CONNECT') }}</button>
              <template v-else>
                <p class="text-sm">{{ $t('TOLZAR_SETTINGS.CONNECTIONS.CONNECTED', { who: data.user_name, status: data.status }) }}</p>
                <div v-for="p in data.pages || []" :key="p.id" class="flex flex-wrap gap-2 items-center py-2 border-t border-n-weak text-[13px]">
                  <input v-model="p.selected" type="checkbox" />
                  <span class="flex-1">{{ p.name }}<span v-if="p.ig_username" class="text-n-slate-10"> · @{{ p.ig_username }}</span></span>
                  <input v-model="p.team" class="tz-in !w-[140px]" :placeholder="$t('TOLZAR_SETTINGS.CONNECTIONS.TEAM')" />
                </div>
                <div class="flex gap-2"><button type="button" class="tz-btn" @click="metaSave">{{ $t('TOLZAR_SETTINGS.SAVE') }}</button><button type="button" class="tz-btn-ghost" @click="metaDisconnect">{{ $t('TOLZAR_SETTINGS.CONNECTIONS.DISCONNECT') }}</button></div>
              </template>
            </template>
          </div>

          <!-- mcp -->
          <div v-if="current === 'mcp'" class="max-w-[620px]">
            <p class="p-2 text-xs rounded-lg text-amber-700 bg-amber-500/10">{{ $t('TOLZAR_SETTINGS.MCP.NOT_PUBLIC') }}</p>
            <div class="flex gap-2">
              <button type="button" class="tz-btn" @click="newToken(false)">{{ $t('TOLZAR_SETTINGS.MCP.CREATE') }}</button>
              <button type="button" class="tz-btn-ghost" @click="newToken(true)">{{ $t('TOLZAR_SETTINGS.MCP.REVOKE') }}</button>
            </div>
            <code v-if="data.token" class="block p-2 mt-3 text-xs break-all rounded bg-n-alpha-1">{{ data.token }}</code>
          </div>
        </section>
      </div>
    </div>
  </div>
</template>

<style scoped>
.tz-lab {
  display: block;
  margin: 0.75rem 0 0.25rem;
  font-size: 0.75rem;
  color: rgb(var(--slate-11));
}
.tz-btn,
.tz-btn-ghost {
  display: inline-flex;
  align-items: center;
  height: 2.25rem;
  margin-top: 0.75rem;
  padding: 0 1rem;
  font-size: 0.875rem;
  font-weight: 600;
  border-radius: 0.75rem;
  cursor: pointer;
}
.tz-btn {
  color: #fff;
  background: #3e63dd;
  border: 0;
}
.tz-btn-ghost {
  color: rgb(var(--slate-11));
  background: rgb(var(--solid-1));
  border: 1px solid rgb(var(--border-weak));
}
.tz-in {
  box-sizing: border-box;
  width: 100%;
  padding: 0.5rem 0.625rem;
  font-size: 0.8125rem;
  color: rgb(var(--slate-12));
  background: rgb(var(--solid-1));
  border: 1px solid rgb(var(--border-weak));
  border-radius: 0.5rem;
  outline: none;
}
</style>
