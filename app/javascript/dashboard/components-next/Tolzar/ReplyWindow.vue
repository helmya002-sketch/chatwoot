<script setup>
import { computed, ref, onMounted, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { replyWindow, leftLabel } from './tolzarReplyWindow';

// Above the composer on Messenger / Instagram (round 4, c77): how long a person may still reply. "Standard
// window: 3 h left", or with HUMAN_AGENT on, "Human-agent window: 5 d left". Closed is the existing banner's job.
const props = defineProps({
  channelType: { type: String, default: '' },
  messages: { type: Array, default: () => [] },
});
const { t } = useI18n();
const accountId = useMapGetter('getCurrentAccountId');
const getAccount = useMapGetter('accounts/getAccount');
const humanAgent = computed(
  () => !!getAccount.value(accountId.value)?.tolzar_meta_human_agent
);
const now = ref(Date.now());
let timer = null;
onMounted(() => {
  timer = window.setInterval(() => {
    now.value = Date.now();
  }, 60000);
});
onBeforeUnmount(() => window.clearInterval(timer));

const win = computed(() =>
  replyWindow({
    channelType: props.channelType,
    messages: props.messages,
    humanAgent: humanAgent.value,
    now: now.value,
  })
);
const text = computed(() => {
  if (!win.value || win.value.kind === 'closed') return '';
  const { n, unit } = leftLabel(win.value.secondsLeft);
  const left = t(`TOLZAR_INBOX.REPLY_WINDOW.LEFT_${unit}`, { n });
  return win.value.kind === 'standard'
    ? t('TOLZAR_INBOX.REPLY_WINDOW.STANDARD', { left })
    : t('TOLZAR_INBOX.REPLY_WINDOW.HUMAN_AGENT', { left });
});
</script>

<template>
  <p
    v-if="text"
    class="mx-2 mt-2 mb-0 px-3 py-1.5 rounded-lg text-xs"
    :class="
      win.kind === 'human_agent'
        ? 'bg-n-amber-3 text-n-amber-11'
        : 'bg-n-slate-3 text-n-slate-11'
    "
    role="status"
  >
    {{ text }}
  </p>
</template>
