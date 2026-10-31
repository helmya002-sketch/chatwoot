<script setup>
import { ref, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { INPUT, LABEL } from './tzClasses';

// Settings hub → Growth → Lead sources (Tolzar::LeadSources): leads per source and campaign, and how many were won
// or lost, from lead forms and ad clicks. Ad spend and cost per lead join when the ad platforms' reports connect.
const { t } = useI18n();
const accountId = useMapGetter('getCurrentAccountId');
const DAYS = [7, 30, 90, 365];

const days = ref(90);
const rows = ref([]);
const loading = ref(true);
const error = ref('');

async function load() {
  loading.value = true;
  error.value = '';
  try {
    const { data } = await window.axios.get(
      `/api/v1/accounts/${accountId.value}/tolzar/lead_sources`,
      { params: { days: days.value } }
    );
    rows.value = data.rows || [];
  } catch {
    error.value = t('TOLZAR_SETTINGS_UI.LEAD_SOURCES.FAILED');
  } finally {
    loading.value = false;
  }
}

const rate = row =>
  row.leads ? `${Math.round((100 * row.won) / row.leads)}%` : '–';

onMounted(load);
</script>

<template>
  <div class="max-w-[760px]">
    <p class="mt-0 mb-0 text-[13px] text-n-slate-11">
      {{ t('TOLZAR_SETTINGS_UI.LEAD_SOURCES.WHAT') }}
    </p>
    <label :class="LABEL" for="tz-lead-sources-days">
      {{ t('TOLZAR_SETTINGS_UI.LEAD_SOURCES.PERIOD') }}
    </label>
    <select
      id="tz-lead-sources-days"
      v-model.number="days"
      :class="INPUT"
      class="!w-48"
      @change="load"
    >
      <option v-for="d in DAYS" :key="d" :value="d">
        {{ t('TOLZAR_SETTINGS_UI.LEAD_SOURCES.DAYS', { n: d }) }}
      </option>
    </select>
    <p v-if="loading" class="mt-3 text-[13px] text-n-slate-11">
      {{ t('TOLZAR_SETTINGS_UI.LEAD_INTAKE.LOADING') }}
    </p>
    <p v-else-if="error" class="mt-3 text-[13px] text-n-ruby-11" role="alert">
      {{ error }}
    </p>
    <p v-else-if="!rows.length" class="mt-3 text-[13px] text-n-slate-11">
      {{ t('TOLZAR_SETTINGS_UI.LEAD_SOURCES.EMPTY') }}
    </p>
    <table v-else class="mt-3 w-full text-[13px] text-start">
      <thead class="text-xs text-n-slate-11">
        <tr class="border-b border-n-weak">
          <th class="py-2 pe-3 text-start font-medium">
            {{ t('TOLZAR_SETTINGS_UI.LEAD_SOURCES.SOURCE') }}
          </th>
          <th class="py-2 pe-3 text-start font-medium">
            {{ t('TOLZAR_SETTINGS_UI.LEAD_SOURCES.CAMPAIGN') }}
          </th>
          <th class="py-2 pe-3 text-end font-medium">
            {{ t('TOLZAR_SETTINGS_UI.LEAD_SOURCES.LEADS') }}
          </th>
          <th class="py-2 pe-3 text-end font-medium">
            {{ t('TOLZAR_SETTINGS_UI.LEAD_SOURCES.WON') }}
          </th>
          <th class="py-2 pe-3 text-end font-medium">
            {{ t('TOLZAR_SETTINGS_UI.LEAD_SOURCES.LOST') }}
          </th>
          <th class="py-2 text-end font-medium">
            {{ t('TOLZAR_SETTINGS_UI.LEAD_SOURCES.WIN_RATE') }}
          </th>
        </tr>
      </thead>
      <tbody class="text-n-slate-12">
        <tr
          v-for="row in rows"
          :key="`${row.source}|${row.campaign}`"
          class="border-b border-n-weak"
        >
          <td class="py-2 pe-3">{{ row.source }}</td>
          <td class="py-2 pe-3 text-n-slate-11">{{ row.campaign || '–' }}</td>
          <td class="py-2 pe-3 text-end tabular-nums">{{ row.leads }}</td>
          <td class="py-2 pe-3 text-end tabular-nums">{{ row.won }}</td>
          <td class="py-2 pe-3 text-end tabular-nums">{{ row.lost }}</td>
          <td class="py-2 text-end tabular-nums">{{ rate(row) }}</td>
        </tr>
      </tbody>
    </table>
    <p class="mt-3 mb-0 text-xs text-n-slate-10">
      {{ t('TOLZAR_SETTINGS_UI.LEAD_SOURCES.SPEND_LATER') }}
    </p>
  </div>
</template>
