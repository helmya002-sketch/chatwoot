<script setup>
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';

// Reports → Results → Reply-time target (round 4, G2; Tolzar::ReplyTarget): per inbox, first replies within the
// workspace's target vs late over 7 / 30 / 90 days. The target is the SLA when on, else the labelled default.
// Administrators; hidden when the workspace has it off (404).
const { t } = useI18n();
const accountId = useMapGetter('getCurrentAccountId');
const days = ref(30);
const report = ref(null);
const DAYS = [7, 30, 90];

async function load() {
  try {
    const { data } = await window.axios.get(
      `/api/v1/accounts/${accountId.value}/tolzar/reply_target`,
      { params: { days: days.value } }
    );
    report.value = data;
  } catch {
    report.value = null;
  }
}

const targetLabel = computed(() => {
  const target = report.value?.target || {};
  const params = { minutes: target.minutes };
  if (target.source !== 'sla')
    return t('TOLZAR_RESULTS_UI.REPLY_TARGET.TARGET_DEFAULT', params);
  return target.working_hours
    ? t('TOLZAR_RESULTS_UI.REPLY_TARGET.TARGET_SLA_HOURS', params)
    : t('TOLZAR_RESULTS_UI.REPLY_TARGET.TARGET_SLA', params);
});
const anyReplies = computed(() =>
  (report.value?.inboxes || []).some(i => i.within + i.late > 0)
);
const share = row => {
  const total = row.within + row.late;
  return total ? `${Math.round((row.within / total) * 100)}%` : '—';
};

watch(days, load, { immediate: true });
</script>

<template>
  <section
    v-if="report"
    class="p-4 mt-6 rounded-xl border border-solid border-n-weak bg-n-solid-1"
  >
    <div class="flex flex-wrap gap-2 justify-between items-center">
      <h2 class="m-0 text-sm font-semibold text-n-slate-12">
        {{ t('TOLZAR_RESULTS_UI.REPLY_TARGET.TITLE') }}
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
    <p class="mt-1 mb-0 text-xs text-n-slate-11">{{ targetLabel }}</p>
    <p v-if="!anyReplies" class="mt-3 mb-0 text-[13px] text-n-slate-10">
      {{ t('TOLZAR_RESULTS_UI.REPLY_TARGET.NONE') }}
    </p>
    <div v-else class="overflow-x-auto mt-3">
      <table class="w-full text-[13px] text-n-slate-12 border-collapse">
        <thead>
          <tr class="text-xs text-n-slate-11">
            <th class="py-1 font-medium text-start">
              {{ t('TOLZAR_RESULTS_UI.REPLY_TARGET.INBOX') }}
            </th>
            <th class="py-1 font-medium text-end">
              {{ t('TOLZAR_RESULTS_UI.REPLY_TARGET.WITHIN') }}
            </th>
            <th class="py-1 font-medium text-end">
              {{ t('TOLZAR_RESULTS_UI.REPLY_TARGET.LATE') }}
            </th>
            <th class="py-1 font-medium text-end">
              {{ t('TOLZAR_RESULTS_UI.REPLY_TARGET.SHARE') }}
            </th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="row in report.inboxes"
            :key="row.id"
            class="border-t border-solid border-n-weak"
          >
            <td class="py-1.5">{{ row.name }}</td>
            <td class="py-1.5 text-end tabular-nums">{{ row.within }}</td>
            <td class="py-1.5 text-end tabular-nums">{{ row.late }}</td>
            <td class="py-1.5 text-end tabular-nums">{{ share(row) }}</td>
          </tr>
        </tbody>
      </table>
    </div>
  </section>
</template>
