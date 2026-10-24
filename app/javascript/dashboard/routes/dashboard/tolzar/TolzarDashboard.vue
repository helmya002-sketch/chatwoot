<script setup>
import { ref, onMounted, computed } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import axios from 'axios';
import ContactAPI from 'dashboard/api/contacts';
import { useMapGetter } from 'dashboard/composables/store';

const route = useRoute();
const router = useRouter();
const accountId = computed(() => route.params.accountId);
const currentUser = useMapGetter('getCurrentUser');
const firstName = computed(
  () => (currentUser.value?.name || '').trim().split(' ')[0] || 'there'
);

// respond.io lifecycle stages (the funnel spine)
const STAGES = [
  { key: 'New Lead', label: 'New Lead', icon: 'i-lucide-user-plus', color: '#64748b' },
  { key: 'Active', label: 'Active', icon: 'i-lucide-activity', color: '#f59e0b' },
  { key: 'Offer Sent Follow up', label: 'Offer Sent', icon: 'i-lucide-file-text', color: '#6366f1' },
  { key: 'Customer Won', label: 'Won', icon: 'i-lucide-trophy', color: '#10b981' },
  { key: 'Customer Lost', label: 'Lost', icon: 'i-lucide-circle-x', color: '#f43f5e' },
];
const TEAM_COLORS = ['#0d9488', '#0ea5e9', '#8b5cf6', '#f59e0b', '#ec4899', '#64748b'];

const counts = ref({});
const conversations = ref([]);
const convMeta = ref({});
const loaded = ref(false);
const errored = ref(false);

const total = computed(() =>
  Object.values(counts.value).reduce((a, b) => a + (b || 0), 0)
);
const won = computed(() => counts.value['Customer Won'] || 0);
const lost = computed(() => counts.value['Customer Lost'] || 0);
const pipeline = computed(
  () =>
    (counts.value['New Lead'] || 0) +
    (counts.value['Active'] || 0) +
    (counts.value['Offer Sent Follow up'] || 0)
);
const winRate = computed(() => {
  const decided = won.value + lost.value;
  return decided ? Math.round((won.value / decided) * 100) : 0;
});
const openConvs = computed(() => convMeta.value.all_count || 0);
const unassigned = computed(() => convMeta.value.unassigned_count || 0);
const funnelMax = computed(() =>
  Math.max(1, ...STAGES.map(s => counts.value[s.key] || 0))
);

const teamDist = computed(() => {
  const m = {};
  conversations.value.forEach(c => {
    const t = c.meta?.team?.name || 'Unassigned';
    m[t] = (m[t] || 0) + 1;
  });
  const max = Math.max(1, ...Object.values(m));
  return Object.entries(m)
    .sort((a, b) => b[1] - a[1])
    .map(([name, n], i) => ({ name, n, pct: Math.round((n / max) * 100), color: TEAM_COLORS[i % TEAM_COLORS.length] }));
});

const recent = computed(() =>
  [...conversations.value]
    .sort((a, b) => (b.last_activity_at || 0) - (a.last_activity_at || 0))
    .slice(0, 6)
    .map(c => ({
      id: c.id,
      name: c.meta?.sender?.name || 'Unknown',
      snippet: (c.last_non_activity_message?.content || '').slice(0, 70),
      team: c.meta?.team?.name || '',
      stage: c.meta?.sender?.custom_attributes?.lifecycle_stage || '',
      ts: c.last_activity_at,
      assignee: c.meta?.assignee?.name || '',
    }))
);

