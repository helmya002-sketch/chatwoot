<script setup>
import { ref, onMounted, onBeforeUnmount, computed } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useLocale } from 'shared/composables/useLocale';
import ContactAPI from 'dashboard/api/contacts';
import {
  STAGES as SHARED_STAGES,
  defaultStage,
  applyPipelineStages,
  contactStage,
  loadStageAttributes,
  stageChipStyle,
  stageColor,
  stageIcon,
  stageOf,
} from 'dashboard/components-next/Tolzar/tolzarStages';
import {
  attentionCounts,
  attentionRows,
} from 'dashboard/components-next/Tolzar/tolzarAttention';
import { ago, fmtClock } from 'dashboard/components-next/Tolzar/tolzarTime';
import {
  BTN_GHOST,
  TONE_WARN,
  TONE_BAD,
  TONE_MUTED,
} from 'dashboard/components-next/Tolzar/settings/tzClasses';
import { OTHER_STAGES, stageCounts } from './tolzarReportsData';
import { useMapGetter, useStore } from 'dashboard/composables/store';

const route = useRoute();
const router = useRouter();
const store = useStore();
const { t } = useI18n();
const { resolvedLocale } = useLocale();
const accountId = computed(() => route.params.accountId);
const currentUser = useMapGetter('getCurrentUser');

// Team presence: the agents endpoint is account-wide, so this is open to administrators as a
// convenience only (Chatwoot gives every member the agents list; the gate is cosmetic).
const currentRole = useMapGetter('getCurrentRole');
const isManager = computed(() => currentRole.value === 'administrator');
const agents = useMapGetter('agents/getVerifiedAgents');
const PRESENCE = [
  { key: 'online', dot: 'bg-n-teal-9' },
  { key: 'busy', dot: 'bg-n-amber-9' },
  { key: 'offline', dot: 'bg-n-slate-9' },
];
const presence = computed(() => {
  const groups = { online: [], busy: [], offline: [] };
  (agents.value || []).forEach(a => {
    const s = a.availability_status || 'offline';
    (groups[s] || groups.offline).push(a);
  });
  return groups;
});
const onlineCount = computed(() => presence.value.online.length);
const agentTotal = computed(() => (agents.value || []).length);

// The viewer's time zone and when these numbers were last refreshed, so the figures are never
// read as "now" when they are minutes old.
const timezone = computed(() => {
  try {
    return Intl.DateTimeFormat().resolvedOptions().timeZone || '';
  } catch (e) {
    return '';
  }
});
const lastUpdated = ref(null);
const lastUpdatedLabel = computed(() =>
  lastUpdated.value ? fmtClock(lastUpdated.value, resolvedLocale.value) : ''
);
const firstName = computed(
  () =>
    (currentUser.value?.name || '').trim().split(' ')[0] ||
    t('TOLZAR_DASHBOARD.FALLBACK_NAME')
);
const greeting = computed(() => {
  const h = new Date().getHours();
  let part = 'EVENING';
  if (h < 12) part = 'MORNING';
  else if (h < 18) part = 'AFTERNOON';
  return t(`TOLZAR_DASHBOARD.GREETING.${part}`, { name: firstName.value });
});

// The workspace's stages (account setting, else the defaults) and their colours.
const getAccount = useMapGetter('accounts/getAccount');
const STAGES = computed(() =>
  SHARED_STAGES.map(s => ({
    ...s,
    color: stageColor(s.key),
    icon: stageIcon(s.key),
  }))
);
// Chart hues live in CSS variables (see <style>), one per series, with a dark override.
const SERIES = 6;
// Staggered entrance delay for a card (inline so the list order decides it).
const rise = ms => ({ animationDelay: `${ms}ms` });
const seriesVar = i => `var(--tz-s${(i % SERIES) + 1})`;

const counts = ref({});
const conversations = ref([]);
const openMeta = ref({});
const teamCounts = ref([]);
const totalContacts = ref(0);
const loaded = ref(false);
const errored = ref(false);
const refreshing = ref(false);

