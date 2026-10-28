<script setup>
import { ref, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import BrainNotice from './BrainNotice.vue';
import { BTN, INPUT, LABEL, SHADOW_BADGE } from './tzClasses';
import { MEDIA_MODES, getDocuments, saveDocuments } from '../tolzarMedia';

// Settings hub → AI: read attachments customers send (PDFs) in Shadow. The text is read for
// triage only and never stored (brain plugins/documents.py). Off / Shadow, never live.
const { t } = useI18n();
const accountId = useMapGetter('getCurrentAccountId');

const mode = ref(null);
const result = ref(null);
const saved = ref('');
const busy = ref(false);

async function load() {
  const r = await getDocuments(accountId.value);
  result.value = r && r.ok ? null : r;
  mode.value = (r && r.config && r.config.mode) || 'off';
}
async function save() {
  busy.value = true;
  try {
    const r = await saveDocuments(accountId.value, mode.value);
    result.value = r;
    saved.value = r && r.ok ? t('TOLZAR_SETTINGS.R1.SAVED') : '';
    if (r && r.ok) mode.value = r.config.mode;
  } finally {
    busy.value = false;
  }
}

onMounted(load);
</script>

<template>
  <div v-if="mode" class="max-w-[520px]">
    <span :class="SHADOW_BADGE">{{ t('TOLZAR_SETTINGS.R1.SHADOW_ONLY') }}</span>
    <label :class="LABEL">{{ t('TOLZAR_SETTINGS.DOCUMENTS.MODE') }}</label>
    <select v-model="mode" :class="INPUT">
      <option v-for="m in MEDIA_MODES" :key="m" :value="m">
        {{ t(`TOLZAR_SETTINGS.MODES.${m}`) }}
      </option>
    </select>
    <p class="mt-2 mb-0 text-xs text-n-slate-10">
      {{ t('TOLZAR_SETTINGS.DOCUMENTS.EXPLAIN') }}
    </p>
    <button type="button" :class="BTN" :disabled="busy" @click="save">
      {{ t('TOLZAR_SETTINGS.SAVE') }}
    </button>
    <BrainNotice :result="result" :saved="saved" />
  </div>
</template>
