<script setup>
/**
 * The lead-score ring, drawn once for the conversation header and the contact panel.
 * The filled arc takes the brand colour through `text-n-brand` (currentColor), so a
 * white-labelled workspace recolours it with the rest of the UI; the track and the
 * centre follow the theme tokens. Screen readers get "Lead score 78 of 100".
 */
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  // 0–100; anything outside is clamped.
  score: { type: Number, required: true },
  // 'sm' for a header badge, 'md' for the panel.
  size: {
    type: String,
    default: 'md',
    validator: v => ['sm', 'md'].includes(v),
  },
});

const { t } = useI18n();
const pct = computed(() => Math.min(100, Math.max(0, Math.round(props.score))));
const ringStyle = computed(() => ({
  background: `conic-gradient(currentColor ${pct.value}%, rgb(var(--slate-5)) 0)`,
}));
const ariaLabel = computed(() =>
  t('TOLZAR_INBOX.LEAD_SCORE.ARIA', { score: pct.value })
);
</script>

<template>
  <span
    class="tz-lsr text-n-brand"
    :class="`tz-lsr-${size}`"
    :style="ringStyle"
    role="img"
    :aria-label="ariaLabel"
  >
    <i aria-hidden="true">{{ pct }}</i>
  </span>
</template>

<style scoped>
.tz-lsr {
  border-radius: 50%;
  display: grid;
  place-items: center;
  flex-shrink: 0;
}
.tz-lsr i {
  border-radius: 50%;
  background: rgb(var(--surface-1));
  display: grid;
  place-items: center;
  font-weight: 800;
  font-style: normal;
  color: rgb(var(--slate-12));
}
.tz-lsr-sm {
  width: 30px;
  height: 30px;
}
.tz-lsr-sm i {
  width: 23px;
  height: 23px;
  font-size: 11px;
}
.tz-lsr-md {
  width: 44px;
  height: 44px;
}
.tz-lsr-md i {
  width: 34px;
  height: 34px;
  font-size: 13px;
}
</style>
