<script setup>
// Tolzar Reports (UI pass 2 + roadmap #2): one overview of leads, bookings, team speed and
// the shadow-eval scoreboard. Live data only: Chatwoot's reports API, contact filters, and the
// brain's /scoreboard through the admin-only Rails proxy. Numbers that can't be known yet say so.
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import ReportsAPI from 'dashboard/api/reports';
import SummaryReportsAPI from 'dashboard/api/summaryReports';
import { STAGES } from 'dashboard/components-next/Tolzar/tolzarStages';
import {
  delta,
  duration,
  euro,
  newContacts,
  pct,
  rangeFor,
  stageCounts,
  stageValue,
  weeklyNewContacts,
} from './tolzarReportsData';

const { t } = useI18n();
const store = useStore();
const accountId = useMapGetter('getCurrentAccountId');
const agents = useMapGetter('agents/getAgents');

const RANGES = [7, 30, 90];
const days = ref(30);
const loading = ref(true);
const updatedAt = ref(null);

const summary = ref(null);
const prevSummary = ref(null);
const newNow = ref(0);
const newPrev = ref(0);
const counts = ref({});
const weekly = ref([]);
const people = ref([]);
const values = ref([]);
const sb = ref(null);
const sbError = ref(false);
const tables = ref({
  funnel: false,
  weekly: false,
  pipeline: false,
  ai: false,
});

const STAGE_VAR = {
  'New Lead': 'var(--tz-s1)',
  Active: 'var(--tz-s2)',
  'Offer Sent Follow up': 'var(--tz-s3)',
  'Customer Won': 'var(--tz-s4)',
  'Customer Lost': 'var(--tz-s5)',
};

async function load() {
  loading.value = true;
  const r = rangeFor(days.value);
  const id = accountId.value;
  const jobs = [
    ReportsAPI.getSummary(r.since, r.until, 'account').then(x => {
      summary.value = x.data;
    }),
    ReportsAPI.getSummary(r.prevSince, r.since, 'account').then(x => {
      prevSummary.value = x.data;
    }),
    newContacts(r.since).then(n => {
      newNow.value = n;
    }),
    newContacts(r.prevSince, r.since).then(n => {
      newPrev.value = n;
    }),
    stageCounts().then(c => {
      counts.value = c;
    }),
    weeklyNewContacts().then(w => {
      weekly.value = w;
    }),
    SummaryReportsAPI.getAgentReports({ since: r.since, until: r.until }).then(
      x => {
        people.value = (x.data || []).filter(p => p.conversations_count > 0);
      }
    ),
    Promise.all(
      ['Active', 'Offer Sent Follow up', 'Customer Won'].map(s => stageValue(s))
    ).then(v => {
      values.value = v;
    }),
    window.axios
      .get(`/api/v1/accounts/${id}/tolzar/scoreboard`, {
        params: { days: days.value },
      })
      .then(x => {
        sb.value = x.data;
        sbError.value = !x.data?.ok;
      })
      .catch(() => {
        sbError.value = true;
      }),
  ];
  await Promise.allSettled(jobs);
  loading.value = false;
  updatedAt.value = new Date();
}

onMounted(() => {
  store.dispatch('agents/get').catch(() => {});
  load();
});
watch(days, load);

// ---- KPIs ------------------------------------------------------------------------------
const wonValue = computed(
  () => values.value.find(v => v.stage === 'Customer Won') || null
);
const kpis = computed(() => {
  const s = summary.value || {};
  const p = prevSummary.value || {};
  const vs = (now, prev) => {
    const d = delta(now, prev);
    if (d === null) return { text: t('TOLZAR_REPORTS.KPI.NO_PREV'), dir: 0 };
    let sign = '';
    if (d > 0) sign = '▲';
    else if (d < 0) sign = '▼';
    return {
      text: t('TOLZAR_REPORTS.KPI.VS_PREV', {
        delta: `${sign} ${Math.abs(Math.round(d * 100))}%`,
        days: days.value,
      }),
      dir: Math.sign(d),
    };
  };
  return [
    {
      key: 'conv',
      label: t('TOLZAR_REPORTS.KPI.CONVERSATIONS'),
      value: s.conversations_count ?? '—',
      ...vs(s.conversations_count, p.conversations_count),
    },
    {
      key: 'new',
      label: t('TOLZAR_REPORTS.KPI.NEW_CONTACTS'),
      value: newNow.value,
      ...vs(newNow.value, newPrev.value),
    },
    {
      key: 'won',
      label: t('TOLZAR_REPORTS.KPI.WON'),
      value: counts.value['Customer Won'] ?? '—',
      text: '',
      dir: 0,
    },
    {
      key: 'value',
      label: t('TOLZAR_REPORTS.KPI.WON_VALUE'),
      value: wonValue.value
        ? `${wonValue.value.capped ? `${t('TOLZAR_REPORTS.KPI.AT_LEAST')} ` : ''}${euro(wonValue.value.total)}`
        : '—',
      text: '',
      dir: 0,
    },
    {
      key: 'first',
      label: t('TOLZAR_REPORTS.KPI.FIRST_REPLY'),
      value: duration(s.avg_first_response_time),
      // faster is better: a drop is good news
      ...vs(s.avg_first_response_time, p.avg_first_response_time),
      better: -1,
    },
    {
      key: 'resolve',
      label: t('TOLZAR_REPORTS.KPI.RESOLVE'),
      value: duration(s.avg_resolution_time),
      text: t('TOLZAR_REPORTS.KPI.RESOLVED', { n: s.resolutions_count ?? 0 }),
      dir: 0,
    },
  ];
});
const toneOf = k => {
  if (!k.dir) return 'text-n-slate-11';
  const good = k.better === -1 ? k.dir < 0 : k.dir > 0;
  return good ? 'text-n-teal-11' : 'text-n-ruby-11';
};

