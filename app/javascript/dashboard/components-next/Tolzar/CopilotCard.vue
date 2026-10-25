<script setup>
/**
 * Tolzar copilot card — surfaces the brain's read of THIS conversation inline in the
 * thread: intent + confidence + lead score, a one-line summary, and the suggested
 * reply with a one-tap "Use reply" that drops it into the composer for the agent to
 * review and send. Reads the custom attributes the brain writes (shadow-safe); hides
 * gracefully when there is nothing to show.
 */
import { computed } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';

const chat = useMapGetter('getSelectedChat');
const convAttrs = computed(() => chat.value?.custom_attributes || {});
const contactAttrs = computed(
  () => chat.value?.meta?.sender?.custom_attributes || {}
);

const INTENT_LABEL = {
  lead: 'Lead',
  job: 'Job application',
  spam: 'Spam',
  agency: 'Agency',
  booking_com: 'Booking.com',
  submarine: 'Submarine',
  other: 'Needs routing',
};
const intent = computed(
  () => INTENT_LABEL[convAttrs.value.triage_category] || ''
);
const confidence = computed(() => {
  const c = Number(convAttrs.value.brain_confidence);
  return Number.isFinite(c) ? Math.round(c * 100) : null;
});
const suggestedReply = computed(
  () => (convAttrs.value.tolzar_suggested_reply || '').trim()
);
const summary = computed(() => (contactAttrs.value.tolzar_summary || '').trim());
const score = computed(() => {
  const n = Number(contactAttrs.value.tolzar_lead_score);
  return Number.isFinite(n) && n > 0 ? Math.round(n) : null;
});
const hint = computed(() => (contactAttrs.value.tolzar_lead_hint || '').trim());

const hasContent = computed(
  () => !!(suggestedReply.value || summary.value || score.value || intent.value)
);

const useReply = () => {
  if (suggestedReply.value) {
    emitter.emit(BUS_EVENTS.INSERT_INTO_RICH_EDITOR, suggestedReply.value);
  }
};
</script>

<template>
  <div v-if="hasContent" class="tz-copilot">
    <div class="tz-c-head">
      <span class="tz-c-brand">
        <svg viewBox="0 0 24 24" fill="currentColor">
          <path d="M12 2l2.2 6.3L21 10l-6.8 1.7L12 18l-2.2-6.3L3 10l6.8-1.7z" />
        </svg>
        Tolzar copilot
      </span>
      <span v-if="intent" class="tz-c-chip">{{ intent }}</span>
      <span v-if="score" class="tz-c-chip tz-c-score">score {{ score }}</span>
      <span v-if="confidence !== null" class="tz-c-conf">
        confidence
        <span class="tz-c-bar"><i :style="{ width: confidence + '%' }" /></span>
        {{ confidence }}%
      </span>
    </div>

    <p v-if="summary" class="tz-c-summary">{{ summary }}</p>

    <div v-if="suggestedReply" class="tz-c-reply">
      <div class="tz-c-lbl">Suggested reply</div>
      <div class="tz-c-text">{{ suggestedReply }}</div>
      <button type="button" class="tz-c-use" @click="useReply">
        Use reply
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor">
          <path d="M5 12h14M13 6l6 6-6 6" />
        </svg>
      </button>
    </div>

    <p v-if="hint" class="tz-c-why">{{ hint }}</p>
  </div>
</template>

<style scoped>
.tz-copilot {
  position: relative;
  margin: 10px 16px 14px;
  border-radius: 15px;
  border: 1px solid rgb(var(--slate-5));
  background: linear-gradient(180deg, rgb(var(--blue-9) / 0.06), transparent 34%),
    rgb(var(--surface-1));
  box-shadow: 0 10px 30px -24px rgb(0 0 0 / 0.5);
  padding: 13px 15px;
  overflow: hidden;
}
.tz-copilot::before {
  content: '';
  position: absolute;
  left: 0;
  right: 0;
  top: 0;
  height: 2px;
  background: linear-gradient(90deg, rgb(var(--blue-9)), transparent 68%);
  opacity: 0.75;
}
.tz-c-head {
  display: flex;
  align-items: center;
  flex-wrap: wrap;
  gap: 8px;
  margin-bottom: 9px;
}
.tz-c-brand {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  font-size: 12px;
  font-weight: 800;
  letter-spacing: 0.2px;
  color: rgb(var(--blue-9));
}
.tz-c-brand svg {
  width: 15px;
  height: 15px;
}
.tz-c-chip {
  font-size: 10.5px;
  font-weight: 650;
  border-radius: 6px;
  padding: 2px 8px;
  color: rgb(var(--blue-9));
  background: rgb(var(--blue-9) / 0.1);
}
.tz-c-chip.tz-c-score {
  color: rgb(var(--slate-12));
  background: rgb(var(--slate-3, 244 244 245));
}
.tz-c-conf {
  margin-left: auto;
  display: inline-flex;
  align-items: center;
  gap: 7px;
  font-size: 11px;
  color: rgb(var(--slate-11));
}
.tz-c-bar {
  width: 48px;
  height: 5px;
  border-radius: 5px;
  background: rgb(var(--slate-5));
  overflow: hidden;
  display: inline-block;
}
.tz-c-bar i {
  display: block;
  height: 100%;
  background: rgb(var(--blue-9));
}
.tz-c-summary {
  font-size: 12.5px;
  color: rgb(var(--slate-11));
  line-height: 1.55;
  margin: 0 0 11px;
}
.tz-c-reply {
  border: 1px solid rgb(var(--slate-5));
  border-radius: 11px;
  background: rgb(var(--surface-2, 255 255 255));
  padding: 11px 13px;
}
.tz-c-lbl {
  font-size: 10px;
  font-weight: 700;
  letter-spacing: 0.6px;
  text-transform: uppercase;
  color: rgb(var(--slate-11));
  margin-bottom: 7px;
}
.tz-c-text {
  font-size: 13px;
  color: rgb(var(--slate-12));
  line-height: 1.6;
  white-space: pre-wrap;
}
.tz-c-use {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  margin-top: 11px;
  font-size: 12px;
  font-weight: 650;
  color: #fff;
  background: linear-gradient(180deg, rgb(var(--blue-9) / 0.9), rgb(var(--blue-9)));
  border: 0;
  border-radius: 8px;
  padding: 6px 13px;
  cursor: pointer;
}
.tz-c-use svg {
  width: 13px;
  height: 13px;
  stroke-width: 1.8;
}
.tz-c-why {
  font-size: 11.5px;
  color: rgb(var(--slate-11));
  line-height: 1.55;
  border-left: 2px solid rgb(var(--blue-9));
  padding-left: 11px;
  margin: 11px 0 0;
  opacity: 0.95;
}
</style>