const stageKeys = computed(() => STAGES.value.map(s => s.key));
// Won and lost are the last two stages of the list (the defaults end with Won, Lost).
const wonKey = computed(() => stageKeys.value[stageKeys.value.length - 2]);
const lostKey = computed(() => stageKeys.value[stageKeys.value.length - 1]);
const total = computed(() => totalContacts.value);
const won = computed(() => counts.value[wonKey.value] || 0);
const lost = computed(() => counts.value[lostKey.value] || 0);
// In progress: the stages between the first (new) and the last two (won, lost).
const pipeline = computed(() =>
  stageKeys.value.slice(1, -2).reduce((a, k) => a + (counts.value[k] || 0), 0)
);
const otherStages = computed(() => counts.value[OTHER_STAGES] || 0);
const winRate = computed(() => {
  const decided = won.value + lost.value;
  return decided ? Math.round((won.value / decided) * 100) : 0;
});
const openConvs = computed(() => openMeta.value.all_count || 0);
const unassigned = computed(() => openMeta.value.unassigned_count || 0);
const funnelMax = computed(() =>
  Math.max(1, ...STAGES.value.map(s => counts.value[s.key] || 0))
);

// Open conversations per team, counted by the server (not from one page of the list).
const teamDist = computed(() => {
  const max = Math.max(1, ...teamCounts.value.map(x => x.n));
  return teamCounts.value
    .filter(x => x.n > 0)
    .sort((a, b) => b.n - a.n)
    .map((x, i) => ({
      ...x,
      pct: Math.round((x.n / max) * 100),
      color: seriesVar(i),
    }));
});

const recent = computed(() =>
  [...conversations.value]
    .sort((a, b) => (b.last_activity_at || 0) - (a.last_activity_at || 0))
    .slice(0, 6)
    .map(c => ({
      id: c.id,
      name: c.meta?.sender?.name || t('TOLZAR_DASHBOARD.UNKNOWN'),
      snippet: (c.last_non_activity_message?.content || '').slice(0, 72),
      team: c.meta?.team?.name || '',
      stage: contactStage(c.meta?.sender?.custom_attributes) || defaultStage(),
      ts: c.last_activity_at,
      assignee: c.meta?.assignee?.name || '',
    }))
);

// "Needs attention": hot, unanswered and unassigned open conversations, from the list already
// loaded (the first page of open conversations). One click opens the conversation.
const attention = computed(() => attentionRows(conversations.value));
const attentionTotals = computed(() => attentionCounts(conversations.value));
const REASON_TONE = {
  hot: TONE_BAD,
  waiting: TONE_WARN,
  unassigned: TONE_MUTED,
};
const reasonLabel = (row, k) =>
  k === 'hot' && row.score !== null
    ? `${t('TOLZAR_DASHBOARD.ATTENTION.HOT')} · ${t('TOLZAR_DASHBOARD.ATTENTION.SCORE', { n: row.score })}`
    : t(`TOLZAR_DASHBOARD.ATTENTION.${k.toUpperCase()}`);

const na = computed(() => t('TOLZAR_UI.NOT_AVAILABLE'));
const kpis = computed(() => [
  {
    k: t('TOLZAR_DASHBOARD.KPI.TOTAL_CONTACTS'),
    v: total.value,
    icon: 'i-lucide-users',
    sub: [
      t('TOLZAR_DASHBOARD.KPI.IN_PROGRESS', { n: pipeline.value }),
      otherStages.value
        ? t('TOLZAR_DASHBOARD.KPI.OTHER_STAGES', { n: otherStages.value })
        : '',
    ]
      .filter(Boolean)
      .join(' · '),
    accent: seriesVar(0),
    go: 'contacts_dashboard_index',
  },
  {
    k: t('TOLZAR_DASHBOARD.KPI.OPEN_CONVERSATIONS'),
    v: openConvs.value,
    icon: 'i-lucide-messages-square',
    sub: t('TOLZAR_DASHBOARD.KPI.UNASSIGNED', { n: unassigned.value }),
    accent: seriesVar(1),
    go: 'home',
  },
  {
    k: stageOf(wonKey.value).label,
    v: won.value,
    icon: 'i-lucide-trophy',
    sub: `${lost.value} ${stageOf(lostKey.value).label.toLowerCase()}`,
    accent: seriesVar(3),
    go: 'tolzar_pipeline',
  },
  {
    k: t('TOLZAR_DASHBOARD.KPI.WIN_RATE'),
    v: `${winRate.value}%`,
    icon: 'i-lucide-target',
    sub: t('TOLZAR_DASHBOARD.KPI.WIN_RATE_SUB'),
    hint: t('TOLZAR_DASHBOARD.KPI.WIN_RATE_HINT'),
    accent: seriesVar(2),
    go: 'tolzar_reports',
  },
]);

