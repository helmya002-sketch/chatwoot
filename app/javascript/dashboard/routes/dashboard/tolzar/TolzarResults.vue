<script setup>
import { ref, computed, watch, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useLocale } from 'shared/composables/useLocale';
import { useMapGetter } from 'dashboard/composables/store';
import {
  getRoi,
  roiTiles,
  roiFacts,
  roiView,
  workingHoursLabel,
} from 'dashboard/components-next/Tolzar/tolzarRoi';
import { duration as fmtDuration } from 'dashboard/components-next/Tolzar/tolzarTime';
import BrainNotice from 'dashboard/components-next/Tolzar/settings/BrainNotice.vue';
import ShadowBadge from 'dashboard/components-next/Tolzar/ShadowBadge.vue';
import TolzarBookingResultsCard from 'dashboard/components-next/Tolzar/BookingResultsCard.vue';
import TolzarOutcomeReasonsCard from 'dashboard/components-next/Tolzar/OutcomeReasonsCard.vue';
import TolzarTeamCard from 'dashboard/components-next/Tolzar/TeamLeaderboardCard.vue';
import TolzarChannelsCard from 'dashboard/components-next/Tolzar/ChannelBreakdownCard.vue';
import TolzarRatingsCard from 'dashboard/components-next/Tolzar/CustomerRatingsCard.vue';
import TolzarReplyTargetCard from 'dashboard/components-next/Tolzar/ReplyTargetCard.vue';
import { TONE_WARN } from 'dashboard/components-next/Tolzar/settings/tzClasses';

// Reports → Results (ROI): what Tolzar is worth for this workspace, from the brain's /roi.
// Values Tolzar would have produced in Shadow are labelled "would-be": nothing was sent.
const { t } = useI18n();
const { resolvedLocale } = useLocale();
const accountId = useMapGetter('getCurrentAccountId');
const RANGES = [7, 30, 90];
const WOULD_BE_BADGE = `px-1.5 text-[10px] font-semibold rounded-full whitespace-nowrap ${TONE_WARN}`;

const days = ref(30);
const data = ref(null);
const result = ref(null); // the brain's refusal or errors, for BrainNotice
const loading = ref(true);

// Every block the template reads is present, whatever the brain omitted.
const view = computed(() => roiView(data.value));

// One formatter path: durations and numbers through Intl in the viewer's language.
const duration = s => fmtDuration(s, resolvedLocale.value) || '—';
const number = n => {
  try {
    return new Intl.NumberFormat(resolvedLocale.value).format(Number(n));
  } catch (e) {
    return String(n);
  }
};
const percent = v => {
  try {
    return new Intl.NumberFormat(resolvedLocale.value, {
      style: 'percent',
      maximumFractionDigits: 0,
    }).format(Number(v));
  } catch (e) {
    return `${Math.round(Number(v) * 100)}%`;
  }
};

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
  if (tile.kind === 'share') return percent(tile.value);
  return number(tile.value);
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
    result.value = r && r.ok ? null : r;
    data.value = r && r.ok ? r : null;
  } catch (e) {
    result.value = { ok: false, error: t('TOLZAR_UI.LOAD_FAILED') };
    data.value = null;
  } finally {
    loading.value = false;
  }
}
watch(days, load);
onMounted(load);
</script>

<template>
  <div class="overflow-auto flex-1 bg-n-background" data-tz-build="results-2">
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
          t('TOLZAR_UI.LOADING')
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
            :aria-pressed="days === d"
            @click="days = d"
          >
            {{ t(`TOLZAR_REPORTS.RANGE.D${d}`) }}
          </button>
        </div>
      </div>

      <BrainNotice v-if="result" :result="result" />
      <div v-if="result && !loading" class="mt-2 mb-4">
        <button
          type="button"
          class="text-xs font-semibold text-n-brand underline"
          @click="load"
        >
          {{ t('TOLZAR_UI.RETRY') }}
        </button>
      </div>

      <template v-if="data">
        <div
          v-if="view.first_reply.would_be"
          class="flex flex-wrap gap-2 items-center p-2 mb-4 text-xs rounded-lg"
          :class="TONE_WARN"
        >
          <ShadowBadge state="shadow" />
          <span class="flex-1 min-w-0">
            {{ t('TOLZAR_RESULTS_UI.WOULD_BE_HINT') }}
          </span>
          <router-link
            :to="{ name: 'tolzar_settings', query: { section: 'go_live' } }"
            class="font-semibold underline text-current"
          >
            {{ t('TOLZAR_RESULTS_UI.WHAT_IS_SHADOW') }}
          </router-link>
        </div>
        <div class="grid grid-cols-2 gap-3 md:grid-cols-3 xl:grid-cols-6">
          <div
            v-for="k in tiles"
            :key="k.key"
            class="tz-kpi p-4 rounded-xl border border-solid border-n-weak bg-n-solid-1"
          >
            <div class="flex gap-1.5 justify-between items-start">
              <div class="text-xs text-n-slate-11">
                {{ t(`TOLZAR_RESULTS.TILE.${k.key}`) }}
              </div>
              <span
                v-if="k.wouldBe"
                :class="WOULD_BE_BADGE"
                :title="t('TOLZAR_UI.STATE.SHADOW_HINT')"
              >
                {{ t('TOLZAR_RESULTS.WOULD_BE') }}
              </span>
            </div>
            <div class="tz-kpi-value mt-1 text-2xl font-semibold text-n-slate-12">
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
            <p
              v-if="view.off_hours.working_hours"
              class="mt-3 mb-0 text-xs text-n-slate-10"
            >
              {{
                t('TOLZAR_RESULTS.HOURS', {
                  hours: workingHoursLabel(
                    view.off_hours.working_hours,
                    resolvedLocale
                  ),
                  tz: view.off_hours.timezone || '',
                })
              }}
            </p>
            <p
              v-if="view.won_rule.field"
              class="mt-1 mb-0 text-xs text-n-slate-10"
            >
              {{
                t('TOLZAR_RESULTS.WON_RULE', {
                  field: view.won_rule.field,
                  value: view.won_rule.contains || '',
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
            <table v-if="view.campaigns.length" class="mt-2 w-full text-[13px]">
              <tbody>
                <tr
                  v-for="c in view.campaigns"
                  :key="c.campaign"
                  class="border-t border-solid border-n-weak"
                >
                  <td class="py-1.5">{{ c.campaign }}</td>
                  <td class="text-end text-n-slate-11">
                    {{
                      t('TOLZAR_RESULTS.CAMPAIGN_ROW', {
                        n: number(c.conversations || 0),
                        codes: number(c.codes || 0),
                      })
                    }}
                  </td>
                </tr>
              </tbody>
            </table>
            <p v-else class="mt-2 mb-0 text-[13px] text-n-slate-10">
              {{ t('TOLZAR_RESULTS.NO_CAMPAIGNS') }}
            </p>
          </div>
        </div>
        <TolzarBookingResultsCard />
        <TolzarOutcomeReasonsCard />
        <TolzarTeamCard />
        <TolzarChannelsCard />
        <TolzarRatingsCard />
        <TolzarReplyTargetCard />
      </template>
    </div>
  </div>
</template>
