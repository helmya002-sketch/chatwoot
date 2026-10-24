<script setup>
import { ref, onMounted, computed } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import ContactAPI from 'dashboard/api/contacts';

// respond.io's exact lifecycle stages (the sales funnel spine)
const STAGES = [
  { key: 'New Lead', label: 'New Lead', emoji: '🆕' },
  { key: 'Active', label: 'Active', emoji: '📤' },
  { key: 'Offer Sent Follow up', label: 'Offer Sent', emoji: '📝' },
  { key: 'Customer Won', label: 'Customer Won', emoji: '🤩' },
  { key: 'Customer Lost', label: 'Customer Lost', emoji: '😭' },
];

const route = useRoute();
const router = useRouter();
const accountId = computed(() => route.params.accountId);
const counts = ref({});
const loaded = ref(false);
const errored = ref(false);

const total = computed(() => Object.values(counts.value).reduce((a, b) => a + (b || 0), 0));
const won = computed(() => counts.value['Customer Won'] || 0);
const lost = computed(() => counts.value['Customer Lost'] || 0);
const pipeline = computed(
  () => (counts.value['New Lead'] || 0) + (counts.value['Active'] || 0) + (counts.value['Offer Sent Follow up'] || 0)
);
const winRate = computed(() => {
  const decided = won.value + lost.value;
  return decided ? Math.round((won.value / decided) * 100) : 0;
});
const maxCount = computed(() => Math.max(1, ...STAGES.map(s => counts.value[s.key] || 0)));
function barPct(key) {
  return Math.round(((counts.value[key] || 0) / maxCount.value) * 100);
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

function go(name) {
  router.push({ name, params: { accountId: accountId.value } });
}

const QUICK = [
  { name: 'tolzar_ai_agents', emoji: '🤖', label: 'AI Agents', sub: 'Build your sellers' },
  { name: 'tolzar_workflows', emoji: '🔀', label: 'Workflows', sub: 'Automate conversations' },
  { name: 'home', emoji: '💬', label: 'Inbox', sub: 'All conversations' },
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
  <div class="flex-1 overflow-auto" data-tz-build="dash-2" style="background: #f5f8fc">
    <div style="max-width: 1120px; margin: 0 auto; padding: 24px 24px 64px">
      <!-- hero -->
      <div style="background: linear-gradient(120deg,#0f4a66,#156080,#12a594); border-radius: 18px; padding: 24px 28px; color: #fff; box-shadow: 0 8px 24px rgba(15,74,102,.18)">
        <div style="font-size: 13px; opacity: .85; font-weight: 600; letter-spacing: .3px">DASHBOARD</div>
        <h1 style="font-size: 24px; font-weight: 800; margin: 4px 0 2px">Your sales funnel at a glance</h1>
        <p style="margin: 0; opacity: .9; font-size: 14px">Lifecycle pipeline across all conversations.</p>
      </div>

      <!-- summary tiles -->
      <div style="display: grid; grid-template-columns: repeat(4,1fr); gap: 14px; margin-top: 18px">
        <div v-for="t in [
          { k: 'Total contacts', v: loaded ? total : '—', c: '#0b1f3a' },
          { k: 'Active pipeline', v: loaded ? pipeline : '—', c: '#12a594' },
          { k: 'Won', v: loaded ? won : '—', c: '#2bd98a' },
          { k: 'Win rate', v: loaded ? winRate + '%' : '—', c: '#12a594' },
        ]" :key="t.k" style="background: #fff; border: 1px solid #e3e9f2; border-radius: 14px; padding: 16px 18px">
          <div style="color: #64748b; font-size: 12.5px">{{ t.k }}</div>
          <div :style="{ fontSize: '28px', fontWeight: 800, color: t.c, marginTop: '2px' }">{{ t.v }}</div>
        </div>
      </div>

      <!-- funnel -->
      <div style="background: #fff; border: 1px solid #e3e9f2; border-radius: 16px; padding: 20px 22px; margin-top: 18px">
        <h3 style="margin: 0 0 16px; font-size: 15px; color: #0b1f3a">Lifecycle funnel</h3>
        <div v-for="s in STAGES" :key="s.key" style="display: grid; grid-template-columns: 150px 1fr 54px; align-items: center; gap: 12px; margin-bottom: 12px">
          <div style="display: flex; align-items: center; gap: 8px; color: #475569; font-size: 13px; font-weight: 600">
            <span>{{ s.emoji }}</span>{{ s.label }}
          </div>
          <div style="background: #eef2f7; border-radius: 8px; height: 26px; overflow: hidden">
            <div :style="{ width: (loaded ? barPct(s.key) : 0) + '%', height: '100%', background: s.key === 'Customer Lost' ? 'linear-gradient(90deg,#f59e0b,#ef4444)' : 'linear-gradient(90deg,#14b8a6,#0e8f84)', borderRadius: '8px', transition: 'width .4s ease' }"></div>
          </div>
          <div style="text-align: right; font-weight: 800; color: #0b1f3a">{{ loaded ? (counts[s.key] || 0) : '—' }}</div>
        </div>
      </div>

      <!-- quick links -->
      <div style="display: grid; grid-template-columns: repeat(3,1fr); gap: 14px; margin-top: 18px">
        <div v-for="q in QUICK" :key="q.name" style="background: #fff; border: 1px solid #e3e9f2; border-radius: 14px; padding: 18px; cursor: pointer; display: flex; align-items: center; gap: 12px" @click="go(q.name)">
          <span style="width: 42px; height: 42px; border-radius: 11px; background: #d8f5f0; display: grid; place-content: center; font-size: 20px">{{ q.emoji }}</span>
          <div>
            <div style="font-weight: 700; color: #0b1f3a">{{ q.label }}</div>
            <div style="color: #64748b; font-size: 12.5px">{{ q.sub }}</div>
          </div>
          <span style="margin-left: auto; color: #12a594; font-weight: 700">→</span>
        </div>
      </div>

      <p v-if="errored" style="color: #94a3b8; font-size: 12px; margin-top: 16px">
        Live counts are unavailable right now — the layout is in place.
      </p>
    </div>
  </div>
</template>
