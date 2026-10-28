<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import BrainNotice from './BrainNotice.vue';
import EnvStatus from './EnvStatus.vue';
import { BTN, BTN_GHOST, INPUT, LABEL, CHECK, SHADOW_BADGE } from './tzClasses';
import {
  SMS_PROVIDERS,
  SMS_ENV,
  CRM_PROVIDERS,
  CRM_DIRECTIONS,
  SHOP_PROVIDERS,
  SHOP_ENV,
  getSms,
  saveSms,
  previewSms,
  smsEnvRows,
  getCrm,
  saveCrm,
  crmRuns,
  previewCrm,
  crmEnvRows,
  crmMapRows,
  mapFromRows,
  runSummary,
  getCommerce,
  saveCommerce,
  syncCatalogue,
  orderStatus,
  commerceTemplates,
  commerceEnvRows,
} from '../tolzarChannels';

// Settings hub → Channels: SMS fallback, CRM sync, Commerce. Shadow / dry run only: Tolzar
// shows the exact request it WOULD send; keys stay in the server's environment.
const props = defineProps({
  section: { type: String, required: true }, // sms | crm | commerce
});
const { t } = useI18n();
const accountId = useMapGetter('getCurrentAccountId');

const raw = ref(null); // the brain's GET answer (for env presence)
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

const envRowsNow = computed(() => {
  if (!raw.value) return [];
  if (props.section === 'sms') return smsEnvRows(raw.value);
  if (props.section === 'crm') return crmEnvRows(raw.value);
  return commerceEnvRows(raw.value);
});
const smsFields = computed(() => SMS_ENV[form.value?.provider] || ['key_env']);
const shopFields = computed(() => SHOP_ENV[form.value?.provider] || ['key_env']);

async function load() {
  result.value = null;
  saved.value = '';
  preview.value = null;
  if (props.section === 'sms') {
    raw.value = await getSms(accountId.value);
    form.value = { provider: 'twilio', from: '', key_env: '', account_sid_env: '', enabled: false, ...(raw.value.settings || {}) };
  } else if (props.section === 'crm') {
    const [c, r] = await Promise.all([getCrm(accountId.value), crmRuns(accountId.value)]);
    raw.value = c;
    form.value = { provider: 'hubspot', key_env: '', direction: 'to_crm', read_crm: false, enabled: false, stage_map: {}, ...(c.settings || {}) };
    runs.value = r.runs || [];
    fillMap();
  } else {
    const [c, a, tp] = await Promise.all([
      getCommerce(accountId.value),
      window.axios.get(`/api/v1/accounts/${accountId.value}/tolzar/agents`).then(x => x.data),
      commerceTemplates(accountId.value),
    ]);
    raw.value = c;
    form.value = { provider: 'shopify', shop_domain: '', currency: '', key_env: '', secret_env: '', agent_id: '', catalogue_auto: false, ...(c.settings || {}) };
    agents.value = a.agents || [];
    templates.value = tp.templates || [];
  }
}