function initials(name) {
  return (name || '?')
    .split(' ')
    .map(w => w[0])
    .join('')
    .slice(0, 2)
    .toUpperCase();
}
const since = ts => (ts ? ago(new Date(ts * 1000), resolvedLocale.value) : '');
function go(name) {
  if (!name) return;
  router.push({ name, params: { accountId: accountId.value } }).catch(() => {});
}
function openConversation(id) {
  router.push({
    name: 'inbox_conversation',
    params: { accountId: accountId.value, conversation_id: id },
  });
}

const openMetaFor = async (params = '') => {
  const { data } = await window.axios.get(
    `/api/v1/accounts/${accountId.value}/conversations/meta?status=open${params}`
  );
  return data?.meta || {};
};

// Every team's open conversations in one request (tolzar/team_summary), not one per team (N+1).
async function loadTeams() {
  const { data } = await window.axios.get(
    `/api/v1/accounts/${accountId.value}/tolzar/team_summary`
  );
  const rows = (data?.teams || []).map(team => ({
    name: team.name,
    n: team.open || 0,
  }));
  teamCounts.value = [
    ...rows,
    {
      name: t('TOLZAR_DASHBOARD.NO_TEAM'),
      n: Math.max(0, data?.no_team?.open || 0),
    },
  ];
}

// The workspace's first-run checklist (open to every administrator): a card until it is done.
const setup = ref(null);
const setupOpen = computed(
  () => setup.value && setup.value.total && setup.value.done < setup.value.total
);
async function loadSetup() {
  try {
    const { data } = await window.axios.get(
      `/api/v1/accounts/${accountId.value}/tolzar/workspace/checklist`
    );
    setup.value = data && data.ok !== false ? data : null;
  } catch (e) {
    setup.value = null;
  }
}

async function load() {
  if (refreshing.value) return;
  refreshing.value = true;
  errored.value = false;
  applyPipelineStages(getAccount.value(accountId.value)?.settings);
  try {
    await loadStageAttributes(accountId.value);
    const [stageCountsOut, contactsTotal, meta] = await Promise.all([
      stageCounts(),
      ContactAPI.get(1).then(({ data }) => data?.meta?.count || 0),
      openMetaFor(),
    ]);
    counts.value = stageCountsOut;
    totalContacts.value = contactsTotal;
    openMeta.value = meta;
    await Promise.all([
      loadTeams().catch(() => {}),
      window.axios
        .get(`/api/v1/accounts/${accountId.value}/conversations?status=open`)
        .then(({ data }) => {
          conversations.value = data?.data?.payload || [];
        })
        .catch(() => {}),
    ]);
  } catch (e) {
    errored.value = true;
  } finally {
    loaded.value = true;
    refreshing.value = false;
    lastUpdated.value = new Date();
    loadSetup();
  }
}

// Auto-refresh every 5 minutes while the tab is visible; a hidden tab refreshes on return.
const REFRESH_MS = 5 * 60_000;
let timer = null;
const tick = () => {
  if (document.visibilityState === 'visible') load();
};
const onVisible = () => {
  if (
    document.visibilityState === 'visible' &&
    lastUpdated.value &&
    Date.now() - lastUpdated.value.getTime() > REFRESH_MS
  )
    load();
};

onMounted(() => {
  store.dispatch('agents/get').catch(() => {});
  load();
  timer = setInterval(tick, REFRESH_MS);
  document.addEventListener('visibilitychange', onVisible);
});
onBeforeUnmount(() => {
  if (timer) clearInterval(timer);
  document.removeEventListener('visibilitychange', onVisible);
});
</script>

