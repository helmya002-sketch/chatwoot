<script setup>
import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { duration } from 'dashboard/components-next/Tolzar/tolzarTime';

// Reports → Results → Channels (round 4, c97; Tolzar::ChannelBreakdown): conversations, customer messages,
// median first reply and resolved per inbox over 7 / 30 / 90 days. Administrators; hidden when off (404).
const { t, locale } = useI18n();
const accountId = useMapGetter('getCurrentAccountId');
const days = ref(30);
const report = ref(null);
const DAYS = [7, 30, 90];

async function load() {
  try {
    const { data } = await window.axios.get(
      `/api/v1/accounts/${accountId.value}/tolzar/channel_breakdown`,
      { params: { days: days.value } }
    );
    report.value = data;
  } catch {
    report.value = null;
  }
}

const firstReply = s => (s == null ? '—' : duration(s, locale.value) || '—');
const kind = type => String(type || '').replace(/^Channel::/, '');

watch(days, load, { immediate: true });
</script>

<template>
  <section
    v-if="report"
    class="p-4 mt-6 rounded-xl border border-solid border-n-weak bg-n-solid-1"
  >
    <div class="flex flex-wrap gap-2 justify-between items-center">
      <h2 class="m-0 text-sm font-semibold text-n-slate-12">
        {{ t('TOLZAR_RESULTS_UI.CHANNELS.TITLE') }}
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
          <tr class="text-xs text-n-slate-11">
            <th class="py-1 font-medium text-start">
              {{ t('TOLZAR_RESULTS_UI.CHANNELS.INBOX') }}
            </th>
            <th class="py-1 font-medium text-end">
              {{ t('TOLZAR_RESULTS_UI.CHANNELS.CONVERSATIONS') }}
            </th>
            <th class="py-1 font-medium text-end">
              {{ t('TOLZAR_RESULTS_UI.CHANNELS.INCOMING') }}
            </th>
            <th class="py-1 font-medium text-end">
              {{ t('TOLZAR_RESULTS_UI.TEAM.FIRST_REPLY') }}
            </th>
            <th class="py-1 font-medium text-end">
              {{ t('TOLZAR_RESULTS_UI.TEAM.RESOLVED') }}
            </th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="row in report.inboxes"
            :key="row.id"
            class="border-t border-solid border-n-weak"
          >
            <td class="py-1.5">
              {{ row.name }}
              <span class="text-xs text-n-slate-10">
                {{ kind(row.channel_type) }}
              </span>
            </td>
            <td class="py-1.5 text-end tabular-nums">
              {{ row.conversations }}
            </td>
            <td class="py-1.5 text-end tabular-nums">{{ row.incoming }}</td>
            <td class="py-1.5 text-end tabular-nums">
              {{ firstReply(row.first_reply) }}
            </td>
            <td class="py-1.5 text-end tabular-nums">{{ row.resolved }}</td>
          </tr>
        </tbody>
      </table>
    </div>
  </section>
</template>
