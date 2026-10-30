<script setup>
import { useI18n } from 'vue-i18n';

// The one badge for "Tolzar runs here, but nothing reaches a customer".
// Every screen that used to say Draft / Dry run / Preview only / Would-send / Read-only uses this
// instead, so an Owner learns one word. The per-feature detail belongs in the hint line below it.
defineProps({
  // 'shadow' (default), 'off' (not running) or 'live' (sends; only shown when the brain says so).
  state: {
    type: String,
    default: 'shadow',
    validator: v => ['shadow', 'off', 'live'].includes(v),
  },
  // Optional extra sentence appended to the tooltip (feature-specific).
  hint: { type: String, default: '' },
});
const { t } = useI18n();
const classes = {
  shadow: 'text-n-amber-11 bg-n-amber-3 border-n-amber-5',
  off: 'text-n-slate-11 bg-n-slate-3 border-n-slate-5',
  live: 'text-n-teal-11 bg-n-teal-3 border-n-teal-5',
};
</script>

<template>
  <span
    class="inline-flex items-center gap-1 px-2 py-0.5 text-[11px] font-semibold rounded-full border border-solid whitespace-nowrap"
    :class="classes[state]"
    :title="[t(`TOLZAR_UI.STATE.${state.toUpperCase()}_HINT`), hint].filter(Boolean).join(' ')"
    :aria-label="t(`TOLZAR_UI.STATE.${state.toUpperCase()}_HINT`)"
  >
    <span class="w-1.5 h-1.5 rounded-full bg-current" aria-hidden="true" />
    {{ t(`TOLZAR_UI.STATE.${state.toUpperCase()}`) }}
  </span>
</template>