const kpis = computed(() => [
  { k: 'Total contacts', v: total.value, icon: 'i-lucide-users', sub: `${pipeline.value} in active pipeline` },
  { k: 'Open conversations', v: openConvs.value, icon: 'i-lucide-messages-square', sub: `${unassigned.value} unassigned` },
  { k: 'Won', v: won.value, icon: 'i-lucide-trophy', sub: `${lost.value} lost`, accent: '#10b981' },
  { k: 'Win rate', v: `${winRate.value}%`, icon: 'i-lucide-target', sub: 'of decided leads', accent: true },
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
  router.push({ name, params: { accountId: accountId.value } });
}
function openConversation(id) {
  router.push({ name: 'inbox_conversation', params: { accountId: accountId.value, conversation_id: id } });
}

async function fetchStageCount(stage) {
  const { data } = await ContactAPI.filter(1, 'name', {
    payload: [
      {
        attribute_key: 'lifecycle_stage',
        filter_operator: 'equal_to',
        values: [stage],
        query_operator: null,
        custom_attribute_type: 'contact_attribute',
      },
    ],
  });
  return (data && data.meta && data.meta.count) || 0;
}

onMounted(async () => {
  try {
    const out = {};
    for (const s of STAGES) {
      // eslint-disable-next-line no-await-in-loop
      out[s.key] = await fetchStageCount(s.key);
    }
    counts.value = out;
    try {
      const { data } = await axios.get(
        `/api/v1/accounts/${accountId.value}/conversations?status=all`
      );
      conversations.value = data?.data?.payload || [];
      convMeta.value = data?.data?.meta || {};
    } catch (e) {
      /* conversations optional */
    }
  } catch (e) {
    errored.value = true;
  } finally {
    loaded.value = true;
  }
});
</script>

<template>
  <div class="overflow-auto flex-1 bg-n-background" data-tz-build="dash-4">
    <div class="mx-auto max-w-[1180px] px-6 pb-16 pt-6">
      <!-- hero -->
      <div
        class="overflow-hidden relative rounded-2xl px-7 py-6 text-white shadow-lg"
        style="background: linear-gradient(120deg, #0f4a66 0%, #156080 48%, #12a594 100%)"
      >
        <div
          class="absolute -top-20 ltr:-right-12 rtl:-left-12 size-56 rounded-full opacity-20"
          style="background: radial-gradient(circle, #fff 0%, transparent 70%)"
        />
        <div class="flex relative flex-wrap gap-4 justify-between items-end">
          <div>
            <div class="text-xs font-semibold tracking-wider opacity-80">
              YOUR SALES FUNNEL
            </div>
            <h1 class="mt-1 text-2xl font-extrabold">
              Welcome back, {{ firstName }}
            </h1>
            <p class="mt-1 mb-0 text-sm opacity-90">
              {{ loaded ? `${openConvs} open conversations · ${won} won · ${winRate}% win rate` : 'Loading your pipeline…' }}
            </p>
          </div>
          <button
            type="button"
            class="inline-flex gap-2 items-center px-4 h-9 text-sm font-semibold text-white rounded-lg backdrop-blur-sm transition-colors bg-white/15 hover:bg-white/25"
            @click="go('home')"
          >
            <span class="i-lucide-inbox size-4" />
            Open inbox
          </button>
        </div>
      </div>

      <!-- KPI cards -->
      <div class="grid grid-cols-2 gap-4 mt-5 lg:grid-cols-4">
        <div
          v-for="t in kpis"
          :key="t.k"
          class="p-4 rounded-2xl border shadow-sm bg-n-solid-1 border-n-weak"
        >
          <div class="flex gap-2.5 items-center">
            <span class="grid place-content-center rounded-xl size-9 bg-n-alpha-2">
              <span :class="t.icon" class="size-[18px] text-n-brand" />
            </span>
            <div class="text-xs font-medium leading-tight text-n-slate-11">
              {{ t.k }}
            </div>
          </div>
          <div
            class="mt-3 text-[32px] font-extrabold leading-none tabular-nums"
            :style="t.accent && t.accent !== true ? { color: t.accent } : undefined"
            :class="t.accent === true ? 'text-n-brand' : (t.accent ? '' : 'text-n-slate-12')"
          >
            {{ loaded ? t.v : '—' }}
          </div>
          <div class="mt-1.5 text-xs text-n-slate-10">{{ t.sub }}</div>
        </div>
      </div>

      <!-- funnel + team -->
      <div class="grid grid-cols-1 gap-4 mt-4 lg:grid-cols-3">
        <!-- lifecycle funnel -->
        <div class="p-5 rounded-2xl border shadow-sm lg:col-span-2 bg-n-solid-1 border-n-weak">
          <div class="flex justify-between items-center mb-4">
            <h3 class="m-0 text-sm font-semibold text-n-slate-12">Lifecycle funnel</h3>
            <span class="text-xs text-n-slate-10">{{ total }} contacts</span>
          </div>
          <div
            v-for="s in STAGES"
            :key="s.key"
            class="grid gap-3 items-center mb-3.5 last:mb-0 grid-cols-[120px_1fr_64px] md:grid-cols-[150px_1fr_72px]"
          >
            <div class="flex gap-2 items-center min-w-0">
              <span class="grid place-content-center rounded-lg size-6" :style="stageStyle(s.color)">
                <span :class="s.icon" class="size-3.5" />
              </span>
              <span class="text-sm font-semibold truncate text-n-slate-11">{{ s.label }}</span>
            </div>
            <div class="overflow-hidden h-7 rounded-lg bg-n-alpha-2">
              <div
                class="flex items-center h-full rounded-lg transition-[width] duration-700 ease-out ltr:pl-2.5 rtl:pr-2.5"
                :style="{ width: (loaded ? Math.max(6, Math.round(((counts[s.key]||0)/funnelMax)*100)) : 0) + '%', background: s.color }"
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

        <!-- by team -->
        <div class="p-5 rounded-2xl border shadow-sm bg-n-solid-1 border-n-weak">
          <h3 class="m-0 mb-4 text-sm font-semibold text-n-slate-12">Conversations by team</h3>
          <div v-if="loaded && teamDist.length">
            <div v-for="t in teamDist" :key="t.name" class="mb-3.5 last:mb-0">
              <div class="flex justify-between mb-1 text-xs">
                <span class="font-semibold capitalize text-n-slate-11 truncate">{{ t.name }}</span>
                <span class="font-bold text-n-slate-12 tabular-nums">{{ t.n }}</span>
              </div>
              <div class="overflow-hidden h-2 rounded-full bg-n-alpha-2">
                <div class="h-full rounded-full transition-[width] duration-700" :style="{ width: t.pct + '%', background: t.color }" />
              </div>
            </div>
          </div>
          <p v-else class="text-xs text-n-slate-10">No conversations yet.</p>
        </div>
      </div>

      <!-- recent conversations -->
      <div class="mt-4 rounded-2xl border shadow-sm bg-n-solid-1 border-n-weak">
        <div class="flex justify-between items-center px-5 py-4 border-b border-n-weak">
          <h3 class="m-0 text-sm font-semibold text-n-slate-12">Recent conversations</h3>
          <button type="button" class="text-xs font-semibold text-n-brand hover:underline" @click="go('home')">
            View all →
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
      <div class="grid grid-cols-1 gap-4 mt-4 md:grid-cols-3">
        <button
          v-for="q in [
            { name: 'tolzar_ai_agents', icon: 'i-lucide-bot', label: 'AI Agents', sub: 'Build your sellers' },
            { name: 'tolzar_workflows', icon: 'i-lucide-workflow', label: 'Workflows', sub: 'Automate conversations' },
            { name: 'home', icon: 'i-lucide-inbox', label: 'Inbox', sub: 'All conversations' },
          ]"
          :key="q.name"
          type="button"
          class="flex gap-3 items-center p-4 text-left rounded-2xl border shadow-sm transition-colors bg-n-solid-1 border-n-weak hover:bg-n-alpha-1"
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
