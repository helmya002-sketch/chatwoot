<script setup>
import { ref, computed, watch, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import {
  getRoi,
  roiTiles,
  roiFacts,
  workingHoursLabel,
} from 'dashboard/components-next/Tolzar/tolzarRoi';
import { brainErrors } from 'dashboard/components-next/Tolzar/tolzarBrainApi';
import { duration, pct } from './tolzarReportsData';

// Reports → Results (ROI): what Tolzar is worth for this workspace, from the brain's /roi.
// Values Tolzar would have produced in Shadow are labelled "would-be": nothing was sent.
const { t, locale } = useI18n();
const accountId = useMapGetter('getCurrentAccountId');
const RANGES = [7, 30, 90];
const WOULD_BE_BADGE =
  'px-1.5 text-[10px] font-semibold rounded-full text-amber-700 bg-amber-500/10 whitespace-nowrap';

const days = ref(30);
const data = ref(null);
const loading = ref(true);
const errors = ref([]);

const tiles = computed(() => roiTiles(data.value));
const facts = computed(() =>
  roiFacts(data.value).map(f => {
    const p = { ...f.params };
    if ('staff' in p) p.staff = duration(p.staff);
    if ('tolzar' in p) p.tolzar = duration(p.tolzar);
    return t(`TOLZAR_RESULTS.FACT.${f.key}`, p);
  })
);
const show = tile => {
  if (tile.value === null || tile.value === undefined) return '—';
  if (tile.kind === 'seconds') return duration(tile.value);
  if (tile.kind === 'share') return pct(tile.value);
  return Number(tile.value).toLocaleString();
};
const sub = tile => {
  const s = tile.sub || {};
  if (tile.kind === 'seconds')
    return t('TOLZAR_RESULTS.SUB.seconds', { p90: duration(s.p90), n: s.n });
  return t(`TOLZAR_RESULTS.SUB.${tile.key}`, s);
};

async function load() {
  loading.value = true;
  try {
    const r = await getRoi(accountId.value, days.value);
    errors.value = brainErrors(r);
    data.value = r && r.ok ? r : null;
  } finally {
    loading.value = false;
  }
}
watch(days, load);
onMounted(load);
</script>

<template>
  <div class="overflow-auto flex-1 bg-n-background" data-tz-build="results-1">
    <div class="mx-auto max-w-[1200px] px-5 pb-16 pt-6 md:px-7">
      <div class="flex flex-wrap gap-3 items-center mb-5">
        <div class="min-w-0">
          <h1 class="m-0 text-xl font-semibold text-n-slate-12">
            {{ t('TOLZAR_RESULTS.TITLE') }}
          </h1>
          <p class="m-0 text-sm text-n-slate-11">
            {{ t('TOLZAR_RESULTS.SUBTITLE') }}
          </p>
        </div>
        <div class="flex-1" />
        <span v-if="loading" class="text-xs text-n-slate-10">{{
          t('TOLZAR_REPORTS.LOADING')
        }}</span>
        <div
          class="inline-flex overflow-hidden rounded-lg border border-solid border-n-weak bg-n-solid-1"
        >
          <button
            v-for="d in RANGES"
            :key="d"
            type="button"
            class="px-3 py-1.5 text-sm"
            :class="
              days === d
                ? 'bg-n-blue-3 text-n-blue-11 font-semibold'
                : 'text-n-slate-11 hover:bg-n-slate-2'
            "
            @click="days = d"
          >
            {{ t(`TOLZAR_REPORTS.RANGE.D${d}`) }}
          </button>
        </div>
      </div>

      <p
        v-for="e in errors"
        :key="e"
        class="p-2 text-[13px] rounded-lg text-n-ruby-11 bg-n-ruby-9/10"
      >
        {{ e }}
      </p>

      <template v-if="data">
        <p
          v-if="data.first_reply.would_be"
          class="p-2 mb-4 text-xs rounded-lg text-amber-700 bg-amber-500/10"
        >
          {{ t('TOLZAR_RESULTS.WOULD_BE_NOTE') }}
        </p>
        <div class="grid grid-cols-2 gap-3 md:grid-cols-3 xl:grid-cols-6">
          <div
            v-for="k in tiles"
            :key="k.key"
            class="p-4 rounded-xl border border-solid border-n-weak bg-n-solid-1"
          >
            <div class="flex gap-1.5 justify-between items-start">
              <div class="text-xs text-n-slate-11">
                {{ t(`TOLZAR_RESULTS.TILE.${k.key}`) }}
              </div>
              <span v-if="k.wouldBe" :class="WOULD_BE_BADGE">
                {{ t('TOLZAR_RESULTS.WOULD_BE') }}
              </span>
            </div>
            <div class="mt-1 text-2xl font-semibold text-n-slate-12">
              {{ show(k) }}
            </div>
            <div class="mt-0.5 text-xs text-n-slate-10">{{ sub(k) }}</div>
          </div>
        </div>

        <div class="grid gap-3 mt-6 xl:grid-cols-[1.4fr_1fr]">
          <div
            class="p-4 rounded-xl border border-solid border-n-weak bg-n-solid-1"
          >
            <h2 class="m-0 text-sm font-semibold text-n-slate-12">
              {{ t('TOLZAR_RESULTS.SUMMARY') }}
            </h2>
            <p
              v-for="(f, i) in facts"
              :key="i"
              class="mt-2 mb-0 text-sm text-n-slate-12"
            >
              {{ f }}
            </p>
            <p class="mt-3 mb-0 text-xs text-n-slate-10">
              {{
                t('TOLZAR_RESULTS.HOURS', {
                  hours: workingHoursLabel(
                    data.off_hours.working_hours,
                    locale
                  ),
                  tz: data.off_hours.timezone,
                })
              }}
            </p>
            <p class="mt-1 mb-0 text-xs text-n-slate-10">
              {{
                t('TOLZAR_RESULTS.WON_RULE', {
                  field: data.won_rule.field,
                  value: data.won_rule.contains,
                })
              }}
            </p>
          </div>
          <div
            class="p-4 rounded-xl border border-solid border-n-weak bg-n-solid-1"
          >
            <h2 class="m-0 text-sm font-semibold text-n-slate-12">
              {{ t('TOLZAR_RESULTS.CAMPAIGNS') }}
            </h2>
            <table class="mt-2 w-full text-[13px]">
              <tr
                v-for="c in data.campaigns"
                :key="c.campaign"
                class="border-t border-solid border-n-weak"
              >
                <td class="py-1.5">{{ c.campaign }}</td>
                <td class="text-right text-n-slate-11">
                  {{
                    t('TOLZAR_RESULTS.CAMPAIGN_ROW', {
                      n: c.conversations,
                      codes: c.codes,
                    })
                  }}
                </td>
              </tr>
            </table>
            <p
              v-if="!data.campaigns.length"
              class="mt-2 mb-0 text-[13px] text-n-slate-10"
            >
              {{ t('TOLZAR_RESULTS.NO_CAMPAIGNS') }}
            </p>
          </div>
        </div>
      </template>
    </div>
  </div>
</template>
