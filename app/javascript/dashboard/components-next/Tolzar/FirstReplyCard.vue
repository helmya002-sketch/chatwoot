<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { firstReplySeries, niceMax } from './tolzarDashboardData';

// UI phase 3 dashboard (new UI only): the average first-reply time per day, last 14 days, from the app's own
// reports API. One series, so no legend; thin bars with a gap, hover values, a table for screen readers.
const { t } = useI18n();
const accountId = useMapGetter('getCurrentAccountId');
const series = ref([]);
const failed = ref(false);
const W = 560;
const H = 140;
const PAD = 24;

onMounted(async () => {
  const until = Math.floor(Date.now() / 1000);
  const since = until - 14 * 86400;
  try {
    const { data } = await window.axios.get(
      `/api/v2/accounts/${accountId.value}/reports`,
      {
        params: {
          metric: 'avg_first_response_time',
          type: 'account',
          since,
          until,
          group_by: 'day',
          timezone_offset: -new Date().getTimezoneOffset() / 60,
        },
      }
    );
    series.value = firstReplySeries(Array.isArray(data) ? data : []);
  } catch {
    failed.value = true;
  }
});

const max = computed(() => niceMax(series.value.map(p => p.minutes)));
const barW = computed(() => (W - PAD) / Math.max(series.value.length, 1) - 4);
const bars = computed(() =>
  series.value.map((p, i) => {
    const h =
      p.minutes == null ? 0 : Math.max(2, ((H - PAD) * p.minutes) / max.value);
    return { ...p, x: PAD + i * (barW.value + 4), y: H - PAD - h, h };
  })
);
const label = day =>
  new Date(day * 1000).toLocaleDateString(undefined, {
    day: 'numeric',
    month: 'short',
  });
</script>

<template>
  <section
    class="tz-rise p-5 rounded-2xl border shadow-sm bg-n-solid-1 border-n-weak"
  >
    <h3 class="m-0 mb-3 text-sm font-semibold text-n-slate-12">
      {{ t('TOLZAR_SETTINGS_UI.DASH.FIRST_REPLY') }}
    </h3>
    <p v-if="failed" class="m-0 text-xs text-n-slate-11">
      {{ t('TOLZAR_SETTINGS_UI.DASH.NO_DATA') }}
    </p>
    <template v-else>
      <svg
        :viewBox="`0 0 ${W} ${H}`"
        class="w-full h-auto"
        role="img"
        :aria-label="t('TOLZAR_SETTINGS_UI.DASH.FIRST_REPLY')"
      >
        <line
          :x1="PAD"
          :x2="W"
          :y1="H - PAD"
          :y2="H - PAD"
          class="stroke-n-weak"
          stroke-width="1"
        />
        <text :x="0" :y="12" class="fill-n-slate-10 text-[10px]">
          {{ t('TOLZAR_SETTINGS_UI.DASH.MINUTES', { n: max }) }}
        </text>
        <g v-for="b in bars" :key="b.day">
          <rect
            :x="b.x"
            :y="b.y"
            :width="barW"
            :height="b.h"
            rx="3"
            class="fill-n-brand"
          >
            <title>
              {{ label(b.day) }}:
              {{
                b.minutes == null
                  ? t('TOLZAR_SETTINGS_UI.DASH.NO_REPLY')
                  : t('TOLZAR_SETTINGS_UI.DASH.MINUTES', { n: b.minutes })
              }}
            </title>
          </rect>
        </g>
      </svg>
      <table class="sr-only">
        <caption>
          {{
            t('TOLZAR_SETTINGS_UI.DASH.FIRST_REPLY')
          }}
        </caption>
        <tr v-for="b in bars" :key="`t${b.day}`">
          <th scope="row">{{ label(b.day) }}</th>
          <td>
            {{
              b.minutes == null
                ? t('TOLZAR_SETTINGS_UI.DASH.NO_REPLY')
                : t('TOLZAR_SETTINGS_UI.DASH.MINUTES', { n: b.minutes })
            }}
          </td>
        </tr>
      </table>
    </template>
  </section>
</template>
