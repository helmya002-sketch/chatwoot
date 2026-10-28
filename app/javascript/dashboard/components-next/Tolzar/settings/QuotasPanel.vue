<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import BrainNotice from './BrainNotice.vue';
import { BTN, INPUT, LABEL } from './tzClasses';
import { QUOTA_LIMITS, getQuotas, saveQuotas, quotaRows } from '../tolzarUsage';

// Settings hub → Usage: model quotas (calls per day, tokens per month, in the timezone the brain
// reports). Over a limit the AI uses the workspace's safe template, like any budget stop.
const { t } = useI18n();
const accountId = useMapGetter('getCurrentAccountId');

const status = ref(null);
const form = ref({});
const result = ref(null);
const saved = ref('');
const busy = ref(false);
const rows = computed(() => quotaRows(status.value));

function apply(s) {
  status.value = s;
  form.value = Object.fromEntries(QUOTA_LIMITS.map(k => [k, s?.quota?.[k] ?? '']));
}
async function load() {
  apply(await getQuotas(accountId.value));
}
async function save() {
  busy.value = true;
  try {
    const r = await saveQuotas(accountId.value, form.value);
    result.value = r;
    saved.value = r && r.ok ? t('TOLZAR_SETTINGS.R1.SAVED') : '';
    if (r && r.ok) apply(r);
  } finally {
    busy.value = false;
  }
}
const fmt = v => (v === null || v === undefined ? '∞' : Number(v).toLocaleString());

onMounted(load);
</script>

<template>
  <div v-if="status" class="mt-6">
    <h3 class="m-0 text-sm font-semibold text-n-slate-12">{{ t('TOLZAR_SETTINGS.QUOTAS.TITLE') }}</h3>
    <p class="mt-1 text-xs text-n-slate-10">{{ t('TOLZAR_SETTINGS.QUOTAS.HINT', { day: status.period?.day || '', month: status.period?.month || '', tz: status.period?.timezone || 'UTC' }) }}</p>
    <div class="grid gap-3 md:grid-cols-2">
      <div v-for="r in rows" :key="r.key" class="p-3 rounded-lg border border-solid border-n-weak">
        <div class="text-xs text-n-slate-10">{{ t(`TOLZAR_SETTINGS.QUOTAS.${r.key}`) }}</div>
        <div class="mt-1 text-xl font-bold text-n-slate-12">{{ fmt(r.used) }} <span class="text-sm font-normal text-n-slate-10">/ {{ fmt(r.limit) }}</span></div>
        <div class="overflow-hidden mt-2 h-1.5 rounded bg-n-alpha-2">
          <div v-if="r.share !== null" class="h-full" :class="r.reached ? 'bg-n-ruby-9' : 'bg-n-brand'" :style="{ width: `${Math.round(r.share * 100)}%` }" />
        </div>
        <div class="mt-1 text-xs" :class="r.reached ? 'text-n-ruby-11' : 'text-n-slate-11'">
          {{ r.limit === null ? t('TOLZAR_SETTINGS.QUOTAS.UNLIMITED') : r.reached ? t('TOLZAR_SETTINGS.QUOTAS.REACHED') : t('TOLZAR_SETTINGS.QUOTAS.REMAINING', { n: fmt(r.remaining) }) }}
        </div>
        <label :class="LABEL">{{ t('TOLZAR_SETTINGS.QUOTAS.LIMIT') }}</label>
        <input v-model="form[r.key]" type="number" min="0" :class="INPUT" :placeholder="t('TOLZAR_SETTINGS.QUOTAS.EMPTY_UNLIMITED')" />
      </div>
    </div>
    <button type="button" :class="BTN" :disabled="busy" @click="save">{{ t('TOLZAR_SETTINGS.SAVE') }}</button>
    <BrainNotice :result="result" :saved="saved" />
  </div>
</template>
