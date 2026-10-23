<script setup>
import { ref, onMounted, computed } from 'vue';
import ContactAPI from 'dashboard/api/contacts';

// respond.io's exact lifecycle stages (the sales funnel spine)
const STAGES = [
  { key: 'New Lead', label: 'New Lead', emoji: '🆕' },
  { key: 'Active', label: 'Active', emoji: '📤' },
  { key: 'Offer Sent Follow up', label: 'Offer Sent', emoji: '📝' },
  { key: 'Customer Won', label: 'Customer Won', emoji: '🤩' },
  { key: 'Customer Lost', label: 'Customer Lost', emoji: '😭' },
];

const counts = ref({});
const loaded = ref(false);
const errored = ref(false);

const total = computed(() =>
  Object.values(counts.value).reduce((a, b) => a + (b || 0), 0)
);
const won = computed(() => counts.value['Customer Won'] || 0);
const lost = computed(() => counts.value['Customer Lost'] || 0);
const winRate = computed(() => {
  const decided = won.value + lost.value;
  return decided ? Math.round((won.value / decided) * 100) : 0;
});

async function fetchStageCount(stage) {
  // ContactAPI uses the SPA's authenticated (devise-token-auth) axios and
  // resolves the account from the route, so this carries the live session.
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
  } catch (e) {
    errored.value = true;
  } finally {
    loaded.value = true;
  }
});
</script>

<template>
  <div class="flex-1 overflow-auto" data-tz-build="contactapi-1" style="background: #f5f8fc">
    <div style="max-width: 1120px; margin: 0 auto; padding: 32px 24px 64px">
      <h1 style="font-size: 24px; font-weight: 800; color: #0b1f3a; margin: 0 0 2px">
        Dashboard
      </h1>
      <p style="color: #64748b; margin: 0 0 24px">
        Lifecycle — your sales funnel at a glance.
      </p>

      <!-- Lifecycle funnel -->
      <div
        style="
          display: grid;
          grid-template-columns: repeat(5, 1fr);
          gap: 14px;
          margin-bottom: 20px;
        "
      >
        <div
          v-for="s in STAGES"
          :key="s.key"
          style="
            background: #fff;
            border: 1px solid #e3e9f2;
            border-radius: 14px;
            padding: 18px;
          "
        >
          <div style="font-size: 22px">{{ s.emoji }}</div>
          <div style="color: #64748b; font-size: 13px; margin: 6px 0 10px">
            {{ s.label }}
          </div>
          <div style="font-size: 30px; font-weight: 800; color: #12a594">
            {{ loaded ? counts[s.key] || 0 : '—' }}
          </div>
        </div>
      </div>

      <!-- Summary tiles -->
      <div style="display: grid; grid-template-columns: repeat(3, 1fr); gap: 14px">
        <div
          style="
            background: #fff;
            border: 1px solid #e3e9f2;
            border-radius: 14px;
            padding: 18px;
          "
        >
          <div style="color: #64748b; font-size: 13px">Total contacts</div>
          <div style="font-size: 28px; font-weight: 800; color: #0b1f3a">
            {{ loaded ? total : '—' }}
          </div>
        </div>
        <div
          style="
            background: #fff;
            border: 1px solid #e3e9f2;
            border-radius: 14px;
            padding: 18px;
          "
        >
          <div style="color: #64748b; font-size: 13px">Won</div>
          <div style="font-size: 28px; font-weight: 800; color: #2bd98a">
            {{ loaded ? won : '—' }}
          </div>
        </div>
        <div
          style="
            background: #fff;
            border: 1px solid #e3e9f2;
            border-radius: 14px;
            padding: 18px;
          "
        >
          <div style="color: #64748b; font-size: 13px">Win rate</div>
          <div style="font-size: 28px; font-weight: 800; color: #12a594">
            {{ loaded ? winRate + '%' : '—' }}
          </div>
        </div>
      </div>

      <p
        v-if="errored"
        style="color: #94a3b8; font-size: 12px; margin-top: 16px"
      >
        Live counts are unavailable right now — the funnel layout is in place.
      </p>
    </div>
  </div>
</template>
