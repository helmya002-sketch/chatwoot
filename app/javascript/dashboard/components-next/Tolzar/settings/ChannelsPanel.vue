<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { useLocale } from 'shared/composables/useLocale';
import ShadowBadge from '../ShadowBadge.vue';
import BrainNotice from './BrainNotice.vue';
import CredentialInput from './CredentialInput.vue';
import { BTN, BTN_GHOST, INPUT, LABEL, CHECK, TONE_BAD } from './tzClasses';
import {
  SMS_PROVIDERS,
  CRM_PROVIDERS,
  CRM_DIRECTIONS,
  SHOP_PROVIDERS,
  ORDER_LOOKUPS_DEFAULT,
  ORDER_PATTERN_MAX,
  ORDER_CHAT_CHANNELS,
  WIDGET_CHANNEL,
  TRACKING_HOSTS_MAX,
  channelLabelKey,
  parseHosts,
  credentialFields,
  credentialLabelKey,
  getSms,
  saveSms,
  previewSms,
  getCrm,
  saveCrm,
  crmRuns,
  previewCrm,
  crmMapRows,
  mapFromRows,
  runSummary,
  getCommerce,
  saveCommerce,
  syncCatalogue,
  orderStatus,
  commerceTemplates,
} from '../tolzarChannels';
import { credentialStatus } from '../tolzarCredentials';

// Settings hub → Channels: SMS fallback, CRM sync, Commerce. Shadow / dry run only: Tolzar
// shows the exact request it WOULD send. Keys are write-only: typed here, sent once, stored
// encrypted by the brain; the page only ever shows "Saved ••••1234".
const props = defineProps({
  section: { type: String, required: true }, // sms | crm | commerce
});
const { t } = useI18n();
const { resolvedLocale } = useLocale();
const accountId = useMapGetter('getCurrentAccountId');

const raw = ref(null); // the brain's GET answer (settings + credentials status)
const keys = ref({}); // typed keys only; never filled from a GET
const form = ref(null);
const result = ref(null);
const saved = ref('');
const busy = ref(false);
const preview = ref(null);
const probe = ref({ to: '', text: '', contactId: '', order: '' });
const runs = ref([]);
const openRun = ref(null);
const mapRows = ref([]);
const agents = ref([]);
const templates = ref([]);

// Order chat: which channels may answer "Where is my order?" (none until picked).
const hostsText = ref('');
const pickedChannel = type => (form.value?.order_chat_channels || []).includes(type);
function toggleChannel(type) {
  const list = form.value.order_chat_channels || [];
  form.value.order_chat_channels = list.includes(type) ? list.filter(c => c !== type) : [...list, type];
  // The website chat goes only together with allow_widget (and off again with it).
  if (type === WIDGET_CHANNEL) form.value.allow_widget = form.value.order_chat_channels.includes(type);
}
function setHosts(text) {
  hostsText.value = text;
  form.value.tracking_hosts = parseHosts(text);
}

const credFields = computed(() => credentialFields(props.section, form.value?.provider));
const credLabel = f => t(credentialLabelKey(props.section, form.value?.provider, f));
// A saved key belongs to the saved provider: after switching provider the brain drops it on save.
const credStatus = f =>
  (raw.value?.settings || {}).provider === form.value?.provider ? credentialStatus(raw.value, f) : {};

function fillMap() {
  const d = raw.value || {};
  const stored = (d.settings || {}).provider === form.value.provider ? (d.settings || {}).field_map : null;
  mapRows.value = crmMapRows(d.fields, stored, (d.default_maps || {})[form.value.provider]);
}

