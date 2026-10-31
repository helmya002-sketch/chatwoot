<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { liveStatus } from './tolzarDashboardData';

// UI phase 3 dashboard (new UI only): the open conversations as a table with status pills (assigned to a person,
// to a team, or waiting), newest activity first; each row opens the conversation.
const props = defineProps({
  conversations: { type: Array, default: () => [] },
  accountId: { type: [Number, String], required: true },
});
const { t } = useI18n();
const rows = computed(() =>
  [...props.conversations]
    .sort((a, b) => (b.last_activity_at || 0) - (a.last_activity_at || 0))
    .slice(0, 8)
    .map(c => ({ c, status: liveStatus(c) }))
);
const PILL = {
  assigned: 'bg-n-blue-3 text-n-blue-11',
  team: 'bg-n-teal-3 text-n-teal-11',
  waiting: 'bg-n-amber-3 text-n-amber-11',
};
</script>

<template>
  <section
    class="tz-rise p-5 rounded-2xl border shadow-sm bg-n-solid-1 border-n-weak"
  >
    <h3 class="m-0 mb-3 text-sm font-semibold text-n-slate-12">
      {{ t('TOLZAR_SETTINGS_UI.DASH.LIVE') }}
    </h3>
    <p v-if="!rows.length" class="m-0 text-xs text-n-slate-11">
      {{ t('TOLZAR_SETTINGS_UI.DASH.LIVE_NONE') }}
    </p>
    <table v-else class="w-full text-[13px]">
      <thead class="text-xs text-n-slate-11">
        <tr>
          <th class="py-1.5 text-start font-medium">
            {{ t('TOLZAR_SETTINGS_UI.DASH.COL_CONTACT') }}
          </th>
          <th class="py-1.5 text-start font-medium">
            {{ t('TOLZAR_SETTINGS_UI.DASH.COL_STATUS') }}
          </th>
          <th class="py-1.5 text-end font-medium">
            {{ t('TOLZAR_SETTINGS_UI.DASH.COL_UNREAD') }}
          </th>
        </tr>
      </thead>
      <tbody>
        <tr v-for="r in rows" :key="r.c.id" class="border-t border-n-weak">
          <td class="py-1.5">
            <router-link
              :to="`/app/accounts/${accountId}/conversations/${r.c.id}`"
              class="text-n-slate-12 hover:underline"
            >
              {{ r.c.meta?.sender?.name || `#${r.c.id}` }}
            </router-link>
          </td>
          <td class="py-1.5">
            <span
              class="px-1.5 py-0.5 rounded-full text-[11px] font-medium"
              :class="PILL[r.status.key]"
            >
              {{
                t(`TOLZAR_SETTINGS_UI.DASH.ST_${r.status.key}`, {
                  who: r.status.who,
                })
              }}
            </span>
          </td>
          <td class="py-1.5 text-end tabular-nums text-n-slate-12">
            {{ r.c.unread_count || 0 }}
          </td>
        </tr>
      </tbody>
    </table>
  </section>
</template>
