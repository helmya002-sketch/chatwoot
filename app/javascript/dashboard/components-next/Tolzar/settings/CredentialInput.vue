<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { INPUT, LABEL } from './tzClasses';

// One write-only credential: a password box that is never pre-filled, the saved status from the
// brain ("Saved ••••1234", never the value) and a Remove action for a saved key.
const props = defineProps({
  label: { type: String, required: true },
  status: { type: Object, default: () => ({}) }, // { set, last4, source }
  busy: { type: Boolean, default: false },
});
const emit = defineEmits(['remove']);
const model = defineModel({ type: String, default: '' });
const { t } = useI18n();

const savedText = computed(() =>
  props.status.last4
    ? t('TOLZAR_SETTINGS.CHANNELS.CRED.SAVED_LAST4', {
        last4: props.status.last4,
      })
    : t('TOLZAR_SETTINGS.CHANNELS.CRED.SAVED')
);
</script>

<template>
  <div>
    <label :class="LABEL">{{ label }}</label>
    <input
      v-model="model"
      type="password"
      autocomplete="new-password"
      spellcheck="false"
      :class="INPUT"
      :placeholder="
        status.set
          ? t('TOLZAR_SETTINGS.CHANNELS.CRED.REPLACE')
          : t('TOLZAR_SETTINGS.CHANNELS.CRED.PASTE')
      "
      :aria-label="label"
    />
    <div class="flex flex-wrap gap-2 justify-between items-center mt-1 text-xs">
      <span v-if="status.set" class="text-n-teal-11" data-tz-cred-saved>{{
        savedText
      }}</span>
      <span v-else class="text-n-slate-10">{{
        t('TOLZAR_SETTINGS.CHANNELS.CRED.NOT_SET')
      }}</span>
      <button
        v-if="status.set"
        type="button"
        class="p-0 text-xs bg-transparent border-0 cursor-pointer text-n-ruby-11 disabled:opacity-50"
        :disabled="busy"
        @click="emit('remove')"
      >
        {{ t('TOLZAR_SETTINGS.CHANNELS.CRED.REMOVE') }}
      </button>
    </div>
  </div>
</template>
