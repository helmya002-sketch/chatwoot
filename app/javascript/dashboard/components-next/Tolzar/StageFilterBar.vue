<script setup>
// Tolzar Contacts pass 1: one-click stage views above the table. Applies a normal Chatwoot
// contact filter (lifecycle_stage = X), so pagination, the filter pill and "Save as segment"
// keep working.
import { watchEffect } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { STAGES, stageClass, applyPipelineStages } from './tolzarStages';

defineProps({
  activeStage: { type: String, default: '' },
});
const emit = defineEmits(['select']);
const { t } = useI18n();

// The workspace's own stage list (account setting `pipeline_stages`), else the defaults.
const accountId = useMapGetter('getCurrentAccountId');
const getAccount = useMapGetter('accounts/getAccount');
watchEffect(() =>
  applyPipelineStages(getAccount.value(accountId.value)?.settings)
);
</script>

<template>
  <div class="flex flex-wrap items-center gap-1.5">
    <button
      type="button"
      class="px-2.5 py-1 text-xs font-medium border rounded-full"
      :class="
        !activeStage
          ? 'border-n-brand bg-n-brand text-white'
          : 'border-n-weak text-n-slate-11 hover:bg-n-slate-2'
      "
      :aria-pressed="!activeStage"
      @click="emit('select', '')"
    >
      {{ t('TOLZAR_CONTACTS.STAGES.ALL') }}
    </button>
    <button
      v-for="s in STAGES"
      :key="s.key"
      type="button"
      class="inline-flex items-center gap-1.5 px-2.5 py-1 text-xs font-medium border rounded-full"
      :class="
        activeStage === s.key
          ? ['border-transparent font-semibold', stageClass(s.key)]
          : 'border-n-weak text-n-slate-11 hover:bg-n-slate-2'
      "
      :aria-pressed="activeStage === s.key"
      @click="emit('select', s.key)"
    >
      <span
        class="p-0.5 rounded-full"
        :class="stageClass(s.key)"
        aria-hidden="true"
      >
        <span class="block rounded-full size-1.5 bg-current" />
      </span>
      {{ s.label }}
    </button>
  </div>
</template>
