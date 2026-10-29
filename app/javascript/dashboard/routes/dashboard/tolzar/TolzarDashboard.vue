<script setup>
import { ref, onMounted, computed } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import ContactAPI from 'dashboard/api/contacts';
import {
  STAGES as SHARED_STAGES,
  defaultStage,
  applyPipelineStages,
  contactStage,
  loadStageAttributes,
  stageColor,
  stageIcon,
  stageOf,
} from 'dashboard/components-next/Tolzar/tolzarStages';
import { stageCounts } from './tolzarReportsData';
import { useMapGetter, useStore } from 'dashboard/composables/store';

const route = useRoute();
const router = useRouter();
const store = useStore();
const accountId = computed(() => route.params.accountId);
const currentUser = useMapGetter('getCurrentUser');

// Tolzar D1: a manager (administrator) sees every agent's presence, across all
// teams — the agents endpoint is account-wide, so no per-team scoping is needed.
const currentRole = useMapGetter('getCurrentRole');
const isManager = computed(() => currentRole.value === 'administrator');
const agents = useMapGetter('agents/getVerifiedAgents');
const PRESENCE = [
  { key: 'online', label: 'Online', color: '#10b981' },
  { key: 'busy', label: 'Busy', color: '#f59e0b' },
  { key: 'offline', label: 'Offline', color: '#94a3b8' },
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

// Tolzar D2: surface the viewer's timezone and when these numbers were last
// refreshed, so the figures are never read as "now" when they are minutes old.
const timezone = computed(() => {
  try {
    return Intl.DateTimeFormat().resolvedOptions().timeZone || '';
  } catch (e) {
    return '';
  }
});
const lastUpdated = ref(null);
const lastUpdatedLabel = computed(() => {
  if (!lastUpdated.value) return '';
  try {
    return lastUpdated.value.toLocaleTimeString([], {
      hour: '2-digit',
      minute: '2-digit',
    });
  } catch (e) {
    return '';
  }
});
const firstName = computed(
  () => (currentUser.value?.name || '').trim().split(' ')[0] || 'there'
);
const greeting = computed(() => {
  const h = new Date().getHours();
  if (h < 12) return 'Good morning';
  if (h < 18) return 'Good afternoon';
  return 'Good evening';
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
const TEAM_COLORS = ['#3e63dd', '#0ea5e9', '#8b5cf6', '#f59e0b', '#ec4899', '#64748b'];

const counts = ref({});
const conversations = ref([]);
const openMeta = ref({});
const teamCounts = ref([]);
const totalContacts = ref(0);
const loaded = ref(false);
const errored = ref(false);

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
const otherStages = computed(() => counts.value.__other || 0);
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
  const max = Math.max(1, ...teamCounts.value.map(t => t.n));
  return teamCounts.value
    .filter(t => t.n > 0)
    .sort((a, b) => b.n - a.n)
    .map((t, i) => ({ ...t, pct: Math.round((t.n / max) * 100), color: TEAM_COLORS[i % TEAM_COLORS.length] }));
});

const recent = computed(() =>
  [...conversations.value]
    .sort((a, b) => (b.last_activity_at || 0) - (a.last_activity_at || 0))
    .slice(0, 6)
    .map(c => ({
      id: c.id,
      name: c.meta?.sender?.name || 'Unknown',
      snippet: (c.last_non_activity_message?.content || '').slice(0, 72),
      team: c.meta?.team?.name || '',
      stage: contactStage(c.meta?.sender?.custom_attributes) || defaultStage(),
      ts: c.last_activity_at,
      assignee: c.meta?.assignee?.name || '',
    }))
);

const kpis = computed(() => [
  { k: 'Total contacts', v: total.value, icon: 'i-lucide-users', sub: `${pipeline.value} in progress${otherStages.value ? ` · ${otherStages.value} in other stages` : ''}`, accent: '#3e63dd', go: 'contacts_dashboard_index' },
  { k: 'Open conversations', v: openConvs.value, icon: 'i-lucide-messages-square', sub: `${unassigned.value} unassigned`, accent: '#0ea5e9', go: 'home' },
  { k: stageOf(wonKey.value).label, v: won.value, icon: 'i-lucide-trophy', sub: `${lost.value} ${stageOf(lostKey.value).label.toLowerCase()}`, accent: '#10b981', go: 'tolzar_pipeline' },
  { k: 'Win rate', v: `${winRate.value}%`, icon: 'i-lucide-target', sub: 'of decided leads', accent: '#8b5cf6', go: 'tolzar_reports' },
]);

function stageStyle(color) {
  return { backgroundColor: `${color}1a`, color };
}
function initials(name) {
  return (name || '?')
    .split(' ')
    .map(w => w[0])
    .join('')
    .slice(0, 2)
    .toUpperCase();
}
function timeAgo(ts) {
  if (!ts) return '';
  const s = Math.max(0, Math.floor(Date.now() / 1000 - ts));
  if (s < 60) return 'now';
  if (s < 3600) return `${Math.floor(s / 60)}m`;
  if (s < 86400) return `${Math.floor(s / 3600)}h`;
  return `${Math.floor(s / 86400)}d`;
}
function go(name) {
  if (!name) return;
  router.push({ name, params: { accountId: accountId.value } }).catch(() => {});
}
function openConversation(id) {
  router.push({ name: 'inbox_conversation', params: { accountId: accountId.value, conversation_id: id } });
}

const openMetaFor = async (params = '') => {
  const { data } = await window.axios.get(
    `/api/v1/accounts/${accountId.value}/conversations/meta?status=open${params}`
  );
  return data?.meta || {};
};

async function loadTeams(openTotal) {
  await store.dispatch('teams/get');
  const teams = store.getters['teams/getTeams'] || [];
  const rows = await Promise.all(
    teams.map(async t => ({ name: t.name, n: (await openMetaFor(`&team_id=${t.id}`)).all_count || 0 }))
  );
  const inTeams = rows.reduce((a, r) => a + r.n, 0);
  teamCounts.value = [...rows, { name: 'No team', n: Math.max(0, openTotal - inTeams) }];
}

// The workspace's first-run checklist (open to every administrator): a card until it is done.
const setup = ref(null);
const setupOpen = computed(() => setup.value && setup.value.total && setup.value.done < setup.value.total);
async function loadSetup() {
  try {
    const { data } = await window.axios.get(`/api/v1/accounts/${accountId.value}/tolzar/workspace/checklist`);
    setup.value = data && data.ok !== false ? data : null;
  } catch (e) {
    setup.value = null;
  }
}

onMounted(async () => {
  store.dispatch('agents/get').catch(() => {});
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
      loadTeams(meta.all_count || 0).catch(() => {}),
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
    lastUpdated.value = new Date();
    loadSetup();
  }
});
</script>

