<script setup>
/**
 * Tolzar sidebar panel — the brain's read of this contact as a collapsible panel:
 * lead score with its breakdown (label + why), and the one-line summary. Reads the
 * custom attributes the brain writes; hides when empty. Generic: no workspace-specific
 * sales advice lives here (that belongs to the workspace's own settings).
 */
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import AccordionItem from 'dashboard/components/Accordion/AccordionItem.vue';
import LeadScoreRing from './LeadScoreRing.vue';
import { tolzarBrand } from './TolzarBranding.vue';

const props = defineProps({
  contact: { type: Object, default: () => ({}) },
});

const { t } = useI18n();
const attrs = computed(() => props.contact?.custom_attributes || {});
const score = computed(() => {
  const n = Number(attrs.value.tolzar_lead_score);
  return Number.isFinite(n) && n > 0 ? Math.min(100, Math.round(n)) : null;
});
const label = computed(
  () => attrs.value.tolzar_lead_label || t('TOLZAR_INBOX.LEAD_SCORE.LABEL')
);
const hint = computed(() => (attrs.value.tolzar_lead_hint || '').trim());
const summary = computed(() => (attrs.value.tolzar_summary || '').trim());
const title = computed(() => tolzarBrand.productName);

const hasContent = computed(() => !!(score.value || summary.value));
const isOpen = ref(true);
</script>

<template>
  <div v-if="hasContent" class="conversation--actions">
    <AccordionItem :title="title" :is-open="isOpen" @toggle="v => (isOpen = v)">
      <div class="tz-sp">
        <div v-if="score" class="tz-sp-score">
          <LeadScoreRing :score="score" size="md" />
          <span class="tz-sp-lx">
            <b>{{ label }}</b>
            <i v-if="hint">{{ hint }}</i>
          </span>
        </div>
        <p v-if="summary" class="tz-sp-sum">{{ summary }}</p>
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
</style>