<template>
  <div class="overflow-auto flex-1 bg-n-background" data-tz-build="dash-7">
    <div class="tz-dash mx-auto max-w-[1200px] px-5 pb-16 pt-6 md:px-7">
      <!-- a failed load: say so at the top, with a way back -->
      <div
        v-if="errored"
        class="flex flex-wrap gap-3 justify-between items-center p-3 mb-4 text-[13px] rounded-xl"
        :class="TONE_BAD"
        role="alert"
      >
        <span>{{ t('TOLZAR_UI.LOAD_FAILED') }}</span>
        <button
          type="button"
          class="px-3 h-8 text-xs font-semibold rounded-lg border border-solid border-current bg-transparent cursor-pointer"
          :disabled="refreshing"
          @click="load"
        >
          {{ t('TOLZAR_UI.RETRY') }}
        </button>
      </div>

      <!-- hero header -->
      <div
        class="tz-rise tz-hero overflow-hidden relative p-6 rounded-3xl border shadow-sm md:p-7 bg-n-solid-1 border-n-weak"
        :style="rise(0)"
      >
        <span
          class="tz-hero-glow absolute rounded-full pointer-events-none bg-n-brand/10 blur-3xl"
          aria-hidden="true"
        />
        <div class="flex relative flex-wrap gap-5 justify-between items-center">
          <div class="flex gap-4 items-center min-w-0">
            <span
              class="grid flex-shrink-0 place-content-center rounded-2xl size-14 shadow-md bg-n-brand"
            >
              <span class="i-lucide-layout-dashboard size-7 text-white" />
            </span>
            <div class="min-w-0">
              <div
                class="flex gap-2 items-center text-[11px] font-semibold tracking-[0.14em] uppercase text-n-brand"
              >
                <span
                  class="inline-block rounded-full size-1.5 bg-n-brand tz-pulse"
                />
                {{ t('TOLZAR_DASHBOARD.TITLE') }}
              </div>
              <h1
                class="mt-1 text-2xl font-extrabold tracking-tight md:text-[26px] text-n-slate-12"
              >
                {{ greeting }}
              </h1>
              <p class="mt-1 mb-0 text-sm text-n-slate-11">
                {{
                  loaded
                    ? t('TOLZAR_DASHBOARD.SUMMARY', {
                        open: openConvs,
                        won,
                        rate: winRate,
                      })
                    : t('TOLZAR_DASHBOARD.LOADING')
                }}
              </p>
              <p
                v-if="loaded"
                class="flex flex-wrap gap-x-2 gap-y-0.5 items-center mt-1 mb-0 text-[11px] text-n-slate-10"
              >
                <span v-if="timezone" class="inline-flex gap-1 items-center">
                  <span class="i-lucide-globe size-3" />
                  {{ t('TOLZAR_UI.YOUR_TIME_ZONE', { zone: timezone }) }}
                </span>
                <span
                  v-if="lastUpdatedLabel"
                  class="inline-flex gap-1 items-center"
                >
                  <span class="i-lucide-refresh-cw size-3" />
                  {{
                    t('TOLZAR_DASHBOARD.UPDATED', { time: lastUpdatedLabel })
                  }}
                </span>
              </p>
            </div>
          </div>
          <div class="flex flex-wrap gap-2.5 items-center">
            <button
              type="button"
              :class="BTN_GHOST"
              class="!mt-0 gap-1.5"
              :disabled="refreshing"
              :aria-label="t('TOLZAR_DASHBOARD.REFRESH')"
              @click="load"
            >
              <span
                class="i-lucide-refresh-cw size-4"
                :class="{ 'animate-spin': refreshing }"
              />
              {{
                refreshing
                  ? t('TOLZAR_DASHBOARD.REFRESHING')
                  : t('TOLZAR_DASHBOARD.REFRESH')
              }}
            </button>
            <button
              v-if="loaded && unassigned > 0"
              type="button"
              class="inline-flex gap-1.5 items-center px-3 h-9 text-[13px] font-semibold rounded-xl border border-solid border-current transition-colors"
              :class="TONE_WARN"
              @click="go('home')"
            >
              <span class="i-lucide-alert-circle size-4" />
              {{ t('TOLZAR_DASHBOARD.TO_ASSIGN', { n: unassigned }) }}
            </button>
            <button
              type="button"
              class="inline-flex gap-2 items-center px-4 h-9 text-sm font-semibold text-white rounded-xl shadow-sm transition-all bg-n-brand hover:opacity-90 hover:shadow-md"
              @click="go('home')"
            >
              <span class="i-lucide-inbox size-4" />
              {{ t('TOLZAR_DASHBOARD.OPEN_INBOX') }}
            </button>
          </div>
        </div>
      </div>

      <!-- first-run setup: until the workspace's checklist is done -->
      <div
        v-if="setupOpen"
        class="flex flex-wrap gap-3 justify-between items-center p-4 mt-4 rounded-2xl border bg-n-solid-1 border-n-weak"
        data-tz-setup-card
      >
        <div class="min-w-0">
          <div class="text-[14px] font-semibold text-n-slate-12">
            {{ t('TOLZAR_ONBOARDING.CARD_TITLE') }}
          </div>
          <div class="text-[13px] text-n-slate-11">
            {{
              t('TOLZAR_ONBOARDING.CARD_PROGRESS', {
                done: setup.done,
                total: setup.total,
              })
            }}
          </div>
        </div>
        <button
          type="button"
          class="inline-flex items-center px-4 h-9 text-sm font-semibold text-white rounded-xl border-0 cursor-pointer bg-n-brand"
          @click="go('tolzar_onboarding')"
        >
          {{ t('TOLZAR_ONBOARDING.CARD_OPEN') }}
        </button>
      </div>

      <!-- KPI cards -->
      <div class="grid grid-cols-2 gap-3.5 mt-4 lg:grid-cols-4">
        <button
          v-for="(k, i) in kpis"
          :key="k.k"
          v-tooltip.top="errored ? t('TOLZAR_UI.LOAD_FAILED') : k.hint || ''"
          type="button"
          class="tz-rise tz-card tz-hover overflow-hidden relative p-4 w-full text-left rounded-2xl border shadow-sm cursor-pointer bg-n-solid-1 border-n-weak"
          :style="rise(60 + i * 50)"
          :aria-label="`${k.k}: ${loaded ? (errored ? na : k.v) : ''}`"
          @click="go(k.go)"
        >
          <span
            class="tz-accent"
            :style="{ background: k.accent }"
            aria-hidden="true"
          />
          <div class="flex gap-2.5 items-center">
            <span
              class="grid place-content-center rounded-xl size-9 bg-n-alpha-2"
              :style="{ color: k.accent }"
            >
              <span :class="k.icon" class="size-[18px]" />
            </span>
            <div class="text-xs font-medium leading-tight text-n-slate-11">
              {{ k.k }}
            </div>
          </div>
          <div
            class="mt-3 text-[34px] font-extrabold leading-none tabular-nums text-n-slate-12"
            :class="{ 'text-n-slate-10 text-2xl': errored }"
          >
            <template v-if="!loaded">—</template>
            <template v-else-if="errored">{{ na }}</template>
            <template v-else>{{ k.v }}</template>
          </div>
          <div class="mt-1.5 text-xs text-n-slate-10">{{ k.sub }}</div>
        </button>
      </div>

      <!-- needs attention -->
      <div
        class="tz-rise mt-3.5 rounded-2xl border shadow-sm bg-n-solid-1 border-n-weak"
        :style="rise(260)"
        data-tz-attention
      >
        <div
          class="flex flex-wrap gap-2 justify-between items-center px-5 py-4 border-b border-n-weak"
        >
          <h3 class="m-0 text-sm font-semibold text-n-slate-12">
            {{ t('TOLZAR_DASHBOARD.ATTENTION.TITLE') }}
          </h3>
          <div v-if="loaded" class="flex flex-wrap gap-1.5">
            <span
              v-if="attentionTotals.hot"
              class="px-2 py-0.5 text-[11px] font-semibold rounded-full"
              :class="TONE_BAD"
            >
              {{
                t('TOLZAR_DASHBOARD.ATTENTION.HOT_N', {
                  n: attentionTotals.hot,
                })
              }}
            </span>
            <span
              v-if="attentionTotals.waiting"
              class="px-2 py-0.5 text-[11px] font-semibold rounded-full"
              :class="TONE_WARN"
            >
              {{
                t('TOLZAR_DASHBOARD.ATTENTION.WAITING_N', {
                  n: attentionTotals.waiting,
                })
              }}
            </span>
            <span
              v-if="attentionTotals.unassigned"
              class="px-2 py-0.5 text-[11px] font-semibold rounded-full"
              :class="TONE_MUTED"
            >
              {{
                t('TOLZAR_DASHBOARD.ATTENTION.UNASSIGNED_N', {
                  n: attentionTotals.unassigned,
                })
              }}
            </span>
          </div>
        </div>
        <div v-if="loaded && attention.length">
          <button
            v-for="r in attention"
            :key="r.id"
            type="button"
            class="flex gap-3 items-center px-5 py-2.5 w-full text-left border-b transition-colors border-n-weak last:border-0 hover:bg-n-alpha-1"
            @click="openConversation(r.id)"
          >
            <span
              class="grid flex-shrink-0 place-content-center text-xs font-bold rounded-full size-8 bg-n-alpha-2 text-n-slate-11"
            >
              {{ initials(r.name || t('TOLZAR_DASHBOARD.UNKNOWN')) }}
            </span>
            <span class="flex-1 min-w-0">
              <span
                class="block text-sm font-semibold truncate text-n-slate-12"
              >
                {{ r.name || t('TOLZAR_DASHBOARD.UNKNOWN') }}
              </span>
              <span class="flex flex-wrap gap-1 mt-0.5">
                <span
                  v-for="k in r.reasons"
                  :key="k"
                  class="px-1.5 py-0.5 text-[10px] font-semibold leading-none rounded-full whitespace-nowrap"
                  :class="REASON_TONE[k]"
                >
                  {{ reasonLabel(r, k) }}
                </span>
              </span>
            </span>
            <span
              class="flex flex-col flex-shrink-0 gap-1 items-end text-[11px] text-n-slate-10"
            >
              <span v-if="r.assignee" class="font-medium text-n-slate-11">{{
                r.assignee
              }}</span>
              <span>{{ since(r.since) }}</span>
            </span>
            <span
              class="i-lucide-arrow-right size-4 text-n-slate-10 rtl:rotate-180"
            />
          </button>
        </div>
        <div v-else-if="loaded" class="px-5 py-6">
          <p class="m-0 text-sm font-semibold text-n-slate-12">
            {{ t('TOLZAR_DASHBOARD.ATTENTION.EMPTY') }}
          </p>
          <p class="mt-1 mb-0 text-xs text-n-slate-10">
            {{ t('TOLZAR_DASHBOARD.ATTENTION.EMPTY_HINT') }}
          </p>
        </div>
        <p v-else class="px-5 py-6 text-xs text-n-slate-10">
          {{ t('TOLZAR_UI.LOADING') }}
        </p>
      </div>

      <!-- funnel + team -->
      <div class="grid grid-cols-1 gap-3.5 mt-3.5 lg:grid-cols-3">
        <!-- lifecycle funnel -->
        <div
          class="tz-rise p-5 rounded-2xl border shadow-sm lg:col-span-2 bg-n-solid-1 border-n-weak"
          :style="rise(300)"
        >
          <div class="flex justify-between items-center mb-4">
            <h3 class="m-0 text-sm font-semibold text-n-slate-12">
              {{ t('TOLZAR_DASHBOARD.FUNNEL') }}
            </h3>
            <span
              class="px-2 py-0.5 text-[11px] font-medium rounded-full bg-n-alpha-2 text-n-slate-11"
            >
              {{ t('TOLZAR_DASHBOARD.CONTACTS_N', { n: total }) }}
            </span>
          </div>
          <div
            v-for="s in STAGES"
            :key="s.key"
            class="grid gap-3 items-center mb-3 last:mb-0 grid-cols-[112px_1fr_60px] md:grid-cols-[150px_1fr_72px]"
          >
            <div class="flex gap-2 items-center min-w-0">
              <span
                class="grid place-content-center rounded-lg size-6"
                :style="stageChipStyle(s.key)"
              >
                <span :class="s.icon" class="size-3.5" />
              </span>
              <span class="text-sm font-semibold truncate text-n-slate-11">{{
                s.label
              }}</span>
            </div>
            <div class="overflow-hidden h-7 rounded-lg bg-n-alpha-2">
              <div
                class="h-full rounded-lg transition-[width] duration-700 ease-out"
                :style="{
                  width:
                    (loaded
                      ? Math.max(
                          5,
                          Math.round(((counts[s.key] || 0) / funnelMax) * 100)
                        )
                      : 0) + '%',
                  background: s.color,
                }"
              />
            </div>
            <div class="font-extrabold text-right text-n-slate-12 tabular-nums">
              {{ loaded ? counts[s.key] || 0 : '—' }}
              <span class="block text-[10px] font-medium text-n-slate-10">
                {{
                  total ? Math.round(((counts[s.key] || 0) / total) * 100) : 0
                }}%
              </span>
            </div>
          </div>
        </div>

        <!-- right column: team mix + (managers) live presence -->
        <div class="flex flex-col gap-3.5">
          <div
            class="tz-rise p-5 rounded-2xl border shadow-sm bg-n-solid-1 border-n-weak"
            :style="rise(350)"
          >
            <h3 class="m-0 mb-4 text-sm font-semibold text-n-slate-12">
              {{ t('TOLZAR_DASHBOARD.BY_TEAM') }}
            </h3>
            <div v-if="loaded && teamDist.length">
              <div v-for="x in teamDist" :key="x.name" class="mb-3.5 last:mb-0">
                <div class="flex justify-between mb-1 text-xs">
                  <span
                    class="font-semibold capitalize truncate text-n-slate-11"
                    >{{ x.name }}</span
                  >
                  <span class="font-bold text-n-slate-12 tabular-nums">{{
                    x.n
                  }}</span>
                </div>
                <div class="overflow-hidden h-2 rounded-full bg-n-alpha-2">
                  <div
                    class="h-full rounded-full transition-[width] duration-700"
                    :style="{ width: x.pct + '%', background: x.color }"
                  />
                </div>
              </div>
            </div>
            <p v-else class="text-xs text-n-slate-10">
              {{ t('TOLZAR_DASHBOARD.NO_CONVERSATIONS') }}
            </p>
          </div>

          <div
            v-if="isManager"
            class="tz-rise p-5 rounded-2xl border shadow-sm bg-n-solid-1 border-n-weak"
            :style="rise(380)"
          >
            <div class="flex justify-between items-center mb-4">
              <h3 class="m-0 text-sm font-semibold text-n-slate-12">
                {{ t('TOLZAR_DASHBOARD.PRESENCE.TITLE') }}
              </h3>
              <span
                class="px-2 py-0.5 text-[11px] font-medium rounded-full bg-n-alpha-2 text-n-slate-11"
              >
                {{
                  t('TOLZAR_DASHBOARD.PRESENCE.ONLINE_OF', {
                    online: onlineCount,
                    total: agentTotal,
                  })
                }}
              </span>
            </div>
            <div v-if="agentTotal">
              <div v-for="p in PRESENCE" :key="p.key" class="mb-3 last:mb-0">
                <div class="flex gap-1.5 items-center mb-1.5">
                  <span
                    class="inline-block rounded-full size-2"
                    :class="p.dot"
                  />
                  <span class="text-xs font-semibold text-n-slate-11">
                    {{ t(`TOLZAR_DASHBOARD.PRESENCE.${p.key.toUpperCase()}`) }}
                  </span>
                  <span
                    class="text-[11px] font-bold text-n-slate-12 tabular-nums"
                  >
                    {{ presence[p.key].length }}
                  </span>
                </div>
                <div
                  v-if="presence[p.key].length"
                  class="flex flex-wrap gap-1.5"
                >
                  <span
                    v-for="a in presence[p.key].slice(0, 10)"
                    :key="a.id"
                    v-tooltip.top="a.name"
                    class="grid relative place-content-center text-[10px] font-bold rounded-full size-7 bg-n-alpha-2 text-n-slate-11"
                    :class="{ 'opacity-60': p.key === 'offline' }"
                  >
                    {{ initials(a.name) }}
                    <span
                      class="absolute -bottom-0.5 ltr:-right-0.5 rtl:-left-0.5 rounded-full size-2.5 ring-2 ring-n-solid-1"
                      :class="p.dot"
                    />
                  </span>
                  <span
                    v-if="presence[p.key].length > 10"
                    class="grid place-content-center text-[10px] font-semibold rounded-full size-7 bg-n-alpha-2 text-n-slate-10"
                  >
                    +{{ presence[p.key].length - 10 }}
                  </span>
                </div>
              </div>
            </div>
            <p v-else class="text-xs text-n-slate-10">
              {{ t('TOLZAR_DASHBOARD.PRESENCE.NONE') }}
            </p>
          </div>
        </div>
      </div>

      <!-- recent conversations -->
      <div
        class="tz-rise mt-3.5 rounded-2xl border shadow-sm bg-n-solid-1 border-n-weak"
        :style="rise(400)"
      >
        <div
          class="flex justify-between items-center px-5 py-4 border-b border-n-weak"
        >
          <h3 class="m-0 text-sm font-semibold text-n-slate-12">
            {{ t('TOLZAR_DASHBOARD.RECENT') }}
          </h3>
          <button
            type="button"
            class="inline-flex gap-1 items-center text-xs font-semibold text-n-brand hover:underline"
            @click="go('home')"
          >
            {{ t('TOLZAR_DASHBOARD.VIEW_ALL') }}
            <span class="i-lucide-arrow-right size-3.5 rtl:rotate-180" />
          </button>
        </div>
        <div v-if="loaded && recent.length">
          <button
            v-for="r in recent"
            :key="r.id"
            type="button"
            class="flex gap-3 items-center px-5 py-3 w-full text-left border-b transition-colors border-n-weak last:border-0 hover:bg-n-alpha-1"
            @click="openConversation(r.id)"
          >
            <span
              class="grid flex-shrink-0 place-content-center text-xs font-bold rounded-full size-9 bg-n-alpha-2 text-n-slate-11"
            >
              {{ initials(r.name) }}
            </span>
            <span class="flex-1 min-w-0">
              <span class="flex gap-2 items-center">
                <span class="text-sm font-semibold truncate text-n-slate-12">{{
                  r.name
                }}</span>
                <span
                  v-if="r.stage"
                  class="px-1.5 py-0.5 text-[10px] font-semibold leading-none rounded-full whitespace-nowrap"
                  :style="stageChipStyle(r.stage)"
                >
                  {{ stageOf(r.stage).label }}
                </span>
              </span>
              <span class="block text-xs truncate text-n-slate-10">
                {{ r.snippet || t('TOLZAR_DASHBOARD.NO_MESSAGES') }}
              </span>
            </span>
            <span class="flex flex-col flex-shrink-0 gap-1 items-end">
              <span
                v-if="r.team"
                class="text-[11px] font-medium capitalize text-n-slate-11"
                >{{ r.team }}</span
              >
              <span class="text-[11px] text-n-slate-10">{{ since(r.ts) }}</span>
            </span>
          </button>
        </div>
        <p v-else class="px-5 py-6 text-xs text-n-slate-10">
          {{ t('TOLZAR_DASHBOARD.NO_CONVERSATIONS') }}
        </p>
      </div>

      <!-- quick links -->
      <div class="grid grid-cols-1 gap-3.5 mt-3.5 md:grid-cols-3">
        <button
          v-for="(q, i) in [
            {
              name: 'tolzar_ai_agents',
              icon: 'i-lucide-bot',
              key: 'AI_AGENTS',
            },
            {
              name: 'tolzar_workflows',
              icon: 'i-lucide-workflow',
              key: 'WORKFLOWS',
            },
            { name: 'home', icon: 'i-lucide-inbox', key: 'INBOX' },
          ]"
          :key="q.name"
          type="button"
          class="tz-rise tz-card tz-hover flex gap-3 items-center p-4 text-left rounded-2xl border shadow-sm cursor-pointer bg-n-solid-1 border-n-weak"
          :style="rise(450 + i * 50)"
          @click="go(q.name)"
        >
          <span
            class="grid flex-shrink-0 place-content-center rounded-xl size-10 bg-n-alpha-2"
          >
            <span :class="q.icon" class="size-5 text-n-brand" />
          </span>
          <span class="min-w-0">
            <span class="block font-semibold truncate text-n-slate-12">
              {{ t(`TOLZAR_DASHBOARD.LINKS.${q.key}`) }}
            </span>
            <span class="block text-xs truncate text-n-slate-11">
              {{ t(`TOLZAR_DASHBOARD.LINKS.${q.key}_SUB`) }}
            </span>
          </span>
          <span
            class="ltr:ml-auto rtl:mr-auto i-lucide-arrow-right size-4 text-n-brand rtl:rotate-180"
          />
        </button>
      </div>
    </div>
  </div>