<template>
  <div class="overflow-auto flex-1 bg-n-background" data-tz-build="dash-6">
    <div class="tz-dash mx-auto max-w-[1200px] px-5 pb-16 pt-6 md:px-7">
      <!-- hero header -->
      <div
        class="tz-rise tz-hero overflow-hidden relative p-6 rounded-3xl border shadow-sm md:p-7 bg-n-solid-1 border-n-weak"
        style="animation-delay: 0ms"
      >
        <span class="tz-hero-glow" aria-hidden="true" />
        <div class="flex relative flex-wrap gap-5 justify-between items-center">
          <div class="flex gap-4 items-center min-w-0">
            <span class="tz-hero-mark grid flex-shrink-0 place-content-center rounded-2xl size-14">
              <span class="i-lucide-layout-dashboard size-7 text-white" />
            </span>
            <div class="min-w-0">
              <div class="flex gap-2 items-center text-[11px] font-semibold tracking-[0.14em] uppercase text-n-brand">
                <span class="inline-block rounded-full size-1.5 bg-n-brand tz-pulse" />
                Your command center
              </div>
              <h1 class="mt-1 text-2xl font-extrabold tracking-tight md:text-[26px] text-n-slate-12">
                {{ greeting }}, {{ firstName }}
              </h1>
              <p class="mt-1 mb-0 text-sm text-n-slate-11">
                {{ loaded ? `${openConvs} open · ${won} won · ${winRate}% win rate` : 'Loading your pipeline…' }}
              </p>
              <!-- Tolzar D2: timezone + when these numbers were last refreshed -->
              <p
                v-if="loaded"
                class="flex flex-wrap gap-x-2 gap-y-0.5 items-center mt-1 mb-0 text-[11px] text-n-slate-10"
              >
                <span v-if="timezone" class="inline-flex gap-1 items-center">
                  <span class="i-lucide-globe size-3" />{{ timezone }}
                </span>
                <span v-if="lastUpdatedLabel" class="inline-flex gap-1 items-center">
                  <span class="i-lucide-refresh-cw size-3" />Updated {{ lastUpdatedLabel }}
                </span>
              </p>
            </div>
          </div>
          <div class="flex flex-wrap gap-2.5 items-center">
            <button
              v-if="loaded && unassigned > 0"
              type="button"
              class="inline-flex gap-1.5 items-center px-3 h-9 text-[13px] font-semibold rounded-xl border transition-colors tz-attn"
              @click="go('home')"
            >
              <span class="i-lucide-alert-circle size-4" />
              {{ unassigned }} to assign
            </button>
            <button
              type="button"
              class="inline-flex gap-2 items-center px-4 h-9 text-sm font-semibold text-white rounded-xl shadow-sm transition-all bg-n-brand hover:opacity-90 hover:shadow-md"
              @click="go('home')"
            >
              <span class="i-lucide-inbox size-4" />
              Open inbox
            </button>
          </div>
        </div>
      </div>

      <!-- first-run setup: until the workspace's checklist is done -->
      <div v-if="setupOpen" class="flex flex-wrap gap-3 justify-between items-center p-4 mt-4 rounded-2xl border bg-n-solid-1 border-n-weak" data-tz-setup-card>
        <div class="min-w-0">
          <div class="text-[14px] font-semibold text-n-slate-12">{{ $t('TOLZAR_ONBOARDING.CARD_TITLE') }}</div>
          <div class="text-[13px] text-n-slate-11">{{ $t('TOLZAR_ONBOARDING.CARD_PROGRESS', { done: setup.done, total: setup.total }) }}</div>
        </div>
        <button type="button" class="inline-flex items-center px-4 h-9 text-sm font-semibold text-white rounded-xl border-0 cursor-pointer bg-n-brand" @click="go('tolzar_onboarding')">{{ $t('TOLZAR_ONBOARDING.CARD_OPEN') }}</button>
      </div>

      <!-- KPI cards -->
      <div class="grid grid-cols-2 gap-3.5 mt-4 lg:grid-cols-4">
        <component
          :is="t.go ? 'button' : 'div'"
          v-for="(t, i) in kpis"
          :key="t.k"
          :type="t.go ? 'button' : undefined"
          class="tz-rise tz-card overflow-hidden relative p-4 w-full text-left rounded-2xl border shadow-sm bg-n-solid-1 border-n-weak"
          :class="t.go ? 'tz-hover cursor-pointer' : ''"
          :style="{ animationDelay: 60 + i * 50 + 'ms' }"
          @click="t.go && go(t.go)"
        >
          <span class="tz-accent" :style="{ background: t.accent }" aria-hidden="true" />
          <div class="flex gap-2.5 items-center">
            <span class="grid place-content-center rounded-xl size-9" :style="stageStyle(t.accent)">
              <span :class="t.icon" class="size-[18px]" />
            </span>
            <div class="text-xs font-medium leading-tight text-n-slate-11">{{ t.k }}</div>
          </div>
          <div class="mt-3 text-[34px] font-extrabold leading-none tabular-nums text-n-slate-12">
            {{ loaded ? t.v : '—' }}
          </div>
          <div class="mt-1.5 text-xs text-n-slate-10">{{ t.sub }}</div>
        </component>
      </div>

      <!-- funnel + team -->
      <div class="grid grid-cols-1 gap-3.5 mt-3.5 lg:grid-cols-3">
        <!-- lifecycle funnel -->
        <div class="tz-rise p-5 rounded-2xl border shadow-sm lg:col-span-2 bg-n-solid-1 border-n-weak" style="animation-delay: 300ms">
          <div class="flex justify-between items-center mb-4">
            <h3 class="m-0 text-sm font-semibold text-n-slate-12">Lifecycle funnel</h3>
            <span class="px-2 py-0.5 text-[11px] font-medium rounded-full bg-n-alpha-2 text-n-slate-11">{{ total }} contacts</span>
          </div>
          <div
            v-for="s in STAGES"
            :key="s.key"
            class="grid gap-3 items-center mb-3 last:mb-0 grid-cols-[112px_1fr_60px] md:grid-cols-[150px_1fr_72px]"
          >
            <div class="flex gap-2 items-center min-w-0">
              <span class="grid place-content-center rounded-lg size-6" :style="stageStyle(s.color)">
                <span :class="s.icon" class="size-3.5" />
              </span>
              <span class="text-sm font-semibold truncate text-n-slate-11">{{ s.label }}</span>
            </div>
            <div class="overflow-hidden h-7 rounded-lg bg-n-alpha-2">
              <div
                class="h-full rounded-lg transition-[width] duration-700 ease-out"
                :style="{ width: (loaded ? Math.max(5, Math.round(((counts[s.key]||0)/funnelMax)*100)) : 0) + '%', background: `linear-gradient(90deg, ${s.color}, ${s.color}cc)` }"
              />
            </div>
            <div class="font-extrabold text-right text-n-slate-12 tabular-nums">
              {{ loaded ? (counts[s.key] || 0) : '—' }}
              <span class="block text-[10px] font-medium text-n-slate-10">
                {{ total ? Math.round(((counts[s.key]||0)/total)*100) : 0 }}%
              </span>
            </div>
          </div>
        </div>

        <!-- right column: team mix + (managers) live presence -->
        <div class="flex flex-col gap-3.5">
        <!-- by team -->
        <div class="tz-rise p-5 rounded-2xl border shadow-sm bg-n-solid-1 border-n-weak" style="animation-delay: 350ms">
          <h3 class="m-0 mb-4 text-sm font-semibold text-n-slate-12">Conversations by team</h3>
          <div v-if="loaded && teamDist.length">
            <div v-for="t in teamDist" :key="t.name" class="mb-3.5 last:mb-0">
              <div class="flex justify-between mb-1 text-xs">
                <span class="font-semibold capitalize truncate text-n-slate-11">{{ t.name }}</span>
                <span class="font-bold text-n-slate-12 tabular-nums">{{ t.n }}</span>
              </div>
              <div class="overflow-hidden h-2 rounded-full bg-n-alpha-2">
                <div class="h-full rounded-full transition-[width] duration-700" :style="{ width: t.pct + '%', background: `linear-gradient(90deg, ${t.color}, ${t.color}cc)` }" />
              </div>
            </div>
          </div>
          <p v-else class="text-xs text-n-slate-10">No conversations yet.</p>
        </div>

        <!-- Tolzar D1: live team presence (managers see every agent) -->
        <div
          v-if="isManager"
          class="tz-rise p-5 rounded-2xl border shadow-sm bg-n-solid-1 border-n-weak"
          style="animation-delay: 380ms"
        >
          <div class="flex justify-between items-center mb-4">
            <h3 class="m-0 text-sm font-semibold text-n-slate-12">Team presence</h3>
            <span class="px-2 py-0.5 text-[11px] font-medium rounded-full bg-n-alpha-2 text-n-slate-11">
              {{ onlineCount }}/{{ agentTotal }} online
            </span>
          </div>
          <div v-if="agentTotal">
            <div v-for="p in PRESENCE" :key="p.key" class="mb-3 last:mb-0">
              <div class="flex gap-1.5 items-center mb-1.5">
                <span class="inline-block rounded-full size-2" :style="{ background: p.color }" />
                <span class="text-xs font-semibold text-n-slate-11">{{ p.label }}</span>
                <span class="text-[11px] font-bold text-n-slate-12 tabular-nums">{{ presence[p.key].length }}</span>
              </div>
              <div v-if="presence[p.key].length" class="flex flex-wrap gap-1.5">
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
                    :style="{ background: p.color }"
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
          <p v-else class="text-xs text-n-slate-10">No teammates yet.</p>
        </div>
        </div>
      </div>

      <!-- recent conversations -->
      <div class="tz-rise mt-3.5 rounded-2xl border shadow-sm bg-n-solid-1 border-n-weak" style="animation-delay: 400ms">
        <div class="flex justify-between items-center px-5 py-4 border-b border-n-weak">
          <h3 class="m-0 text-sm font-semibold text-n-slate-12">Recent conversations</h3>
          <button type="button" class="inline-flex gap-1 items-center text-xs font-semibold text-n-brand hover:underline" @click="go('home')">
            View all <span class="i-lucide-arrow-right size-3.5 rtl:rotate-180" />
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
            <span class="grid flex-shrink-0 place-content-center text-xs font-bold rounded-full size-9 bg-n-alpha-2 text-n-slate-11">
              {{ initials(r.name) }}
            </span>
            <span class="flex-1 min-w-0">
              <span class="flex gap-2 items-center">
                <span class="text-sm font-semibold truncate text-n-slate-12">{{ r.name }}</span>
                <span
                  v-if="r.stage"
                  class="px-1.5 py-0.5 text-[10px] font-semibold leading-none rounded-full whitespace-nowrap"
                  :style="stageStyle((STAGES.find(s=>s.key===r.stage)||{}).color || '#64748b')"
                >
                  {{ (STAGES.find(s=>s.key===r.stage)||{}).label || r.stage }}
                </span>
              </span>
              <span class="block text-xs truncate text-n-slate-10">{{ r.snippet || 'No messages yet' }}</span>
            </span>
            <span class="flex flex-col flex-shrink-0 gap-1 items-end">
              <span v-if="r.team" class="text-[11px] font-medium capitalize text-n-slate-11">{{ r.team }}</span>
              <span class="text-[11px] text-n-slate-10">{{ timeAgo(r.ts) }}</span>
            </span>
          </button>
        </div>
        <p v-else class="px-5 py-6 text-xs text-n-slate-10">No conversations yet.</p>
      </div>

      <!-- quick links -->
      <div class="grid grid-cols-1 gap-3.5 mt-3.5 md:grid-cols-3">
        <button
          v-for="(q, i) in [
            { name: 'tolzar_ai_agents', icon: 'i-lucide-bot', label: 'AI Agents', sub: 'Build your sellers' },
            { name: 'tolzar_workflows', icon: 'i-lucide-workflow', label: 'Workflows', sub: 'Automate conversations' },
            { name: 'home', icon: 'i-lucide-inbox', label: 'Inbox', sub: 'All conversations' },
          ]"
          :key="q.name"
          type="button"
          class="tz-rise tz-card tz-hover flex gap-3 items-center p-4 text-left rounded-2xl border shadow-sm cursor-pointer bg-n-solid-1 border-n-weak"
          :style="{ animationDelay: 450 + i * 50 + 'ms' }"
          @click="go(q.name)"
        >
          <span class="grid flex-shrink-0 place-content-center rounded-xl size-10 bg-n-alpha-2">
            <span :class="q.icon" class="size-5 text-n-brand" />
          </span>
          <span class="min-w-0">
            <span class="block font-semibold truncate text-n-slate-12">{{ q.label }}</span>
            <span class="block text-xs truncate text-n-slate-11">{{ q.sub }}</span>
          </span>
          <span class="ltr:ml-auto rtl:mr-auto i-lucide-arrow-right size-4 text-n-brand rtl:rotate-180" />
        </button>
      </div>

      <p v-if="errored" class="mt-4 text-xs text-n-slate-10">
        Live counts are unavailable right now — the layout is in place.
      </p>
    </div>
  </div>
