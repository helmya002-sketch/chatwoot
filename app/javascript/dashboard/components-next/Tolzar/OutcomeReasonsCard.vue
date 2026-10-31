<script setup>
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';

// Reports → Results → Why deals were won or lost (round 4, c95; Tolzar::OutcomeReasons): the reasons the team
// picks on the Pipeline board, over 7 / 30 / 90 days. Administrators; hidden when the workspace has it off (404).
const { t } = useI18n();
const accountId = useMapGetter('getCurrentAccountId');
const days = ref(30);
const report = ref(null);
const DAYS = [7, 30, 90];

async function load() {
  try {
    const { data } = await window.axios.get(
      `/api/v1/accounts/${accountId.value}/tolzar/outcome_reasons`,
      { params: { days: days.value } }
    );
    report.value = data;
  } catch {
    report.value = null;
  }
}

const groups = computed(() =>
  ['won', 'lost'].map(outcome => ({
    outcome,
    rows: (report.value?.reasons || []).filter(r => r.outcome === outcome),
  }))
);

watch(days, load, { immediate: true });
</script>

<template>
  <section
    v-if="report"
    class="p-4 mt-6 rounded-xl border border-solid border-n-weak bg-n-solid-1"
  >
    <div class="flex flex-wrap gap-2 justify-between items-center">
      <h2 class="m-0 text-sm font-semibold text-n-slate-12">
        {{ t('TOLZAR_RESULTS_UI.OUTCOMES.TITLE') }}
      </h2>
      <div class="flex gap-1" role="group">
        <button
          v-for="d in DAYS"
          :key="d"
          type="button"
          class="px-2 py-0.5 text-xs rounded-md border border-solid border-n-weak"
          :class="
            d === days
              ? 'bg-n-slate-12 text-n-solid-1'
              : 'bg-n-solid-2 text-n-slate-12'
          "
          :aria-pressed="d === days"
          @click="days = d"
        >
          {{ t('TOLZAR_RESULTS_UI.BOOKINGS.DAYS', { n: d }) }}
        </button>
      </div>
    </div>
    <div class="grid gap-4 mt-3 md:grid-cols-2">
      <div v-for="g in groups" :key="g.outcome">
        <h3 class="m-0 text-xs font-semibold text-n-slate-11 uppercase">
          {{ t(`TOLZAR_RESULTS_UI.OUTCOMES.${g.outcome}`) }}
        </h3>
        <p v-if="!g.rows.length" class="mt-1 mb-0 text-[13px] text-n-slate-10">
          {{ t('TOLZAR_RESULTS_UI.OUTCOMES.NONE') }}
        </p>
        <ul v-else class="m-0 mt-1 p-0 list-none flex flex-col gap-1">
          <li
            v-for="r in g.rows"
            :key="r.reason"
            class="flex justify-between text-[13px] text-n-slate-12"
          >
            <span>{{ t(`TOLZAR_CONTACTS.STAGES.REASON.${r.reason}`) }}</span>
            <b class="tabular-nums">{{ r.count }}</b>
          </li>
        </ul>
      </div>
    </div>
  </section>
</template>
