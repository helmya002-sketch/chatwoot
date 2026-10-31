<script setup>
import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { duration } from 'dashboard/components-next/Tolzar/tolzarTime';

// Reports → Results → Team (round 4, c96; Tolzar::TeamLeaderboard): replies, median first reply, resolved and
// rating per person over 7 / 30 / 90 days. Administrators; hidden when the workspace has it off (404).
const { t, locale } = useI18n();
const accountId = useMapGetter('getCurrentAccountId');
const days = ref(30);
const report = ref(null);
const DAYS = [7, 30, 90];

async function load() {
  try {
    const { data } = await window.axios.get(
      `/api/v1/accounts/${accountId.value}/tolzar/team_leaderboard`,
      { params: { days: days.value } }
    );
    report.value = data;
  } catch {
    report.value = null;
  }
}

const firstReply = s => (s == null ? '—' : duration(s, locale.value) || '—');
const rating = c =>
  c ? t('TOLZAR_RESULTS_UI.TEAM.CSAT_N', { avg: c.average, n: c.count }) : '—';

watch(days, load, { immediate: true });
</script>

<template>
  <section
    v-if="report"
    class="p-4 mt-6 rounded-xl border border-solid border-n-weak bg-n-solid-1"
  >
    <div class="flex flex-wrap gap-2 justify-between items-center">
      <h2 class="m-0 text-sm font-semibold text-n-slate-12">
        {{ t('TOLZAR_RESULTS_UI.TEAM.TITLE') }}
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
    <div class="overflow-x-auto mt-3">
      <table class="w-full text-[13px] text-n-slate-12 border-collapse">
        <thead>
          <tr class="text-xs text-n-slate-11 text-start">
            <th class="py-1 font-medium text-start">
              {{ t('TOLZAR_RESULTS_UI.TEAM.PERSON') }}
            </th>
            <th class="py-1 font-medium text-end">
              {{ t('TOLZAR_RESULTS_UI.TEAM.REPLIES') }}
            </th>
            <th class="py-1 font-medium text-end">
              {{ t('TOLZAR_RESULTS_UI.TEAM.FIRST_REPLY') }}
            </th>
            <th class="py-1 font-medium text-end">
              {{ t('TOLZAR_RESULTS_UI.TEAM.RESOLVED') }}
            </th>
            <th class="py-1 font-medium text-end">
              {{ t('TOLZAR_RESULTS_UI.TEAM.CSAT') }}
            </th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="p in report.people"
            :key="p.id"
            class="border-t border-solid border-n-weak"
          >
            <td class="py-1.5">{{ p.name }}</td>
            <td class="py-1.5 text-end tabular-nums">{{ p.replies }}</td>
            <td class="py-1.5 text-end tabular-nums">
              {{ firstReply(p.first_reply) }}
            </td>
            <td class="py-1.5 text-end tabular-nums">{{ p.resolved }}</td>
            <td class="py-1.5 text-end tabular-nums">{{ rating(p.csat) }}</td>
          </tr>
        </tbody>
      </table>
    </div>
  </section>
</template>