</template>

<style scoped>
/* premium hero: subtle brand wash + glow, elegant in both themes */
.tz-hero {
  background-image: linear-gradient(135deg, rgba(62, 99, 221, 0.06), rgba(62, 99, 221, 0) 42%);
}
.tz-hero-glow {
  position: absolute;
  inset-inline-end: -60px;
  top: -70px;
  width: 240px;
  height: 240px;
  border-radius: 9999px;
  background: radial-gradient(circle, rgba(62, 99, 221, 0.14), rgba(62, 99, 221, 0) 70%);
  pointer-events: none;
}
.tz-hero-mark {
  background: linear-gradient(140deg, #5472e4, #3e63dd);
  box-shadow: 0 8px 20px -6px rgba(62, 99, 221, 0.55);
}
.tz-attn {
  color: #b45309;
  background: rgba(245, 158, 11, 0.12);
  border-color: rgba(245, 158, 11, 0.35);
}
.tz-attn:hover {
  background: rgba(245, 158, 11, 0.2);
}
/* KPI accent bar */
.tz-card {
  transition: transform 0.18s ease, box-shadow 0.18s ease;
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
  0%, 100% { opacity: 1; transform: scale(1); }
  50% { opacity: 0.45; transform: scale(0.82); }
}
/* staggered entrance */
.tz-rise {
  opacity: 0;
  animation: tz-rise 0.5s cubic-bezier(0.22, 1, 0.36, 1) forwards;
}
@keyframes tz-rise {
  from { opacity: 0; transform: translateY(10px); }
  to { opacity: 1; transform: translateY(0); }
}
@media (prefers-reduced-motion: reduce) {
  .tz-rise, .tz-pulse { animation: none; opacity: 1; }
}
</style>
