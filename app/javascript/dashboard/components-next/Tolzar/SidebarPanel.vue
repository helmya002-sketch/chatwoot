<script setup>
/**
 * Tolzar sidebar panel — the brain's read of this contact as a collapsible panel:
 * lead score, a one-line summary, the next step, and (for strong leads) the team's
 * strongest close. Reads the custom attributes the brain writes; hides when empty.
 */
import { computed, ref } from 'vue';
import AccordionItem from 'dashboard/components/Accordion/AccordionItem.vue';

const props = defineProps({
  contact: { type: Object, default: () => ({}) },
});

const attrs = computed(() => props.contact?.custom_attributes || {});
const score = computed(() => {
  const n = Number(attrs.value.tolzar_lead_score);
  return Number.isFinite(n) && n > 0 ? Math.min(100, Math.round(n)) : null;
});
const label = computed(() => attrs.value.tolzar_lead_label || '');
const hint = computed(() => (attrs.value.tolzar_lead_hint || '').trim());
const summary = computed(() => (attrs.value.tolzar_summary || '').trim());

const hasContent = computed(() => !!(score.value || summary.value));
const isOpen = ref(true);
const ringStyle = computed(() => ({
  background: `conic-gradient(rgb(var(--blue-9)) ${score.value}%, rgb(var(--slate-5)) 0)`,
}));
const showVoucher = computed(() => score.value && score.value >= 70);
</script>

<template>
  <div v-if="hasContent" class="conversation--actions">
    <AccordionItem title="Tolzar" :is-open="isOpen" @toggle="v => (isOpen = v)">
      <div class="tz-sp">
        <div v-if="score" class="tz-sp-score">
          <span class="tz-sp-ring" :style="ringStyle"><i>{{ score }}</i></span>
          <span class="tz-sp-lx">
            <b>{{ label || 'Lead score' }}</b>
            <i v-if="hint">{{ hint }}</i>
          </span>
        </div>
        <p v-if="summary" class="tz-sp-sum">{{ summary }}</p>
        <div v-if="showVoucher" class="tz-sp-nudge">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor">
            <path
              d="M9 11l3 3 8-8M20 12v6a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2h9"
            />
          </svg>
          <span>Offer the free pre-booking voucher — the team's strongest close.</span>
        </div>
      </div>
    </AccordionItem>
  </div>
</template>

<style scoped>
.tz-sp {
  display: flex;
  flex-direction: column;
  gap: 12px;
  padding: 2px 0 6px;
}
.tz-sp-score {
  display: flex;
  align-items: center;
  gap: 12px;
}
.tz-sp-ring {
  width: 44px;
  height: 44px;
  border-radius: 50%;
  flex: 0 0 44px;
  display: grid;
  place-items: center;
}
.tz-sp-ring i {
  width: 34px;
  height: 34px;
  border-radius: 50%;
  background: rgb(var(--surface-1));
  display: grid;
  place-items: center;
  font-size: 13px;
  font-weight: 800;
  font-style: normal;
  color: rgb(var(--slate-12));
}
.tz-sp-lx {
  display: flex;
  flex-direction: column;
  line-height: 1.3;
}
.tz-sp-lx b {
  font-size: 13px;
  font-weight: 700;
  color: rgb(var(--slate-12));
}
.tz-sp-lx i {
  font-size: 12px;
  font-style: normal;
  color: rgb(var(--slate-11));
}
.tz-sp-sum {
  font-size: 12.5px;
  color: rgb(var(--slate-11));
  line-height: 1.55;
  margin: 0;
}
.tz-sp-nudge {
  display: flex;
  align-items: flex-start;
  gap: 8px;
  font-size: 12px;
  color: rgb(var(--slate-12));
  background: rgb(var(--blue-9) / 0.08);
  border: 1px solid rgb(var(--blue-9) / 0.18);
  border-radius: 9px;
  padding: 9px 11px;
  line-height: 1.45;
}
.tz-sp-nudge svg {
  width: 15px;
  height: 15px;
  flex: 0 0 15px;
  margin-top: 1px;
  stroke: rgb(var(--blue-9));
  stroke-width: 1.8;
}
</style>