// ---- Funnel ----------------------------------------------------------------------------
const funnel = computed(() => {
  const order = STAGES.filter(s => s.key !== 'Customer Lost');
  const max = Math.max(1, ...order.map(s => counts.value[s.key] || 0));
  return order.map((s, i) => {
    const n = counts.value[s.key] || 0;
    const prevN = i ? counts.value[order[i - 1].key] || 0 : null;
    return {
      ...s,
      n,
      width: Math.max(1, (n / max) * 100),
      share:
        i && prevN
          ? t('TOLZAR_REPORTS.SHARE_OF', {
              pct: Math.round((n / prevN) * 100),
              stage: order[i - 1].label,
            })
          : '',
      color: STAGE_VAR[s.key],
    };
  });
});
const lost = computed(() => counts.value['Customer Lost'] || 0);

// ---- Weekly bars (single series) --------------------------------------------------------
const weekMax = computed(() => Math.max(1, ...weekly.value.map(w => w.count)));

// ---- People ----------------------------------------------------------------------------
const peopleRows = computed(() =>
  people.value
    .map(p => ({
      ...p,
      name: (agents.value || []).find(a => a.id === p.id)?.name || `#${p.id}`,
    }))
    .sort((a, b) => b.conversations_count - a.conversations_count)
);

// ---- Pipeline --------------------------------------------------------------------------
const pipeMax = computed(() => Math.max(1, ...values.value.map(v => v.total)));
const stageLabel = key => STAGES.find(s => s.key === key)?.label || key;

// ---- Scoreboard ------------------------------------------------------------------------
const checkLabel = c => t(`TOLZAR_REPORTS.CHECK.${c.key.toUpperCase()}`);
const checkValue = c => {
  if (c.value === null || c.value === undefined)
    return t('TOLZAR_REPORTS.NO_DATA');
  return c.key === 'price_leaks' ? String(c.value) : pct(c.value, 1);
};
const checkTarget = c => {
  const v = c.key === 'price_leaks' ? String(c.target) : pct(c.target);
  return c.higher_is_better
    ? t('TOLZAR_REPORTS.TARGET_MIN', { target: v })
    : t('TOLZAR_REPORTS.TARGET_MAX', { target: v });
};
const ready = computed(
  () =>
    sb.value &&
    sb.value.measured > 0 &&
    sb.value.passing === sb.value.checks.length
);
const modelName = computed(
  () => sb.value?.model_latest || Object.keys(sb.value?.models || {})[0] || '—'
);
const byModel = computed(() => sb.value?.by_model || []);
const FEW = 30;
const wouldLabel = w => {
  if (w === 'ask') return t('TOLZAR_REPORTS.WOULD_ASK');
  if (w === 'human') return t('TOLZAR_REPORTS.WOULD_HUMAN');
  return w || '—';
};
const daily = computed(() => sb.value?.daily || []);

// Line geometry for the daily AI chart: one % axis, two series, crosshair tooltip.
const LW = 460;
const LH = 200;
const PAD = { l: 34, r: 12, t: 10, b: 24 };
const xAt = i =>
  PAD.l +
  (daily.value.length > 1
    ? (i * (LW - PAD.l - PAD.r)) / (daily.value.length - 1)
    : 0);
const yAt = v => PAD.t + (LH - PAD.t - PAD.b) * (1 - (v ?? 0));
const pathOf = key =>
  daily.value
    .map((d, i) => (d[key] === null ? null : `${xAt(i)} ${yAt(d[key])}`))
    .filter(Boolean)
    .map((p, i) => `${i ? 'L' : 'M'}${p}`)
    .join(' ');
