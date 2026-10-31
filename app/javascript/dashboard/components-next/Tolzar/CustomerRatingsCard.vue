<script setup>
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { frontendURL } from 'dashboard/helper/URLHelper';

// Reports → Results → Customer ratings (round 4, G1; Tolzar::CustomerRatings): average, count, 1-5 spread and the
// latest written comments over 7 / 30 / 90 days. Administrators; hidden when the workspace has it off (404).
const { t } = useI18n();
const accountId = useMapGetter('getCurrentAccountId');
const days = ref(30);
const report = ref(null);
const DAYS = [7, 30, 90];

async function load() {
  try {
    const { data } = await window.axios.get(
      `/api/v1/accounts/${accountId.value}/tolzar/customer_ratings`,
      { params: { days: days.value } }
    );
    report.value = data;
  } catch {
    report.value = null;
  }
}

// Highest rating first, as people read a ratings spread.
const bars = computed(() =>
  [...(report.value?.distribution || [])].reverse().map(row => {
    const total = report.value.count || 0;
    return { ...row, pct: total ? Math.round((row.count / total) * 100) : 0 };
  })
);
const link = id =>
  frontendURL(`accounts/${accountId.value}/conversations/${id}`);

watch(days, load, { immediate: true });
</script>

<template>
  <section
    v-if="report"
    class="p-4 mt-6 rounded-xl border border-solid border-n-weak bg-n-solid-1"
  >
    <div class="flex flex-wrap gap-2 justify-between items-center">
      <h2 class="m-0 text-sm font-semibold text-n-slate-12">
        {{ t('TOLZAR_RESULTS_UI.RATINGS.TITLE') }}
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
    <p v-if="!report.count" class="mt-3 mb-0 text-[13px] text-n-slate-10">
      {{ t('TOLZAR_RESULTS_UI.RATINGS.NONE') }}
    </p>
    <div v-else class="grid gap-4 mt-3 md:grid-cols-[1fr_1.4fr]">
      <div>
        <div class="flex gap-6">
          <div>
            <div class="text-xs text-n-slate-11">
              {{ t('TOLZAR_RESULTS_UI.RATINGS.AVERAGE') }}
            </div>
            <div class="text-2xl font-semibold text-n-slate-12 tabular-nums">
              {{
                t('TOLZAR_RESULTS_UI.RATINGS.OUT_OF', { avg: report.average })
              }}
            </div>
          </div>
          <div>
            <div class="text-xs text-n-slate-11">
              {{ t('TOLZAR_RESULTS_UI.RATINGS.COUNT') }}
            </div>
            <div class="text-2xl font-semibold text-n-slate-12 tabular-nums">
              {{ report.count }}
            </div>
          </div>
        </div>
        <ul class="p-0 m-0 mt-3 list-none">
          <li
            v-for="b in bars"
            :key="b.rating"
            class="flex gap-2 items-center py-0.5 text-[13px] text-n-slate-12"
          >
            <span class="w-14 shrink-0">
              {{ t('TOLZAR_RESULTS_UI.RATINGS.STARS', { n: b.rating }) }}
            </span>
            <span
              class="overflow-hidden flex-1 h-2 rounded-full bg-n-slate-3"
              aria-hidden="true"
            >
              <span
                class="block h-full rounded-full bg-n-blue-9"
                :style="{ width: `${b.pct}%` }"
              />
            </span>
            <span class="w-16 text-end tabular-nums text-n-slate-11">
              {{
                t('TOLZAR_RESULTS_UI.RATINGS.SHARE', { n: b.count, pct: b.pct })
              }}
            </span>
          </li>
        </ul>
      </div>
      <div>
        <h3 class="m-0 text-xs font-medium text-n-slate-11">
          {{ t('TOLZAR_RESULTS_UI.RATINGS.COMMENTS') }}
        </h3>
        <p
          v-if="!report.comments.length"
          class="mt-2 mb-0 text-[13px] text-n-slate-10"
        >
          {{ t('TOLZAR_RESULTS_UI.RATINGS.NO_COMMENTS') }}
        </p>
        <ul v-else class="p-0 m-0 mt-1 list-none">
          <li
            v-for="(c, i) in report.comments"
            :key="i"
            class="py-1.5 text-[13px] border-t border-solid border-n-weak first:border-t-0"
          >
            <div class="flex gap-2 justify-between text-xs text-n-slate-11">
              <span>{{
                t('TOLZAR_RESULTS_UI.RATINGS.STARS', { n: c.rating })
              }}</span>
              <router-link :to="link(c.conversation)" class="text-n-brand">
                {{
                  t('TOLZAR_RESULTS_UI.RATINGS.OPEN', { id: c.conversation })
                }}
              </router-link>
            </div>
            <p class="mt-0.5 mb-0 text-n-slate-12 break-words">{{ c.text }}</p>
          </li>
        </ul>
      </div>
    </div>
  </section>
</template>