</template>

<style scoped>
/* Series hues for the KPI accents and the team bars (same scale as TolzarReports), with a dark
   override; stage colours come from tolzarStages. No raw brand hex: the brand utilities follow
   the workspace's white-label colour. */
.tz-dash {
  --tz-s1: #2a78d6;
  --tz-s2: #0e9aa7;
  --tz-s3: #6250d6;
  --tz-s4: #1baf7a;
  --tz-s5: #c2559a;
  --tz-s6: #6b7a90;
}
:global(.dark) .tz-dash {
  --tz-s1: #3987e5;
  --tz-s2: #27b0bd;
  --tz-s3: #9085e9;
  --tz-s4: #199e70;
  --tz-s5: #d070b0;
  --tz-s6: #8d9bb0;
}
.tz-hero-glow {
  inset-inline-end: -60px;
  top: -70px;
  width: 240px;
  height: 240px;
}
/* KPI accent bar */
.tz-card {
  transition:
    transform 0.18s ease,
    box-shadow 0.18s ease;
}
.tz-accent {
  position: absolute;
  inset-inline: 0;
  top: 0;
  height: 3px;
  opacity: 0.9;
}
.tz-hover:hover {
  transform: translateY(-2px);
  box-shadow: 0 12px 26px -14px rgba(15, 23, 42, 0.28);
}
.tz-pulse {
  animation: tz-pulse 2s ease-in-out infinite;
}
@keyframes tz-pulse {
  0%,
  100% {
    opacity: 1;
    transform: scale(1);
  }
  50% {
    opacity: 0.45;
    transform: scale(0.82);
  }
}
/* staggered entrance */
.tz-rise {
  opacity: 0;
  animation: tz-rise 0.5s cubic-bezier(0.22, 1, 0.36, 1) forwards;
}
@keyframes tz-rise {
  from {
    opacity: 0;
    transform: translateY(10px);
  }
  to {
    opacity: 1;
    transform: translateY(0);
  }
}
@media (prefers-reduced-motion: reduce) {
  .tz-rise,
  .tz-pulse {
    animation: none;
    opacity: 1;
  }
}
</style>
