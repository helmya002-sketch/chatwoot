<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { closedNotice } from './tolzarReplyClosed';

// Above the composer when no reply can go out (owner, 31 Oct): a calm Tolzar card with a lock, one sentence that
// says why and what to do next, and a "Why?" link to the channel's own rule.
const props = defineProps({
  kind: { type: String, default: 'other' },
  humanAgent: { type: Boolean, default: false },
  apiMessage: { type: String, default: '' },
  apiHours: { type: [Number, String], default: null },
  link: { type: String, default: '' },
});
const { t } = useI18n();
const text = computed(() => {
  const n = closedNotice({
    kind: props.kind,
    humanAgent: props.humanAgent,
    apiMessage: props.apiMessage,
    apiHours: props.apiHours,
  });
  return n.text || t(`TOLZAR_INBOX.REPLY_CLOSED.${n.key}`, n.params);
});
</script>

<template>
  <div
    class="mx-2 mt-2 flex items-start gap-3 rounded-xl border border-solid border-n-amber-6 bg-n-amber-2 px-3.5 py-2.5"
    role="status"
  >
    <span
      class="i-lucide-lock mt-0.5 size-4 flex-shrink-0 text-n-amber-11"
      aria-hidden="true"
    />
    <p class="m-0 flex-1 text-sm leading-5 text-n-slate-12">
      <b class="font-semibold">{{ t('TOLZAR_INBOX.REPLY_CLOSED.TITLE') }}</b>
      {{ text }}
    </p>
    <a
      v-if="link"
      :href="link"
      target="_blank"
      rel="noopener noreferrer"
      class="flex-shrink-0 text-sm font-medium text-n-amber-11 underline"
    >
      {{ t('TOLZAR_INBOX.REPLY_CLOSED.WHY') }}
    </a>
  </div>
</template>
