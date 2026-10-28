<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { brainErrors, isOwnerOnly } from '../tolzarBrainApi';

// What the brain or the proxy said back: "saved", the Owner-only refusal, or the brain's errors.
const props = defineProps({
  result: { type: Object, default: null },
  saved: { type: String, default: '' },
});
const { t } = useI18n();
const errors = computed(() =>
  isOwnerOnly(props.result)
    ? [t('TOLZAR_SETTINGS.R1.OWNER_ONLY')]
    : brainErrors(props.result)
);
</script>

<template>
  <div v-if="errors.length" class="p-2 mt-3 text-[13px] rounded-lg text-n-ruby-11 bg-n-ruby-9/10">
    <div v-for="e in errors" :key="e">{{ e }}</div>
  </div>
  <p v-else-if="saved" class="p-2 mt-3 text-[13px] rounded-lg text-n-brand bg-n-brand/10">
    {{ saved }}
  </p>
</template>
