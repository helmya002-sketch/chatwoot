<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';

// Conversation header → Print transcript (round 4, H1; TolzarTranscriptController): a print-friendly page of the
// conversation, private notes only when "include internal notes" is ticked; the browser's print saves it as PDF.
// Hidden when the workspace has inbox tools off (tolzar_inbox_tools).
const props = defineProps({
  displayId: { type: [Number, String], required: true },
});

const { t } = useI18n();
const accountId = useMapGetter('getCurrentAccountId');
const getAccount = useMapGetter('accounts/getAccount');
const enabled = computed(
  () => !!getAccount.value(accountId.value)?.tolzar_inbox_tools
);
const open = ref(false);
const notes = ref(false);
const busy = ref(false);

async function print() {
  busy.value = true;
  try {
    const tz = Intl.DateTimeFormat().resolvedOptions().timeZone;
    const { data } = await window.axios.get(
      `/api/v1/accounts/${accountId.value}/tolzar/conversations/${props.displayId}/transcript`,
      { params: { notes: notes.value ? 1 : 0, tz }, responseType: 'text' }
    );
    const url = URL.createObjectURL(new Blob([data], { type: 'text/html' }));
    window.open(url, '_blank', 'noopener');
    setTimeout(() => URL.revokeObjectURL(url), 60000);
    open.value = false;
  } catch {
    useAlert(t('TOLZAR_INBOX.TRANSCRIPT.FAILED'));
  } finally {
    busy.value = false;
  }
}
</script>

<template>
  <div v-if="enabled" class="relative flex-shrink-0">
    <button
      v-tooltip="t('TOLZAR_INBOX.TRANSCRIPT.BUTTON')"
      type="button"
      class="inline-flex items-center justify-center h-7 px-2 text-xs font-medium rounded-lg border border-solid border-n-weak bg-n-solid-1 text-n-slate-12 hover:bg-n-alpha-2"
      :aria-label="t('TOLZAR_INBOX.TRANSCRIPT.BUTTON')"
      aria-haspopup="dialog"
      :aria-expanded="open ? 'true' : 'false'"
      @click="open = !open"
    >
      <span class="i-lucide-printer size-4" aria-hidden="true" />
    </button>
    <div v-if="open" class="fixed inset-0 z-40" @click="open = false" />
    <div
      v-if="open"
      role="dialog"
      class="absolute end-0 top-full mt-1.5 z-50 w-64 p-3 rounded-xl border border-solid border-n-weak bg-n-solid-1 shadow-lg"
      @keydown.esc="open = false"
    >
      <p class="m-0 text-sm font-semibold text-n-slate-12">
        {{ t('TOLZAR_INBOX.TRANSCRIPT.TITLE') }}
      </p>
      <p class="mt-1 mb-2 text-xs text-n-slate-11">
        {{ t('TOLZAR_INBOX.TRANSCRIPT.HINT') }}
      </p>
      <label class="flex gap-2 items-center text-xs text-n-slate-12">
        <input v-model="notes" type="checkbox" />
        {{ t('TOLZAR_INBOX.TRANSCRIPT.NOTES') }}
      </label>
      <button
        type="button"
        class="mt-3 w-full h-8 text-xs font-medium rounded-lg bg-n-brand text-white disabled:opacity-60"
        :disabled="busy"
        @click="print"
      >
        {{ t('TOLZAR_INBOX.TRANSCRIPT.OPEN') }}
      </button>
    </div>
  </div>
</template>
