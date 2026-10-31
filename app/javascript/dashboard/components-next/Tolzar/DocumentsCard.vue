<script setup>
import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';

// Conversation sidebar → this contact's booking documents (Tolzar::Document): number, type and status, newest
// first. Hidden when the workspace has documents off (404) or the contact has none.
const props = defineProps({
  contactId: { type: [Number, String], default: null },
});
const { t } = useI18n();
const accountId = useMapGetter('getCurrentAccountId');
const docs = ref([]);

async function load() {
  docs.value = [];
  if (!props.contactId) return;
  try {
    const { data } = await window.axios.get(
      `/api/v1/accounts/${accountId.value}/tolzar/documents`,
      { params: { contact_id: props.contactId } }
    );
    docs.value = (data.documents || []).slice(0, 10);
  } catch {
    docs.value = [];
  }
}

const label = d => d.number || t('TOLZAR_SETTINGS_UI.DOCS.NO_NUMBER');

watch(() => props.contactId, load, { immediate: true });
</script>

<template>
  <section
    v-if="docs.length"
    class="mt-3 p-3 rounded-xl border border-solid border-n-weak bg-n-solid-1"
  >
    <h3 class="m-0 mb-2 text-xs font-semibold text-n-slate-11 uppercase">
      {{ t('TOLZAR_SETTINGS_UI.DOCS.CARD_TITLE') }}
    </h3>
    <ul class="m-0 p-0 list-none flex flex-col gap-1.5">
      <li
        v-for="d in docs"
        :key="d.id"
        class="flex justify-between gap-2 text-xs"
      >
        <span class="font-mono text-n-slate-12">{{ label(d) }}</span>
        <span class="text-n-slate-11">{{
          t(`TOLZAR_SETTINGS_UI.DOCS.T_${d.doc_type}`)
        }}</span>
        <span class="text-n-slate-11">{{
          t(`TOLZAR_SETTINGS_UI.DOCS.ST_${d.status}`)
        }}</span>
      </li>
    </ul>
  </section>
</template>