const hover = ref(null);
const onLineMove = e => {
  const box = e.currentTarget.getBoundingClientRect();
  const x = ((e.clientX - box.left) / box.width) * LW;
  const n = daily.value.length;
  if (!n) return;
  const i = Math.max(
    0,
    Math.min(n - 1, Math.round(((x - PAD.l) / (LW - PAD.l - PAD.r)) * (n - 1)))
  );
  hover.value = { i, x: e.clientX, y: e.clientY };
};

// Generic hover tooltip for bars.
const tip = ref(null);
const showTip = (e, title, body) => {
  tip.value = { x: e.clientX, y: e.clientY, title, body };
};

const updatedLabel = computed(() =>
  updatedAt.value
    ? t('TOLZAR_REPORTS.UPDATED', {
        time: updatedAt.value.toLocaleTimeString([], {
          hour: '2-digit',
          minute: '2-digit',
        }),
      })
    : ''
);
</script>

<template>
  <div class="tz-rep flex-1 overflow-auto bg-n-background">
    <div class="mx-auto max-w-[1200px] px-5 pb-16 pt-6 md:px-7">
      <div class="flex flex-wrap items-center gap-3 mb-5">
        <div class="min-w-0">
          <h1 class="m-0 text-xl font-semibold text-n-slate-12">
            {{ t('TOLZAR_REPORTS.TITLE') }}
          </h1>
          <p class="m-0 text-sm text-n-slate-11">
            {{ t('TOLZAR_REPORTS.SUBTITLE') }}
          </p>
        </div>
        <div class="flex-1" />
        <span class="text-xs text-n-slate-10">{{
          loading ? t('TOLZAR_REPORTS.LOADING') : updatedLabel
        }}</span>
        <div
          class="inline-flex overflow-hidden border rounded-lg border-n-weak bg-n-solid-1"
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

      <!-- KPIs -->
      <div class="grid grid-cols-2 gap-3 md:grid-cols-3 xl:grid-cols-6">
        <div
          v-for="k in kpis"
          :key="k.key"
          class="p-4 border rounded-xl border-n-weak bg-n-solid-1"
        >
          <div class="text-xs text-n-slate-11">{{ k.label }}</div>
          <div class="mt-1 text-2xl font-semibold text-n-slate-12">
            {{ k.value }}
          </div>
          <div class="mt-0.5 text-xs" :class="toneOf(k)">{{ k.text }}</div>
        </div>
      </div>

      <!-- Lifecycle -->
      <h2 class="mt-7 mb-3 text-base font-semibold text-n-slate-12">
        {{ t('TOLZAR_REPORTS.LIFECYCLE') }}
      </h2>
      <div class="grid gap-3 xl:grid-cols-[1.25fr_1fr]">
        <div class="p-4 border rounded-xl border-n-weak bg-n-solid-1">
          <div class="flex items-start justify-between gap-2">
            <div>
              <h3 class="m-0 text-sm font-semibold text-n-slate-12">
                {{ t('TOLZAR_REPORTS.FUNNEL') }}
              </h3>
              <p class="mt-0.5 mb-3 text-xs text-n-slate-11">
                {{ t('TOLZAR_REPORTS.FUNNEL_SUB') }}
              </p>
            </div>
            <button
              type="button"
              class="text-xs text-n-blue-11"
              @click="tables.funnel = !tables.funnel"
            >
              {{
                tables.funnel
                  ? t('TOLZAR_REPORTS.HIDE_TABLE')
                  : t('TOLZAR_REPORTS.SHOW_TABLE')
              }}
            </button>
          </div>
          <div v-if="!tables.funnel" class="flex flex-col gap-2.5">
            <div
              v-for="f in funnel"
              :key="f.key"
              class="grid grid-cols-[6.5rem_1fr] items-center gap-3"
              @mousemove="
                e =>
                  showTip(
                    e,
                    f.label,
                    t('TOLZAR_REPORTS.CONTACTS_N', { n: f.n })
                  )
              "
              @mouseleave="tip = null"
            >
              <span class="text-sm text-n-slate-12">{{ f.label }}</span>
              <div class="min-w-0">
                <div class="flex items-center gap-2">
                  <span
                    class="block h-6 rounded"
                    :style="{ width: `${f.width}%`, background: f.color }"
                  />
                  <span class="text-sm font-semibold text-n-slate-12">{{
                    f.n
                  }}</span>
                </div>
                <div v-if="f.share" class="mt-0.5 text-xs text-n-slate-10">
                  {{ f.share }}
                </div>
              </div>
            </div>
            <div class="grid grid-cols-[6.5rem_1fr] items-center gap-3">
              <span class="text-sm text-n-slate-12">{{
                stageLabel('Customer Lost')
              }}</span>
              <span class="text-sm font-semibold text-n-slate-12">{{
                lost
              }}</span>
            </div>
          </div>
          <table v-else class="w-full text-sm">
            <thead>
              <tr class="text-xs text-n-slate-10">
                <th class="py-1.5 font-normal text-start">
                  {{ t('TOLZAR_REPORTS.COL.STAGE') }}
                </th>
                <th class="py-1.5 font-normal text-end">
                  {{ t('TOLZAR_REPORTS.COL.CONTACTS') }}
                </th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="s in STAGES"
                :key="s.key"
                class="border-t border-n-weak"
              >
                <td class="py-1.5">{{ s.label }}</td>
                <td class="py-1.5 text-end tabular-nums">
                  {{ counts[s.key] || 0 }}
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <div class="p-4 border rounded-xl border-n-weak bg-n-solid-1">
          <div class="flex items-start justify-between gap-2">
            <div>
              <h3 class="m-0 text-sm font-semibold text-n-slate-12">
                {{ t('TOLZAR_REPORTS.WEEKLY') }}
              </h3>
              <p class="mt-0.5 mb-3 text-xs text-n-slate-11">
                {{ t('TOLZAR_REPORTS.WEEKLY_SUB') }}
              </p>
            </div>
            <button
              type="button"
              class="text-xs text-n-blue-11"
              @click="tables.weekly = !tables.weekly"
            >
              {{
                tables.weekly
                  ? t('TOLZAR_REPORTS.HIDE_TABLE')
                  : t('TOLZAR_REPORTS.SHOW_TABLE')
              }}
            </button>
          </div>
          <div v-if="!tables.weekly" class="flex items-end h-40 gap-3 px-1">
            <div
              v-for="w in weekly"
              :key="w.week"
              class="flex flex-col items-center justify-end flex-1 h-full gap-1"
              @mousemove="
                e =>
                  showTip(
                    e,
                    w.week,
                    t('TOLZAR_REPORTS.CONTACTS_N', { n: w.count })
                  )
              "
              @mouseleave="tip = null"
            >
              <span class="text-xs font-semibold text-n-slate-12">{{
                w.count
              }}</span>
              <span
                class="w-full max-w-12 rounded-t tz-bg-s1"
                :style="{
                  height: `${Math.max(2, (w.count / weekMax) * 100)}%`,
                }"
              />
              <span class="text-[11px] text-n-slate-10">{{
                w.week.slice(5)
              }}</span>
            </div>
          </div>
          <table v-else class="w-full text-sm">
            <thead>
              <tr class="text-xs text-n-slate-10">
                <th class="py-1.5 font-normal text-start">
                  {{ t('TOLZAR_REPORTS.COL.WEEK') }}
                </th>
                <th class="py-1.5 font-normal text-end">
                  {{ t('TOLZAR_REPORTS.COL.NEW') }}
                </th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="w in weekly"
                :key="w.week"
                class="border-t border-n-weak"
              >
                <td class="py-1.5">{{ w.week }}</td>
                <td class="py-1.5 text-end tabular-nums">{{ w.count }}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      <!-- Team -->
      <h2 class="mt-7 mb-3 text-base font-semibold text-n-slate-12">
        {{ t('TOLZAR_REPORTS.TEAM') }}
      </h2>
      <div class="grid gap-3 xl:grid-cols-[1.25fr_1fr]">
        <div class="p-4 border rounded-xl border-n-weak bg-n-solid-1">
          <h3 class="m-0 text-sm font-semibold text-n-slate-12">
            {{ t('TOLZAR_REPORTS.PEOPLE') }}
          </h3>
          <p class="mt-0.5 mb-3 text-xs text-n-slate-11">
            {{ t('TOLZAR_REPORTS.PEOPLE_SUB') }}
          </p>
          <table class="w-full text-sm">
            <thead>
              <tr class="text-xs text-n-slate-10">
                <th class="py-1.5 font-normal text-start">
                  {{ t('TOLZAR_REPORTS.COL.PERSON') }}
                </th>
                <th class="py-1.5 font-normal text-end">
                  {{ t('TOLZAR_REPORTS.COL.CONVERSATIONS') }}
                </th>
                <th class="py-1.5 font-normal text-end">
                  {{ t('TOLZAR_REPORTS.COL.FIRST_REPLY') }}
                </th>
                <th class="py-1.5 font-normal text-end">
                  {{ t('TOLZAR_REPORTS.COL.RESOLVE') }}
                </th>
                <th class="py-1.5 font-normal text-end">
                  {{ t('TOLZAR_REPORTS.COL.RESOLVED') }}
                </th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="p in peopleRows"
                :key="p.id"
                class="border-t border-n-weak"
              >
                <td class="py-1.5 text-n-slate-12">{{ p.name }}</td>
                <td class="py-1.5 text-end tabular-nums">
                  {{ p.conversations_count }}
                </td>
                <td class="py-1.5 text-end tabular-nums">
                  {{ duration(p.avg_first_response_time) }}
                </td>
                <td class="py-1.5 text-end tabular-nums">
                  {{ duration(p.avg_resolution_time) }}
                </td>
                <td class="py-1.5 text-end tabular-nums">
                  {{ p.resolved_conversations_count }}
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <div class="p-4 border rounded-xl border-n-weak bg-n-solid-1">
          <div class="flex items-start justify-between gap-2">
            <div>
              <h3 class="m-0 text-sm font-semibold text-n-slate-12">
                {{ t('TOLZAR_REPORTS.PIPELINE') }}
              </h3>
              <p class="mt-0.5 mb-3 text-xs text-n-slate-11">
                {{ t('TOLZAR_REPORTS.PIPELINE_SUB') }}
              </p>
            </div>
            <button
              type="button"
              class="text-xs text-n-blue-11"
              @click="tables.pipeline = !tables.pipeline"
            >
              {{
                tables.pipeline
                  ? t('TOLZAR_REPORTS.HIDE_TABLE')
                  : t('TOLZAR_REPORTS.SHOW_TABLE')
              }}
            </button>
          </div>
          <div v-if="!tables.pipeline" class="flex flex-col gap-3">
            <div
              v-for="v in values"
              :key="v.stage"
              class="grid grid-cols-[6.5rem_1fr] items-center gap-3"
              @mousemove="
                e =>
                  showTip(
                    e,
                    stageLabel(v.stage),
                    `${euro(v.total)} · ${t('TOLZAR_REPORTS.CONTACTS_N', { n: v.count })}`
                  )
              "
              @mouseleave="tip = null"
            >
              <span class="text-sm text-n-slate-12">{{
                stageLabel(v.stage)
              }}</span>
              <div>
                <div class="flex items-center gap-2">
                  <span
                    class="block h-6 rounded"
                    :style="{
                      width: `${Math.max(1, (v.total / pipeMax) * 100)}%`,
                      background: STAGE_VAR[v.stage],
                    }"
                  />
                  <span class="text-sm font-semibold text-n-slate-12">{{
                    euro(v.total)
                  }}</span>
                </div>
                <div class="mt-0.5 text-xs text-n-slate-10">
                  {{ t('TOLZAR_REPORTS.CONTACTS_N', { n: v.count }) }}
                </div>
              </div>
            </div>
          </div>
          <table v-else class="w-full text-sm">
            <thead>
              <tr class="text-xs text-n-slate-10">
                <th class="py-1.5 font-normal text-start">
                  {{ t('TOLZAR_REPORTS.COL.STAGE') }}
                </th>
                <th class="py-1.5 font-normal text-end">
                  {{ t('TOLZAR_REPORTS.COL.CONTACTS') }}
                </th>
                <th class="py-1.5 font-normal text-end">
                  {{ t('TOLZAR_REPORTS.COL.VALUE') }}
                </th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="v in values"
                :key="v.stage"
                class="border-t border-n-weak"
              >
                <td class="py-1.5">{{ stageLabel(v.stage) }}</td>
                <td class="py-1.5 text-end tabular-nums">{{ v.count }}</td>
                <td class="py-1.5 text-end tabular-nums">
                  {{ euro(v.total) }}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      <!-- Tolzar AI scoreboard -->
      <h2
        class="flex items-center gap-2 mt-7 mb-3 text-base font-semibold text-n-slate-12"
      >
        {{ t('TOLZAR_REPORTS.AI') }}
        <span
          class="px-2 py-0.5 text-[11px] font-semibold rounded-full bg-n-blue-3 text-n-blue-11"
          >{{ t('TOLZAR_REPORTS.AI_PILL') }}</span
        >
      </h2>
      <div
        v-if="sbError"
        class="p-4 text-sm border rounded-xl border-n-weak bg-n-solid-1 text-n-slate-11"
      >
        {{ t('TOLZAR_REPORTS.BRAIN_DOWN') }}
      </div>
      <template v-else-if="sb">
        <div
          class="flex flex-wrap items-center gap-3 p-4 mb-3 border rounded-xl border-n-weak bg-n-solid-1"
        >
          <span
            class="px-2 py-0.5 text-xs font-semibold rounded-full"
            :class="
              ready
                ? 'bg-n-teal-3 text-n-teal-11'
                : 'bg-n-amber-3 text-n-amber-11'
            "
            >{{
              ready ? t('TOLZAR_REPORTS.READY') : t('TOLZAR_REPORTS.NOT_READY')
            }}</span
          >
          <span class="text-lg font-semibold text-n-slate-12">{{
            t('TOLZAR_REPORTS.CHECKS', {
              pass: sb.passing,
              n: sb.checks.length,
            })
          }}</span>
          <span class="flex-1" />
          <span class="text-xs text-n-slate-10">
            {{ t('TOLZAR_REPORTS.SCORED', { n: sb.scored, days: sb.days }) }}
            ·
            {{ t('TOLZAR_REPORTS.MODEL', { model: modelName }) }}
          </span>
        </div>

        <div class="grid gap-3 md:grid-cols-2 xl:grid-cols-3">
          <div
            v-for="c in sb.checks"
            :key="c.key"
            class="p-4 border rounded-xl border-n-weak bg-n-solid-1"
          >
            <div class="flex items-start justify-between gap-2">
              <span class="text-sm text-n-slate-12">{{ checkLabel(c) }}</span>
              <span
                v-if="c.pass !== null"
                class="px-2 py-0.5 text-xs font-semibold rounded-full whitespace-nowrap"
                :class="
                  c.pass
                    ? 'bg-n-teal-3 text-n-teal-11'
                    : 'bg-n-amber-3 text-n-amber-11'
                "
                >{{
                  c.pass
                    ? `✓ ${t('TOLZAR_REPORTS.PASS')}`
                    : `! ${t('TOLZAR_REPORTS.WATCH')}`
                }}</span
              >
            </div>
            <div class="mt-1 text-xl font-semibold text-n-slate-12">
              {{ checkValue(c) }}
            </div>
            <div
              v-if="c.key !== 'price_leaks'"
              class="relative h-1.5 mt-2 rounded bg-n-slate-3"
            >
              <span
                class="absolute inset-y-0 left-0 rounded bg-n-brand"
                :style="{ width: `${Math.min(100, (c.value || 0) * 100)}%` }"
              />
              <span
                class="absolute w-0.5 h-3 -top-[3px] bg-n-slate-12 opacity-50"
                :style="{ left: `${c.target * 100}%` }"
              />
            </div>
            <div class="mt-1.5 text-xs text-n-slate-11">
              {{ checkTarget(c) }}
            </div>
          </div>
        </div>
        <p class="mt-2 mb-0 text-xs text-n-slate-10">
          <span v-if="sb.awaiting_staff"
            >{{
              t('TOLZAR_REPORTS.AWAITING', { n: sb.awaiting_staff })
            }}
            · </span
          >{{
            t('TOLZAR_REPORTS.GUARDS', {
              price: sb.guards.price_guard,
              policy: Object.values(sb.guards.output_policy || {}).reduce(
                (a, b) => a + b,
                0
              ),
              llm: sb.guards.llm_errors,
            })
          }}
        </p>

        <div
          v-if="byModel.length > 1"
          class="p-4 mt-3 border rounded-xl border-n-weak bg-n-solid-1"
        >
          <h3 class="m-0 text-sm font-semibold text-n-slate-12">
            {{ t('TOLZAR_REPORTS.BY_MODEL') }}
          </h3>
          <p class="mt-0.5 mb-3 text-xs text-n-slate-11">
            {{ t('TOLZAR_REPORTS.BY_MODEL_SUB') }}
          </p>
          <table class="w-full text-sm">
            <thead>
              <tr class="text-xs text-n-slate-10">
                <th class="py-1.5 font-normal text-start">
                  {{ t('TOLZAR_REPORTS.COL_MODEL') }}
                </th>
                <th class="py-1.5 font-normal text-end">
                  {{ t('TOLZAR_REPORTS.COL_SCORED') }}
                </th>
                <th class="py-1.5 font-normal text-end">
                  {{ t('TOLZAR_REPORTS.COL.AGREES') }}
                </th>
                <th class="py-1.5 font-normal text-end">
                  {{ t('TOLZAR_REPORTS.COL.ASKS') }}
                </th>
                <th class="py-1.5 font-normal text-end">
                  {{ t('TOLZAR_REPORTS.COL_P95') }}
                </th>
                <th class="py-1.5 font-normal text-end">
                  {{ t('TOLZAR_REPORTS.COL_PERIOD') }}
                </th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="m in byModel"
                :key="m.model"
                class="border-t border-n-weak"
              >
                <td class="py-1.5 text-n-slate-12">
                  {{ m.model }}
                  <span v-if="m.scored < FEW" class="text-xs text-n-amber-11">
                    {{ `· ${t('TOLZAR_REPORTS.FEW')}` }}
                  </span>
                </td>
                <td class="py-1.5 text-end tabular-nums">{{ m.scored }}</td>
                <td class="py-1.5 text-end tabular-nums">
                  {{ pct(m.agreement) }}
                </td>
                <td class="py-1.5 text-end tabular-nums">
                  {{ pct(m.ask_share) }}
                </td>
                <td class="py-1.5 text-end tabular-nums">
                  {{ duration(m.latency_p95_ms / 1000) }}
                </td>
                <td class="py-1.5 text-end tabular-nums text-n-slate-11">
                  {{ m.first.slice(5, 10) }} – {{ m.last.slice(5, 10) }}
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <div class="grid gap-3 mt-3 xl:grid-cols-[1.25fr_1fr]">
          <div class="p-4 border rounded-xl border-n-weak bg-n-solid-1">
            <div class="flex items-start justify-between gap-2">
              <div>
                <h3 class="m-0 text-sm font-semibold text-n-slate-12">
                  {{ t('TOLZAR_REPORTS.AI_TREND') }}
                </h3>
                <p class="mt-0.5 mb-2 text-xs text-n-slate-11">
                  {{ t('TOLZAR_REPORTS.AI_TREND_SUB') }}
                </p>
              </div>
              <button
                type="button"
                class="text-xs text-n-blue-11"
                @click="tables.ai = !tables.ai"
              >
                {{
                  tables.ai
                    ? t('TOLZAR_REPORTS.HIDE_TABLE')
                    : t('TOLZAR_REPORTS.SHOW_TABLE')
                }}
              </button>
            </div>
            <div class="flex flex-wrap gap-4 mb-1 text-xs text-n-slate-11">
              <span class="inline-flex items-center gap-1.5"
                ><span class="rounded size-2.5 tz-bg-s1" />{{
                  t('TOLZAR_REPORTS.COL.AGREES')
                }}</span
              >
              <span class="inline-flex items-center gap-1.5"
                ><span class="rounded size-2.5 tz-bg-s2" />{{
                  t('TOLZAR_REPORTS.COL.ASKS')
                }}</span
              >
              <span class="text-n-slate-10">{{
                t('TOLZAR_REPORTS.TARGET_LINE')
              }}</span>
            </div>
            <p v-if="!daily.length" class="text-sm text-n-slate-10">
              {{ t('TOLZAR_REPORTS.NO_DATA') }}
            </p>
            <svg
              v-else-if="!tables.ai"
              :viewBox="`0 0 ${LW} ${LH}`"
              class="w-full h-auto overflow-visible"
              @mousemove="onLineMove"
              @mouseleave="hover = null"
            >
              <g v-for="k in [0, 0.25, 0.5, 0.75, 1]" :key="k">
                <line
                  :x1="PAD.l"
                  :x2="LW - PAD.r"
                  :y1="yAt(k)"
                  :y2="yAt(k)"
                  class="stroke-n-slate-4"
                />
                <text
                  :x="PAD.l - 6"
                  :y="yAt(k) + 4"
                  text-anchor="end"
                  class="fill-n-slate-10 text-[11px]"
                >
                  {{ pct(k) }}
                </text>
              </g>
              <line
                :x1="PAD.l"
                :x2="LW - PAD.r"
                :y1="yAt(0.85)"
                :y2="yAt(0.85)"
                class="stroke-n-slate-9"
                stroke-dasharray="3 4"
              />
              <path
                :d="pathOf('agreement')"
                fill="none"
                stroke="var(--tz-s1)"
                stroke-width="2"
              />
              <path
                :d="pathOf('ask_share')"
                fill="none"
                stroke="var(--tz-s2)"
                stroke-width="2"
              />
              <text
                v-for="(d, i) in daily"
                v-show="
                  i % Math.ceil(daily.length / 6) === 0 ||
                  i === daily.length - 1
                "
                :key="d.day"
                :x="xAt(i)"
                :y="LH - 6"
                text-anchor="middle"
                class="fill-n-slate-10 text-[11px]"
              >
                {{ d.day.slice(5) }}
              </text>
              <line
                v-if="hover"
                :x1="xAt(hover.i)"
                :x2="xAt(hover.i)"
                :y1="PAD.t"
                :y2="LH - PAD.b"
                class="stroke-n-slate-9"
              />
            </svg>
            <table v-else class="w-full text-sm">
              <thead>
                <tr class="text-xs text-n-slate-10">
                  <th class="py-1.5 font-normal text-start">
                    {{ t('TOLZAR_REPORTS.COL.DAY') }}
                  </th>
                  <th class="py-1.5 font-normal text-end">
                    {{ t('TOLZAR_REPORTS.COL.AGREES') }}
                  </th>
                  <th class="py-1.5 font-normal text-end">
                    {{ t('TOLZAR_REPORTS.COL.ASKS') }}
                  </th>
                </tr>
              </thead>
              <tbody>
                <tr
                  v-for="d in daily"
                  :key="d.day"
                  class="border-t border-n-weak"
                >
                  <td class="py-1.5">{{ d.day }}</td>
                  <td class="py-1.5 text-end tabular-nums">
                    {{ pct(d.agreement) }}
                  </td>
                  <td class="py-1.5 text-end tabular-nums">
                    {{ pct(d.ask_share) }}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>

          <div class="p-4 border rounded-xl border-n-weak bg-n-solid-1">
            <h3 class="m-0 text-sm font-semibold text-n-slate-12">
              {{ t('TOLZAR_REPORTS.DISAGREE') }}
            </h3>
            <p class="mt-0.5 mb-3 text-xs text-n-slate-11">
              {{ t('TOLZAR_REPORTS.DISAGREE_SUB') }}
            </p>
            <p
              v-if="!sb.disagreements.length"
              class="mb-0 text-sm text-n-slate-10"
            >
              {{ t('TOLZAR_REPORTS.NONE_YET') }}
            </p>
            <table v-else class="w-full text-sm">
              <thead>
                <tr class="text-xs text-n-slate-10">
                  <th class="py-1.5 font-normal text-start">
                    {{ t('TOLZAR_REPORTS.COL.CONVERSATION') }}
                  </th>
                  <th class="py-1.5 font-normal text-start">
                    {{ t('TOLZAR_REPORTS.COL.WOULD') }}
                  </th>
                  <th class="py-1.5 font-normal text-start">
                    {{ t('TOLZAR_REPORTS.COL.STAFF') }}
                  </th>
                </tr>
              </thead>
              <tbody>
                <tr
                  v-for="d in sb.disagreements"
                  :key="d.conversation_id"
                  class="border-t border-n-weak"
                >
                  <td class="py-1.5">
                    <router-link
                      class="text-n-blue-11"
                      :to="{
                        name: 'inbox_conversation',
                        params: {
                          accountId,
                          conversation_id: d.conversation_id,
                        },
                      }"
                    >
                      {{ `#${d.conversation_id}` }}
                    </router-link>
                  </td>
                  <td class="py-1.5 capitalize">{{ wouldLabel(d.would) }}</td>
                  <td class="py-1.5">
                    <span class="capitalize">{{ d.staff }}</span>
                    <span v-if="d.staff_name" class="text-xs text-n-slate-10">
                      · {{ d.staff_name }}</span
                    >
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </template>
    </div>

    <div
      v-if="hover && daily[hover.i]"
      class="fixed z-50 px-3 py-2 text-xs border rounded-lg shadow-lg pointer-events-none border-n-weak bg-n-solid-1 text-n-slate-12"
      :style="{ left: `${hover.x + 14}px`, top: `${hover.y + 14}px` }"
    >
      <b class="block mb-0.5">{{ daily[hover.i].day }}</b>
      {{ t('TOLZAR_REPORTS.COL.AGREES') }}: {{ pct(daily[hover.i].agreement)
      }}<br />
      {{ t('TOLZAR_REPORTS.COL.ASKS') }}: {{ pct(daily[hover.i].ask_share) }}
    </div>
    <div
      v-if="tip"
      class="fixed z-50 px-3 py-2 text-xs border rounded-lg shadow-lg pointer-events-none border-n-weak bg-n-solid-1 text-n-slate-12"
      :style="{ left: `${tip.x + 14}px`, top: `${tip.y + 14}px` }"
    >
      <b class="block mb-0.5">{{ tip.title }}</b
      >{{ tip.body }}
    </div>
  </div>
</template>

<style scoped>
/* Stage/series hues validated with the dataviz checker (light + dark). Won/Lost sit in the
   CVD floor band, so every chart carries direct labels and a table view. */
.tz-rep {
  --tz-s1: #2a78d6;
  --tz-s2: #eda100;
  --tz-s3: #6250d6;
  --tz-s4: #1baf7a;
  --tz-s5: #e34948;
}
.tz-bg-s1 {
  background: var(--tz-s1);
}
.tz-bg-s2 {
  background: var(--tz-s2);
}
:global(.dark) .tz-rep {
  --tz-s1: #3987e5;
  --tz-s2: #c98500;
  --tz-s3: #9085e9;
  --tz-s4: #199e70;
  --tz-s5: #e66767;
}
</style>
