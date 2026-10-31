<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import Button from 'dashboard/components-next/button/Button.vue';

// Conversation header → Summarise (Tolzar round 4, E1; Shadow): asks the brain for a short summary of this
// conversation and shows it to the staff member only. "Save as private note" is the staff member's own click
// (a private message, never sent to the customer). Shown only while the workspace has inbox tools on.
const props = defineProps({
  conversationId: { type: [Number, String], required: true },
});

const { t } = useI18n();
const accountId = useMapGetter('getCurrentAccountId');
const open = ref(false);
const loading = ref(false);
const saving = ref(false);
const summary = ref('');
const failed = ref(false);

const base = () => `/api/v1/accounts/${accountId.value}`;

async function summarise() {
  open.value = true;
  loading.value = true;
  failed.value = false;
  summary.value = '';
  try {
    const { data } = await window.axios.post(
      `${base()}/tolzar/conversations/${props.conversationId}/summary`
    );
    summary.value = data.summary || '';
    failed.value = !summary.value;
  } catch {
    failed.value = true;
  } finally {
    loading.value = false;
  }
}

async function saveNote() {
  if (!summary.value || saving.value) return;
  saving.value = true;
  try {
    await window.axios.post(
      `${base()}/conversations/${props.conversationId}/messages`,
      {
        content: `${t('TOLZAR_INBOX.SUMMARY.NOTE_PREFIX')} ${summary.value}`,
        private: true,
      }
    );
    useAlert(t('TOLZAR_INBOX.SUMMARY.SAVED'));
    open.value = false;
  } catch {
    useAlert(t('TOLZAR_INBOX.SUMMARY.SAVE_FAILED'));
  } finally {
    saving.value = false;
  }
}
</script>

<template>
  <div class="relative">
    <Button
      v-tooltip="t('TOLZAR_INBOX.SUMMARY.TOOLTIP')"
      :label="t('TOLZAR_INBOX.SUMMARY.BUTTON')"
      icon="i-lucide-sparkles"
      variant="faded"
      color="slate"
      size="sm"
      :is-loading="loading"
      @click="summarise"
    />
    <div
      v-if="open"
      class="absolute end-0 top-full z-50 mt-2 w-80 max-w-[90vw] p-3 rounded-xl border border-solid border-n-weak bg-n-solid-1 shadow-lg"
      role="dialog"
      :aria-label="t('TOLZAR_INBOX.SUMMARY.TITLE')"
      @keydown.esc="open = false"
    >
      <div class="flex items-center justify-between gap-2">
        <h3 class="m-0 text-sm font-semibold text-n-slate-12">
          {{ t('TOLZAR_INBOX.SUMMARY.TITLE') }}
        </h3>
        <Button
          icon="i-lucide-x"
          variant="ghost"
          color="slate"
          size="xs"
          :aria-label="t('TOLZAR_INBOX.SUMMARY.CLOSE')"
          @click="open = false"
        />
      </div>
      <p class="m-0 mt-1 text-xs text-n-slate-10">
        {{ t('TOLZAR_INBOX.SUMMARY.STAFF_ONLY') }}
      </p>
      <p v-if="loading" class="m-0 mt-3 text-sm text-n-slate-11">
        {{ t('TOLZAR_INBOX.SUMMARY.LOADING') }}
      </p>
      <p v-else-if="failed" class="m-0 mt-3 text-sm text-n-ruby-11">
        {{ t('TOLZAR_INBOX.SUMMARY.FAILED') }}
      </p>
      <p
        v-else
        class="m-0 mt-3 text-sm text-n-slate-12 whitespace-pre-line max-h-64 overflow-y-auto"
      >
        {{ summary }}
      </p>
      <div class="flex justify-end gap-2 mt-3">
        <Button
          v-if="failed"
          :label="t('TOLZAR_INBOX.SUMMARY.RETRY')"
          variant="faded"
          color="slate"
          size="sm"
          @click="summarise"
        />
        <Button
          v-else-if="!loading"
          :label="t('TOLZAR_INBOX.SUMMARY.SAVE_NOTE')"
          size="sm"
          :is-loading="saving"
          @click="saveNote"
        />
      </div>
    </div>
  </div>
</template>
