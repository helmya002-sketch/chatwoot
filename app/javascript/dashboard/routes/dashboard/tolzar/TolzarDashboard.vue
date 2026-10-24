<script setup>
import { ref, onMounted, computed } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import ContactAPI from 'dashboard/api/contacts';

// respond.io's exact lifecycle stages (the sales funnel spine)
const STAGES = [
  { key: 'New Lead', label: 'New Lead', icon: 'i-lucide-user-plus' },
  { key: 'Active', label: 'Active', icon: 'i-lucide-activity' },
  { key: 'Offer Sent Follow up', label: 'Offer Sent', icon: 'i-lucide-file-text' },
  { key: 'Customer Won', label: 'Customer Won', icon: 'i-lucide-trophy' },
  { key: 'Customer Lost', label: 'Customer Lost', icon: 'i-lucide-circle-x' },
];

const route = useRoute();
const router = useRouter();
const accountId = computed(() => route.params.accountId);
const counts = ref({});
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
const maxCount = computed(() =>
  Math.max(1, ...STAGES.map(s => counts.value[s.key] || 0))
);
function barPct(key) {
  return Math.round(((counts.value[key] || 0) / maxCount.value) * 100);
}

const tiles = computed(() => [
  { k: 'Total contacts', v: loaded.value ? total.value : '—', icon: 'i-lucide-users', accent: false },
  { k: 'Active pipeline', v: loaded.value ? pipeline.value : '—', icon: 'i-lucide-activity', accent: true },
  { k: 'Won', v: loaded.value ? won.value : '—', icon: 'i-lucide-trophy', accent: true },
  { k: 'Win rate', v: loaded.value ? `${winRate.value}%` : '—', icon: 'i-lucide-target', accent: true },
]);

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

function go(name) {
  router.push({ name, params: { accountId: accountId.value } });
}

const QUICK = [
  { name: 'tolzar_ai_agents', icon: 'i-lucide-bot', label: 'AI Agents', sub: 'Build your sellers' },
  { name: 'tolzar_workflows', icon: 'i-lucide-workflow', label: 'Workflows', sub: 'Automate conversations' },
  { name: 'home', icon: 'i-lucide-inbox', label: 'Inbox', sub: 'All conversations' },
];

onMounted(async () => {
  try {
    const out = {};
    for (const s of STAGES) {
      // eslint-disable-next-line no-await-in-loop
      out[s.key] = await fetchStageCount(s.key);
    }
    counts.value = out;
  } catch (e) {
    errored.value = true;
  } finally {
    loaded.value = true;
  }
});
</script>

<template>
  <div class="overflow-auto flex-1 bg-n-background" data-tz-build="dash-3">
    <div class="mx-auto max-w-[1120px] px-6 pb-16 pt-6">
      <!-- hero -->
      <div
        class="overflow-hidden relative rounded-2xl p-6 md:p-7 text-white shadow-lg"
        style="
          background: linear-gradient(120deg, #0f4a66 0%, #156080 45%, #12a594 100%);
        "
      >
        <div
          class="absolute -top-16 ltr:-right-10 rtl:-left-10 size-48 rounded-full opacity-20"
          style="background: radial-gradient(circle, #ffffff 0%, transparent 70%)"
        />
        <div class="relative">
          <div class="text-xs font-semibold tracking-wider opacity-80">
            DASHBOARD
          </div>
          <h1 class="mt-1 mb-1 text-2xl font-extrabold">
            Your sales funnel at a glance
          </h1>
          <p class="m-0 text-sm opacity-90">
            Lifecycle pipeline across all conversations.
          </p>
        </div>
      </div>

      <!-- summary tiles -->
      <div class="grid grid-cols-2 gap-3.5 mt-4 lg:grid-cols-4">
        <div
          v-for="t in tiles"
          :key="t.k"
          class="p-4 rounded-xl border bg-n-solid-1 border-n-weak"
        >
          <div class="flex gap-2 items-center">
            <span
              class="grid place-content-center rounded-lg size-7 bg-n-alpha-2"
            >
              <span :class="t.icon" class="size-4 text-n-brand" />
            </span>
            <div class="text-xs font-medium text-n-slate-11">{{ t.k }}</div>
          </div>
          <div
            class="mt-2 text-3xl font-extrabold tabular-nums"
            :class="t.accent ? 'text-n-brand' : 'text-n-slate-12'"
          >
            {{ t.v }}
          </div>
        </div>
      </div>

      <!-- funnel -->
      <div class="p-5 mt-4 rounded-2xl border bg-n-solid-1 border-n-weak">
        <h3 class="m-0 mb-4 text-sm font-semibold text-n-slate-12">
          Lifecycle funnel
        </h3>
        <div
          v-for="s in STAGES"
          :key="s.key"
          class="grid gap-3 items-center mb-3 last:mb-0 grid-cols-[130px_1fr_48px] md:grid-cols-[160px_1fr_54px]"
        >
          <div
            class="flex gap-2 items-center text-sm font-semibold text-n-slate-11 min-w-0"
          >
            <span :class="s.icon" class="flex-shrink-0 size-4 text-n-slate-10" />
            <span class="truncate">{{ s.label }}</span>
          </div>
          <div class="overflow-hidden h-6 rounded-lg bg-n-alpha-2">
            <div
              class="h-full rounded-lg transition-[width] duration-500 ease-out"
              :style="{
                width: (loaded ? barPct(s.key) : 0) + '%',
                background:
                  s.key === 'Customer Lost' ? '#f43f5e' : '#14b8a6',
              }"
            />
          </div>
          <div class="font-extrabold text-right text-n-slate-12 tabular-nums">
            {{ loaded ? counts[s.key] || 0 : '—' }}
          </div>
        </div>
      </div>

      <!-- quick links -->
      <div class="grid grid-cols-1 gap-3.5 mt-4 md:grid-cols-3">
        <button
          v-for="q in QUICK"
          :key="q.name"
          type="button"
          class="flex gap-3 items-center p-4 text-left rounded-xl border transition-colors bg-n-solid-1 border-n-weak hover:bg-n-alpha-1"
          @click="go(q.name)"
        >
          <span
            class="grid flex-shrink-0 place-content-center rounded-xl size-10 bg-n-alpha-2"
          >
            <span :class="q.icon" class="size-5 text-n-brand" />
          </span>
          <span class="min-w-0">
            <span class="block font-semibold truncate text-n-slate-12">
              {{ q.label }}
            </span>
            <span class="block text-xs truncate text-n-slate-11">
              {{ q.sub }}
            </span>
          </span>
          <span
            class="ltr:ml-auto rtl:mr-auto i-lucide-arrow-right size-4 text-n-brand rtl:rotate-180"
          />
        </button>
      </div>

      <p v-if="errored" class="mt-4 text-xs text-n-slate-10">
        Live counts are unavailable right now — the layout is in place.
      </p>
    </div>
  </div>
</template>
