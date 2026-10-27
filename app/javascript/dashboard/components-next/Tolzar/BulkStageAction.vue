<script setup>
// Tolzar Contacts pass 1: "Set stage" in the contacts bulk-action bar.
import { useI18n } from 'vue-i18n';
import { ref } from 'vue';
import Button from 'dashboard/components-next/button/Button.vue';
import { STAGES, stageClass } from './tolzarStages';

defineProps({
  disabled: { type: Boolean, default: false },
  isLoading: { type: Boolean, default: false },
});
const emit = defineEmits(['set']);
const { t } = useI18n();
const open = ref(false);

const pick = key => {
  open.value = false;
  emit('set', key);
};
</script>

<template>
  <div class="relative">
    <Button
      sm
      ghost
      slate
      icon="i-lucide-flag"
      :label="t('TOLZAR_CONTACTS.STAGES.SET')"
      :disabled="disabled || isLoading"
      :is-loading="isLoading"
      @click="open = !open"
    />
    <div v-if="open" class="fixed inset-0 z-40" @click="open = false" />
    <div
      v-if="open"
      class="absolute z-50 p-1 mt-1 border shadow-lg ltr:right-0 rtl:left-0 min-w-44 rounded-xl border-n-weak bg-n-alpha-3 backdrop-blur-[100px]"
    >
      <button
        v-for="s in STAGES"
        :key="s.key"
        type="button"
        class="flex items-center w-full gap-2 px-2 py-1.5 text-sm rounded-lg text-start text-n-slate-12 hover:bg-n-alpha-2"
        @click="pick(s.key)"
      >
        <span class="p-0.5 rounded-full" :class="stageClass(s.key)">
          <span class="block rounded-full size-1.5 bg-current" />
        </span>
        {{ s.label }}
      </button>
    </div>
  </div>
</template>