async function load() {
  result.value = null;
  saved.value = '';
  preview.value = null;
  keys.value = {};
  if (props.section === 'sms') {
    raw.value = await getSms(accountId.value);
    form.value = { provider: 'twilio', from: '', enabled: false, ...(raw.value.settings || {}) };
  } else if (props.section === 'crm') {
    const [c, r] = await Promise.all([getCrm(accountId.value), crmRuns(accountId.value)]);
    raw.value = c;
    form.value = { provider: 'hubspot', direction: 'to_crm', read_crm: false, enabled: false, stage_map: {}, ...(c.settings || {}) };
    runs.value = r.runs || [];
    fillMap();
  } else {
    const [c, a, tp] = await Promise.all([
      getCommerce(accountId.value),
      window.axios.get(`/api/v1/accounts/${accountId.value}/tolzar/agents`).then(x => x.data),
      commerceTemplates(accountId.value),
    ]);
    raw.value = c;
    form.value = { provider: 'shopify', shop_domain: '', currency: '', agent_id: '', catalogue_auto: false, order_chat: false, order_pattern: '', order_lookups_per_day: ORDER_LOOKUPS_DEFAULT, order_chat_channels: [], allow_widget: false, tracking_hosts: [], ...(c.settings || {}) };
    hostsText.value = (form.value.tracking_hosts || []).join(', ');
    agents.value = a.agents || [];
    templates.value = tp.templates || [];
  }
}

const after = (r, ok) => {
  result.value = r;
  saved.value = r && r.ok ? ok : '';
};
async function run(fn) {
  busy.value = true;
  try {
    await fn();
  } finally {
    busy.value = false;
  }
}

const send = (settings, typed, clear) => {
  if (props.section === 'sms') return saveSms(accountId.value, settings, typed, clear);
  if (props.section === 'crm') return saveCrm(accountId.value, settings, typed, clear);
  return saveCommerce(accountId.value, settings, typed, clear);
};
const save = () =>
  run(async () => {
    let settings = form.value;
    if (props.section === 'crm') {
      const rows = mapFromRows(mapRows.value);
      settings = { ...form.value, field_map: Object.keys(rows).length ? rows : undefined };
    }
    const r = await send(settings, keys.value, []);
    if (r && r.ok) await load();
    after(r, t('TOLZAR_SETTINGS.R1.SAVED'));
  });
// Remove one saved key: re-sends the SAVED settings (not unsaved edits) with clear_credentials.
const removeKey = f =>
  run(async () => {
    const r = await send(raw.value?.settings || form.value, {}, [f]);
    if (r && r.ok) await load();
    after(r, t('TOLZAR_SETTINGS.CHANNELS.CRED.REMOVED'));
  });
const missingNames = p =>
  (p.missing_credentials || []).map(f => t(credentialLabelKey('sms', form.value?.provider, f))).join(', ');

const smsPreview = () =>
  run(async () => {
    const r = await previewSms(accountId.value, probe.value.to, probe.value.text);
    after(r, '');
    preview.value = r && r.ok ? r : null;
  });
const crmPreview = () =>
  run(async () => {
    const r = await previewCrm(accountId.value, probe.value.contactId);
    after(r, '');
    preview.value = r && r.ok ? r : null;
  });
const catalogue = () =>
  run(async () => {
    const r = await syncCatalogue(accountId.value, form.value.agent_id);
    after(r, t('TOLZAR_SETTINGS.CHANNELS.SYNCED', { n: (r && r.rows) || 0 }));
  });
const order = () =>
  run(async () => {
    const r = await orderStatus(accountId.value, probe.value.order);
    after(r, '');
    preview.value = r && r.ok ? r : null;
  });
const addTemplate = tpl =>
  run(async () => {
    const wf = { ...JSON.parse(JSON.stringify(tpl)), id: `${tpl.id}-${Date.now().toString(36)}`, status: 'draft' };
    const r = (await window.axios.post(`/api/v1/accounts/${accountId.value}/tolzar/workflows`, { workflow: wf })).data;
    after(r, t('TOLZAR_SETTINGS.CHANNELS.TEMPLATE_ADDED'));
  });