function fillMap() {
  const d = raw.value || {};
  const stored = (d.settings || {}).provider === form.value.provider ? (d.settings || {}).field_map : null;
  mapRows.value = crmMapRows(d.fields, stored, (d.default_maps || {})[form.value.provider]);
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

const save = () =>
  run(async () => {
    let r;
    if (props.section === 'sms') r = await saveSms(accountId.value, form.value);
    if (props.section === 'crm') {
      const rows = mapFromRows(mapRows.value);
      r = await saveCrm(accountId.value, { ...form.value, field_map: Object.keys(rows).length ? rows : undefined });
    }
    if (props.section === 'commerce') r = await saveCommerce(accountId.value, form.value);
    if (r && r.ok) await load();
    after(r, t('TOLZAR_SETTINGS.R1.SAVED'));
  });

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

onMounted(load);
</script>

<template>
  <div v-if="form">
    <span :class="SHADOW_BADGE">{{ t('TOLZAR_SETTINGS.R1.SHADOW_ONLY') }}</span>

    <!-- SMS -->
    <div v-if="section === 'sms'" class="grid gap-5 mt-2 lg:grid-cols-2">
      <div>
        <label :class="LABEL">{{ t('TOLZAR_SETTINGS.CHANNELS.PROVIDER') }}</label>
        <select v-model="form.provider" :class="INPUT">
          <option v-for="p in SMS_PROVIDERS" :key="p" :value="p">{{ t(`TOLZAR_SETTINGS.CHANNELS.P.${p}`) }}</option>
        </select>
        <label :class="LABEL">{{ t('TOLZAR_SETTINGS.CHANNELS.SMS_FROM') }}</label>
        <input v-model="form.from" :class="INPUT" placeholder="+4917012345678" />
        <template v-for="f in smsFields" :key="f">
          <label :class="LABEL">{{ t(`TOLZAR_SETTINGS.CHANNELS.ENV.${form.provider}_${f}`) }}</label>
          <input v-model="form[f]" :class="INPUT" placeholder="ACME_SMS_KEY" spellcheck="false" />
        </template>
        <label :class="CHECK"><input v-model="form.enabled" type="checkbox" /> {{ t('TOLZAR_SETTINGS.ON_SHADOW') }}</label>
        <EnvStatus :rows="envRowsNow" />
        <button type="button" :class="BTN" :disabled="busy" @click="save">{{ t('TOLZAR_SETTINGS.SAVE') }}</button>
      </div>
      <div>
        <h3 class="m-0 text-sm font-semibold text-n-slate-12">{{ t('TOLZAR_SETTINGS.CHANNELS.SMS_PREVIEW') }}</h3>
        <label :class="LABEL">{{ t('TOLZAR_SETTINGS.CHANNELS.SMS_TO') }}</label>
        <input v-model="probe.to" :class="INPUT" placeholder="+49 170 1234567" />
        <label :class="LABEL">{{ t('TOLZAR_SETTINGS.CHANNELS.SMS_TEXT') }}</label>
        <textarea v-model="probe.text" rows="3" :class="INPUT" />
        <button type="button" :class="BTN_GHOST" :disabled="busy" @click="smsPreview">{{ t('TOLZAR_SETTINGS.CHANNELS.PREVIEW') }}</button>
        <div v-if="preview" class="mt-3 text-[13px]">
          <p class="m-0">{{ t('TOLZAR_SETTINGS.CHANNELS.WOULD_SEND') }} · {{ t('TOLZAR_SETTINGS.CHANNELS.SEGMENTS', { n: preview.segments.parts, enc: preview.segments.encoding, chars: preview.segments.characters }) }}</p>
          <p v-if="(preview.missing_env || []).length" class="m-0 mt-1 text-amber-700">{{ t('TOLZAR_SETTINGS.CHANNELS.MISSING', { names: preview.missing_env.join(', ') }) }}</p>
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
          <label :class="LABEL">{{ t('TOLZAR_SETTINGS.CHANNELS.ENV.crm_key_env') }}</label>
          <input v-model="form.key_env" :class="INPUT" placeholder="HUBSPOT_TOKEN" spellcheck="false" />
          <template v-if="form.provider === 'zoho'">
            <label :class="LABEL">{{ t('TOLZAR_SETTINGS.CHANNELS.ZOHO_DOMAIN') }}</label>
            <input v-model="form.api_domain" :class="INPUT" placeholder="https://www.zohoapis.eu" />
          </template>
          <label :class="LABEL">{{ t('TOLZAR_SETTINGS.CHANNELS.DIRECTION') }}</label>
          <select v-model="form.direction" :class="INPUT">
            <option v-for="d in CRM_DIRECTIONS" :key="d" :value="d">{{ t(`TOLZAR_SETTINGS.CHANNELS.DIR.${d}`) }}</option>
          </select>
          <p class="mt-1 text-xs text-n-slate-10">{{ t('TOLZAR_SETTINGS.CHANNELS.CONFLICT_RULE') }}</p>
          <label :class="CHECK"><input v-model="form.read_crm" type="checkbox" /> {{ t('TOLZAR_SETTINGS.CHANNELS.READ_CRM') }}</label>
          <label :class="CHECK"><input v-model="form.enabled" type="checkbox" /> {{ t('TOLZAR_SETTINGS.CHANNELS.HOURLY_DRY_RUN') }}</label>
          <EnvStatus :rows="envRowsNow" />
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
        <p v-if="preview.note || preview.error" class="m-0 text-xs text-amber-700 md:col-span-2">{{ preview.note || preview.error }}</p>
      </div>

      <h3 class="mt-6 mb-1 text-sm font-semibold text-n-slate-12">{{ t('TOLZAR_SETTINGS.CHANNELS.RUNS') }}</h3>
      <div v-for="(r, i) in runs" :key="r.at" class="py-2 border-t border-solid border-n-weak text-[13px]">
        <button type="button" class="flex flex-wrap gap-3 justify-between w-full text-left" @click="openRun = openRun === i ? null : i">
          <span class="text-n-slate-10">{{ runSummary(r).at }}</span>
          <span>{{ t('TOLZAR_SETTINGS.CHANNELS.RUN_LINE', { checked: runSummary(r).checked, changes: runSummary(r).changes }) }}</span>
          <span class="text-xs text-n-slate-10">{{ runSummary(r).crmRead ? t('TOLZAR_SETTINGS.CHANNELS.CRM_READ') : t('TOLZAR_SETTINGS.CHANNELS.CRM_NOT_READ') }}</span>
        </button>
        <pre v-if="openRun === i" class="overflow-auto p-2 mt-2 max-h-[260px] text-xs rounded bg-n-alpha-1">{{ pretty(r.changes) }}</pre>
      </div>
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
          <input v-model="form.shop_domain" :class="INPUT" placeholder="myshop.myshopify.com" />
          <label :class="LABEL">{{ t('TOLZAR_SETTINGS.CHANNELS.CURRENCY') }}</label>
          <input v-model="form.currency" maxlength="3" :class="INPUT" placeholder="EUR" />
          <template v-for="f in shopFields" :key="f">
            <label :class="LABEL">{{ t(`TOLZAR_SETTINGS.CHANNELS.ENV.shop_${f}`) }}</label>
            <input v-model="form[f]" :class="INPUT" placeholder="SHOP_API_KEY" spellcheck="false" />
          </template>
          <label :class="LABEL">{{ t('TOLZAR_SETTINGS.CHANNELS.PRICE_AGENT') }}</label>
          <select v-model="form.agent_id" :class="INPUT">
            <option value="">—</option>
            <option v-for="a in agents" :key="a.id" :value="a.id">{{ a.name }}</option>
          </select>
          <label :class="CHECK"><input v-model="form.catalogue_auto" type="checkbox" /> {{ t('TOLZAR_SETTINGS.CHANNELS.CATALOGUE_DAILY') }}</label>
          <EnvStatus :rows="envRowsNow" />
          <div class="flex flex-wrap gap-2">
            <button type="button" :class="BTN" :disabled="busy" @click="save">{{ t('TOLZAR_SETTINGS.SAVE') }}</button>
            <button type="button" :class="BTN_GHOST" :disabled="busy || !form.agent_id" @click="catalogue">{{ t('TOLZAR_SETTINGS.CHANNELS.SYNC_NOW') }}</button>
          </div>
        </div>
        <div>
          <h3 class="m-0 text-sm font-semibold text-n-slate-12">{{ t('TOLZAR_SETTINGS.CHANNELS.ORDER_STATUS') }}</h3>
          <p class="mt-1 text-xs text-n-slate-10">{{ t('TOLZAR_SETTINGS.CHANNELS.ORDER_HINT') }}</p>
          <div class="flex gap-2 items-end">
            <input v-model="probe.order" :class="INPUT" placeholder="1001" />
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
