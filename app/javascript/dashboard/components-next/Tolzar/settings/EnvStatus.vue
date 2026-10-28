<script setup>
import { useI18n } from 'vue-i18n';

// Secrets live in the server's environment, never in Tolzar: show the variable NAME the brain
// expects and whether the brain can see it.
defineProps({
  rows: { type: Array, default: () => [] },
});
const { t } = useI18n();
</script>

<template>
  <div class="p-3 mt-3 rounded-lg bg-n-alpha-1">
    <div class="text-xs font-semibold text-n-slate-11">{{ t('TOLZAR_SETTINGS.R1.ENV_TITLE') }}</div>
    <p class="mt-1 mb-0 text-xs text-n-slate-10">{{ t('TOLZAR_SETTINGS.R1.ENV_HINT') }}</p>
    <div v-for="r in rows" :key="r.field" class="flex flex-wrap gap-2 justify-between items-center mt-2 text-[13px]">
      <code class="text-n-slate-12">{{ r.name }}</code>
      <span :class="r.present ? 'text-emerald-600' : 'text-amber-700'">
        {{ r.present ? t('TOLZAR_SETTINGS.R1.ENV_PRESENT') : t('TOLZAR_SETTINGS.R1.ENV_MISSING') }}
      </span>
    </div>
    <p v-if="!rows.length" class="mt-2 mb-0 text-xs text-n-slate-10">{{ t('TOLZAR_SETTINGS.R1.ENV_NONE') }}</p>
  </div>
</template>