const pretty = v => JSON.stringify(v, null, 2);
const summary = r => runSummary(r, resolvedLocale.value);
const zone = () => {
  try {
    return Intl.DateTimeFormat().resolvedOptions().timeZone || 'UTC';
  } catch {
    return 'UTC';
  }
};

// One badge for every section: Shadow while the section is on (it runs and sends nothing), Off
// when it is switched off. The commerce section only reads (catalogue, order status), so it is
// Shadow whenever it is set up. What exactly "nothing is sent" means per section is the hint line.
const state = computed(() => {
  if (props.section === 'commerce') return 'shadow';
  return form.value?.enabled ? 'shadow' : 'off';
});
const detail = computed(() => t(`TOLZAR_SETTINGS_UI.SHADOW_DETAIL.${props.section}`));

onMounted(load);
</script>

<template>
  <div v-if="form">
    <ShadowBadge :state="state" :hint="detail" />
    <p class="mt-1 mb-0 text-xs text-n-slate-10">{{ detail }}</p>

    <!-- SMS -->
    <div v-if="section === 'sms'" class="grid gap-5 mt-2 lg:grid-cols-2">
      <div>
        <label :class="LABEL">{{ t('TOLZAR_SETTINGS.CHANNELS.PROVIDER') }}</label>
        <select v-model="form.provider" :class="INPUT">
          <option v-for="p in SMS_PROVIDERS" :key="p" :value="p">{{ t(`TOLZAR_SETTINGS.CHANNELS.P.${p}`) }}</option>
        </select>
        <label :class="LABEL">{{ t('TOLZAR_SETTINGS.CHANNELS.SMS_FROM') }}</label>
        <input v-model="form.from" :class="INPUT" :placeholder="t('TOLZAR_SETTINGS_UI.CHANNELS.PH.SMS_FROM')" />
        <CredentialInput v-for="f in credFields" :key="f" v-model="keys[f]" :label="credLabel(f)" :status="credStatus(f)" :busy="busy" @remove="removeKey(f)" />
        <label :class="CHECK"><input v-model="form.enabled" type="checkbox" /> {{ t('TOLZAR_SETTINGS.ON_SHADOW') }}</label>
        <p class="mt-2 mb-0 text-xs text-n-slate-10">{{ t('TOLZAR_SETTINGS.CHANNELS.CRED.HINT') }}</p>
        <button type="button" :class="BTN" :disabled="busy" @click="save">{{ t('TOLZAR_SETTINGS.SAVE') }}</button>
      </div>
      <div>
        <h3 class="m-0 text-sm font-semibold text-n-slate-12">{{ t('TOLZAR_SETTINGS.CHANNELS.SMS_PREVIEW') }}</h3>
        <label :class="LABEL">{{ t('TOLZAR_SETTINGS.CHANNELS.SMS_TO') }}</label>
        <input v-model="probe.to" :class="INPUT" :placeholder="t('TOLZAR_SETTINGS_UI.CHANNELS.PH.SMS_TO')" />
        <label :class="LABEL">{{ t('TOLZAR_SETTINGS.CHANNELS.SMS_TEXT') }}</label>
        <textarea v-model="probe.text" rows="3" :class="INPUT" />
        <button type="button" :class="BTN_GHOST" :disabled="busy" @click="smsPreview">{{ t('TOLZAR_SETTINGS.CHANNELS.PREVIEW') }}</button>
        <div v-if="preview" class="mt-3 text-[13px]">
          <p class="m-0">{{ t('TOLZAR_SETTINGS.CHANNELS.WOULD_SEND') }} · {{ t('TOLZAR_SETTINGS.CHANNELS.SEGMENTS', { n: preview.segments.parts, enc: preview.segments.encoding, chars: preview.segments.characters }) }}</p>
          <p v-if="(preview.missing_credentials || []).length" class="m-0 mt-1 text-n-amber-11">{{ t('TOLZAR_SETTINGS.CHANNELS.MISSING', { names: missingNames(preview) }) }}</p>
          <pre class="overflow-auto p-2 mt-2 max-h-[260px] text-xs rounded bg-n-alpha-1">{{ pretty(preview.request) }}</pre>
        </div>
      </div>
    </div>

    <!-- CRM sync -->
    <div v-if="section === 'crm'" class="mt-2">
      <div class="grid gap-5 lg:grid-cols-2">
        <div>
          <label :class="LABEL">{{ t('TOLZAR_SETTINGS.CHANNELS.PROVIDER') }}</label>
          <select v-model="form.provider" :class="INPUT" @change="fillMap">
            <option v-for="p in CRM_PROVIDERS" :key="p" :value="p">{{ t(`TOLZAR_SETTINGS.CHANNELS.P.${p}`) }}</option>
          </select>
          <CredentialInput v-for="f in credFields" :key="f" v-model="keys[f]" :label="credLabel(f)" :status="credStatus(f)" :busy="busy" @remove="removeKey(f)" />
          <template v-if="form.provider === 'zoho'">
            <label :class="LABEL">{{ t('TOLZAR_SETTINGS.CHANNELS.ZOHO_DOMAIN') }}</label>
            <input v-model="form.api_domain" :class="INPUT" :placeholder="t('TOLZAR_SETTINGS_UI.CHANNELS.PH.ZOHO_DOMAIN')" />
          </template>
          <label :class="LABEL">{{ t('TOLZAR_SETTINGS.CHANNELS.DIRECTION') }}</label>
          <select v-model="form.direction" :class="INPUT">
            <option v-for="d in CRM_DIRECTIONS" :key="d" :value="d">{{ t(`TOLZAR_SETTINGS.CHANNELS.DIR.${d}`) }}</option>
          </select>
          <p class="mt-1 text-xs text-n-slate-10">{{ t('TOLZAR_SETTINGS.CHANNELS.CONFLICT_RULE') }}</p>
          <label :class="CHECK"><input v-model="form.read_crm" type="checkbox" /> {{ t('TOLZAR_SETTINGS.CHANNELS.READ_CRM') }}</label>
          <label :class="CHECK"><input v-model="form.enabled" type="checkbox" /> {{ t('TOLZAR_SETTINGS.CHANNELS.HOURLY_DRY_RUN') }}</label>
          <p class="mt-2 mb-0 text-xs text-n-slate-10">{{ t('TOLZAR_SETTINGS.CHANNELS.CRED.HINT') }}</p>
        </div>
        <div>
          <h3 class="m-0 text-sm font-semibold text-n-slate-12">{{ t('TOLZAR_SETTINGS.CHANNELS.MAPPING') }}</h3>
          <div v-for="r in mapRows" :key="r.field" class="flex gap-2 items-center mt-1.5">
            <span class="w-[150px] text-[13px] text-n-slate-11">{{ t(`TOLZAR_SETTINGS.CHANNELS.FIELD.${r.field}`) }}</span>
            <input v-model="r.crm" :class="INPUT" :placeholder="r.placeholder" spellcheck="false" />
          </div>
          <p class="mt-1 text-xs text-n-slate-10">{{ t('TOLZAR_SETTINGS.CHANNELS.MAPPING_HINT') }}</p>
        </div>
      </div>
      <button type="button" :class="BTN" :disabled="busy" @click="save">{{ t('TOLZAR_SETTINGS.SAVE') }}</button>

      <h3 class="mt-6 mb-0 text-sm font-semibold text-n-slate-12">{{ t('TOLZAR_SETTINGS.CHANNELS.CRM_PREVIEW') }}</h3>
      <div class="flex gap-2 items-end max-w-[420px]">
        <input v-model="probe.contactId" inputmode="numeric" :class="INPUT" :placeholder="t('TOLZAR_SETTINGS.TRUST.CONTACT_ID')" />
        <button type="button" :class="BTN_GHOST" :disabled="busy" @click="crmPreview">{{ t('TOLZAR_SETTINGS.CHANNELS.PREVIEW') }}</button>
      </div>
      <div v-if="preview" class="grid gap-2 mt-3 text-[13px] md:grid-cols-2">
        <div class="p-2 rounded-lg bg-n-alpha-1">
          <div class="text-xs font-semibold text-n-slate-11">{{ t('TOLZAR_SETTINGS.CHANNELS.WOULD_PUSH') }}</div>
          <pre class="m-0 text-xs whitespace-pre-wrap">{{ pretty(preview.would_push) }}</pre>
        </div>
        <div class="p-2 rounded-lg bg-n-alpha-1">
          <div class="text-xs font-semibold text-n-slate-11">{{ t('TOLZAR_SETTINGS.CHANNELS.WOULD_PULL') }}</div>
          <pre class="m-0 text-xs whitespace-pre-wrap">{{ preview.would_pull === null ? t('TOLZAR_SETTINGS.CHANNELS.NOT_READ') : pretty(preview.would_pull) }}</pre>
        </div>
        <pre v-if="preview.would_send" class="overflow-auto p-2 m-0 max-h-[240px] text-xs rounded bg-n-alpha-1 md:col-span-2">{{ pretty(preview.would_send) }}</pre>
        <p v-if="preview.note || preview.error" class="m-0 text-xs text-n-amber-11 md:col-span-2">{{ preview.note || preview.error }}</p>
      </div>

      <h3 class="mt-6 mb-1 text-sm font-semibold text-n-slate-12">{{ t('TOLZAR_SETTINGS.CHANNELS.RUNS') }}</h3>
      <div v-for="(r, i) in runs" :key="r.at" class="py-2 border-t border-solid border-n-weak text-[13px]">
        <button type="button" class="flex flex-wrap gap-3 justify-between w-full text-start" :aria-expanded="openRun === i" @click="openRun = openRun === i ? null : i">
          <span class="text-n-slate-10">{{ summary(r).at }}</span>
          <span>{{ t('TOLZAR_SETTINGS.CHANNELS.RUN_LINE', { checked: summary(r).checked, changes: summary(r).changes }) }}</span>
          <span class="text-xs text-n-slate-10">{{ summary(r).crmRead ? t('TOLZAR_SETTINGS.CHANNELS.CRM_READ') : t('TOLZAR_SETTINGS.CHANNELS.CRM_NOT_READ') }}</span>
        </button>
        <pre v-if="openRun === i" class="overflow-auto p-2 mt-2 max-h-[260px] text-xs rounded bg-n-alpha-1">{{ pretty(r.changes) }}</pre>
      </div>
      <p v-if="runs.length" class="mt-1 text-xs text-n-slate-10">{{ t('TOLZAR_UI.YOUR_TIME_ZONE', { zone: zone() }) }}</p>
      <p v-if="!runs.length" class="text-n-slate-10 text-[13px]">{{ t('TOLZAR_SETTINGS.NONE_YET') }}</p>
    </div>

    <!-- Commerce -->
    <div v-if="section === 'commerce'" class="mt-2">
      <div class="grid gap-5 lg:grid-cols-2">
        <div>
          <label :class="LABEL">{{ t('TOLZAR_SETTINGS.CHANNELS.PROVIDER') }}</label>
          <select v-model="form.provider" :class="INPUT">
            <option v-for="p in SHOP_PROVIDERS" :key="p" :value="p">{{ t(`TOLZAR_SETTINGS.CHANNELS.P.${p}`) }}</option>
          </select>
          <label :class="LABEL">{{ t('TOLZAR_SETTINGS.CHANNELS.SHOP_DOMAIN') }}</label>
          <input v-model="form.shop_domain" :class="INPUT" :placeholder="t('TOLZAR_SETTINGS_UI.CHANNELS.PH.SHOP_DOMAIN')" />
          <label :class="LABEL">{{ t('TOLZAR_SETTINGS.CHANNELS.CURRENCY') }}</label>
          <input v-model="form.currency" maxlength="3" :class="INPUT" :placeholder="t('TOLZAR_SETTINGS_UI.CHANNELS.PH.CURRENCY')" />
          <CredentialInput v-for="f in credFields" :key="f" v-model="keys[f]" :label="credLabel(f)" :status="credStatus(f)" :busy="busy" @remove="removeKey(f)" />
          <label :class="LABEL">{{ t('TOLZAR_SETTINGS.CHANNELS.PRICE_AGENT') }}</label>
          <select v-model="form.agent_id" :class="INPUT">
            <option value="">—</option>
            <option v-for="a in agents" :key="a.id" :value="a.id">{{ a.name }}</option>
          </select>
          <label :class="CHECK"><input v-model="form.catalogue_auto" type="checkbox" /> {{ t('TOLZAR_SETTINGS.CHANNELS.CATALOGUE_DAILY') }}</label>
          <label :class="CHECK"><input v-model="form.order_chat" type="checkbox" /> {{ t('TOLZAR_SETTINGS.CHANNELS.ORDER_CHAT') }}</label>
          <p class="mt-1 mb-0 text-xs text-n-slate-10">{{ t('TOLZAR_SETTINGS.CHANNELS.ORDER_CHAT_HINT') }}</p>
          <label :class="LABEL">{{ t('TOLZAR_SETTINGS.CHANNELS.ORDER_CHANNELS') }}</label>
          <div class="flex flex-wrap gap-1.5" data-tz-order-channels>
            <button
              v-for="c in ORDER_CHAT_CHANNELS"
              :key="c"
              type="button"
              class="px-2 py-0.5 text-xs rounded-full border transition-colors"
              :class="pickedChannel(c) ? (c === WIDGET_CHANNEL ? 'text-white border-transparent bg-n-ruby-9' : 'text-white border-transparent bg-n-brand') : 'border-n-weak text-n-slate-11 hover:bg-n-alpha-2'"
              :aria-pressed="pickedChannel(c)"
              @click="toggleChannel(c)"
            >
              {{ t(channelLabelKey(c)) }}
            </button>
          </div>
          <p class="mt-1 mb-0 text-xs text-n-slate-10">{{ t('TOLZAR_SETTINGS.CHANNELS.ORDER_CHANNELS_HINT') }}</p>
          <!-- each picked channel with the state it runs in: Shadow while order chat is on, Off otherwise -->
          <ul v-if="(form.order_chat_channels || []).length" class="ps-0 mt-1.5 mb-0 list-none text-xs" data-tz-order-channel-states>
            <li v-for="c in form.order_chat_channels" :key="c" class="flex gap-2 items-center py-0.5">
              <span class="text-n-slate-11">{{ t(channelLabelKey(c)) }}</span>
              <ShadowBadge :state="form.order_chat ? 'shadow' : 'off'" :hint="t('TOLZAR_SETTINGS_UI.SHADOW_DETAIL.order_chat')" />
            </li>
          </ul>
          <p v-if="form.order_chat && !(form.order_chat_channels || []).length" class="mt-1 mb-0 text-xs text-n-amber-11">{{ t('TOLZAR_SETTINGS.CHANNELS.ORDER_CHANNELS_NONE') }}</p>
          <p v-if="pickedChannel(WIDGET_CHANNEL)" class="px-2.5 py-2 mt-1.5 mb-0 text-xs font-semibold rounded-lg border border-solid border-n-ruby-6" :class="TONE_BAD" role="alert" data-tz-widget-warning>
            {{ t('TOLZAR_SETTINGS.CHANNELS.WIDGET_WARNING') }}
          </p>
          <label :class="LABEL">{{ t('TOLZAR_SETTINGS.CHANNELS.TRACKING_HOSTS') }}</label>
          <input :value="hostsText" :class="INPUT" :placeholder="t('TOLZAR_SETTINGS_UI.CHANNELS.PH.TRACKING_HOSTS')" spellcheck="false" @input="setHosts($event.target.value)" />
          <p class="mt-1 mb-0 text-xs text-n-slate-10">{{ t('TOLZAR_SETTINGS.CHANNELS.TRACKING_HOSTS_HINT', { max: TRACKING_HOSTS_MAX }) }}</p>
          <label :class="LABEL">{{ t('TOLZAR_SETTINGS.CHANNELS.ORDER_PATTERN') }}</label>
          <input v-model="form.order_pattern" :maxlength="ORDER_PATTERN_MAX" :class="INPUT" :placeholder="t('TOLZAR_SETTINGS_UI.CHANNELS.PH.ORDER_PATTERN')" spellcheck="false" />
          <p class="mt-1 mb-0 text-xs text-n-slate-10">{{ t('TOLZAR_SETTINGS.CHANNELS.ORDER_PATTERN_HINT') }}</p>
          <label :class="LABEL">{{ t('TOLZAR_SETTINGS.CHANNELS.ORDER_LOOKUPS') }}</label>
          <input v-model.number="form.order_lookups_per_day" type="number" min="0" max="100000" step="1" :class="INPUT" />
          <p class="mt-2 mb-0 text-xs text-n-slate-10">{{ t('TOLZAR_SETTINGS.CHANNELS.CRED.HINT') }}</p>
          <div class="flex flex-wrap gap-2">
            <button type="button" :class="BTN" :disabled="busy" @click="save">{{ t('TOLZAR_SETTINGS.SAVE') }}</button>
            <button type="button" :class="BTN_GHOST" :disabled="busy || !form.agent_id" @click="catalogue">{{ t('TOLZAR_SETTINGS.CHANNELS.SYNC_NOW') }}</button>
          </div>
        </div>
        <div>
          <h3 class="m-0 text-sm font-semibold text-n-slate-12">{{ t('TOLZAR_SETTINGS.CHANNELS.ORDER_STATUS') }}</h3>
          <p class="mt-1 text-xs text-n-slate-10">{{ t('TOLZAR_SETTINGS.CHANNELS.ORDER_HINT') }}</p>
          <div class="flex gap-2 items-end">
            <input v-model="probe.order" :class="INPUT" :placeholder="t('TOLZAR_SETTINGS_UI.CHANNELS.PH.ORDER_NUMBER')" :aria-label="t('TOLZAR_SETTINGS.CHANNELS.ORDER_STATUS')" />
            <button type="button" :class="BTN_GHOST" :disabled="busy" @click="order">{{ t('TOLZAR_SETTINGS.CHANNELS.LOOK_UP') }}</button>
          </div>
          <pre v-if="preview" class="overflow-auto p-2 mt-3 max-h-[260px] text-xs rounded bg-n-alpha-1">{{ pretty(preview) }}</pre>
          <h3 class="mt-6 mb-1 text-sm font-semibold text-n-slate-12">{{ t('TOLZAR_SETTINGS.CHANNELS.TEMPLATES') }}</h3>
          <div v-for="tpl in templates" :key="tpl.id" class="flex flex-wrap gap-2 justify-between items-center py-2 border-t border-solid border-n-weak text-[13px]">
            <span>{{ tpl.name }}</span>
            <button type="button" :class="BTN_GHOST" class="!mt-0 !h-7" :disabled="busy" @click="addTemplate(tpl)">{{ t('TOLZAR_SETTINGS.CHANNELS.ADD_DRAFT') }}</button>
          </div>
        </div>
      </div>
    </div>
    <BrainNotice :result="result" :saved="saved" />
  </div>
</template>
