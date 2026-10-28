<script setup>
import { ref, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import BrainNotice from './BrainNotice.vue';
import { BTN, BTN_GHOST, BTN_DANGER, INPUT, LABEL } from './tzClasses';
import {
  DISCLOSURE_MODES,
  DISCLOSURE_LANGS,
  getDisclosure,
  saveDisclosure,
  getRetention,
  saveRetention,
  exportContact,
  eraseContact,
  disclosureLine,
  validContactId,
  exportFilename,
} from '../tolzarTrust';

// Settings hub → Trust & privacy: AI disclosure, retention, one contact's data (export / erase).
const props = defineProps({
  section: { type: String, required: true }, // disclosure | retention | privacy
});
const { t } = useI18n();
const accountId = useMapGetter('getCurrentAccountId');

const data = ref(null);
const result = ref(null);
const saved = ref('');
const busy = ref(false);
const contactId = ref('');
const confirmText = ref('');
const erased = ref(null);
const dialogRef = ref(null);

async function load() {
  result.value = null;
  saved.value = '';
  if (props.section === 'disclosure') {
    const r = await getDisclosure(accountId.value);
    data.value = {
      disclosure: r.config?.disclosure || 'auto',
      texts: { ...(r.config?.texts || {}) },
      defaults: r.defaults || {},
    };
  } else if (props.section === 'retention') {
    const r = await getRetention(accountId.value);
    data.value = {
      config: { ...(r.config || r.defaults || {}) },
      defaults: r.defaults || {},
      next: r.next_purge || {},
    };
  } else {
    data.value = {};
  }
}

const after = (r, ok) => {
  result.value = r;
  saved.value = r && r.ok ? ok : '';
};

async function saveDisclosureNow() {
  busy.value = true;
  try {
    after(await saveDisclosure(accountId.value, data.value), t('TOLZAR_SETTINGS.R1.SAVED'));
  } finally {
    busy.value = false;
  }
}
async function saveRetentionNow() {
  busy.value = true;
  try {
    after(await saveRetention(accountId.value, data.value.config), t('TOLZAR_SETTINGS.R1.SAVED'));
  } finally {
    busy.value = false;
  }
}

async function downloadExport() {
  if (!validContactId(contactId.value)) return;
  busy.value = true;
  try {
    const r = await exportContact(accountId.value, contactId.value);
    after(r, '');
    if (!r || !r.ok) return;
    const blob = new Blob([JSON.stringify(r, null, 2)], { type: 'application/json' });
    const a = document.createElement('a');
    a.href = URL.createObjectURL(blob);
    a.download = exportFilename(contactId.value);
    a.click();
    URL.revokeObjectURL(a.href);
    saved.value = t('TOLZAR_SETTINGS.TRUST.EXPORTED');
  } finally {
    busy.value = false;
  }
}

function askErase() {
  if (!validContactId(contactId.value)) return;
  confirmText.value = '';
  erased.value = null;
  dialogRef.value?.open();
}
async function erase() {
  if (confirmText.value.trim() !== String(contactId.value).trim()) return;
  busy.value = true;
  try {
    const r = await eraseContact(accountId.value, contactId.value);
    after(r, t('TOLZAR_SETTINGS.TRUST.ERASED'));
    if (r && r.ok) erased.value = { id: Number(contactId.value), counts: r.deleted || {} };
    dialogRef.value?.close();
  } finally {
    busy.value = false;
  }
}

onMounted(load);
</script>

<template>
  <div v-if="data">
    <!-- AI disclosure -->
    <div v-if="section === 'disclosure'" class="max-w-[620px]">
      <label :class="LABEL">{{ t('TOLZAR_SETTINGS.TRUST.MODE') }}</label>
      <select v-model="data.disclosure" :class="INPUT">
        <option v-for="m in DISCLOSURE_MODES" :key="m" :value="m">{{ t(`TOLZAR_SETTINGS.TRUST.MODES.${m}`) }}</option>
      </select>
      <p class="mt-1 text-xs text-n-slate-10">{{ t(`TOLZAR_SETTINGS.TRUST.MODE_HINT.${data.disclosure}`) }}</p>
      <label :class="LABEL">{{ t('TOLZAR_SETTINGS.TRUST.TEXTS') }}</label>
      <div v-for="lang in DISCLOSURE_LANGS" :key="lang" class="flex gap-2 items-center mb-1.5">
        <span class="w-8 text-xs font-semibold uppercase text-n-slate-10">{{ lang }}</span>
        <input v-model="data.texts[lang]" :class="INPUT" :placeholder="disclosureLine(lang, {}, data.defaults)" />
      </div>
      <p class="text-xs text-n-slate-10">{{ t('TOLZAR_SETTINGS.TRUST.TEXTS_HINT') }}</p>
      <button type="button" :class="BTN" :disabled="busy" @click="saveDisclosureNow">{{ t('TOLZAR_SETTINGS.SAVE') }}</button>
    </div>

    <!-- Retention -->
    <div v-if="section === 'retention'" class="max-w-[520px]">
      <label :class="LABEL">{{ t('TOLZAR_SETTINGS.TRUST.DECISIONS_DAYS') }}</label>
      <input v-model.number="data.config.decisions_days" type="number" min="1" max="3650" :class="INPUT" />
      <label :class="LABEL">{{ t('TOLZAR_SETTINGS.TRUST.KV_DAYS') }}</label>
      <input v-model.number="data.config.kv_days" type="number" min="1" max="3650" :class="INPUT" />
      <p class="text-xs text-n-slate-10">{{ t('TOLZAR_SETTINGS.TRUST.RETENTION_SCOPE') }}</p>
      <div class="p-3 mt-3 rounded-lg bg-n-alpha-1 text-[13px]">
        <div class="text-xs font-semibold text-n-slate-11">{{ t('TOLZAR_SETTINGS.TRUST.NEXT_PURGE') }}</div>
        <div v-for="(v, k) in data.next" :key="k" class="flex justify-between mt-1">
          <span class="text-n-slate-11">{{ t(`TOLZAR_SETTINGS.TRUST.COUNT.${k}`) }}</span><span class="font-semibold">{{ v }}</span>
        </div>
        <p v-if="!Object.keys(data.next).length" class="mt-1 mb-0 text-xs text-n-slate-10">{{ t('TOLZAR_SETTINGS.NONE_YET') }}</p>
      </div>
      <button type="button" :class="BTN" :disabled="busy" @click="saveRetentionNow">{{ t('TOLZAR_SETTINGS.SAVE') }}</button>
    </div>

    <!-- One contact's data: export / erase (Owner only) -->
    <div v-if="section === 'privacy'" class="max-w-[620px]">
      <p class="p-2 text-xs rounded-lg text-amber-700 bg-amber-500/10">{{ t('TOLZAR_SETTINGS.TRUST.OWNER_NOTE') }}</p>
      <label :class="LABEL">{{ t('TOLZAR_SETTINGS.TRUST.CONTACT_ID') }}</label>
      <input v-model="contactId" inputmode="numeric" :class="INPUT" placeholder="1234" />
      <p class="mt-1 text-xs text-n-slate-10">{{ t('TOLZAR_SETTINGS.TRUST.CONTACT_ID_HINT') }}</p>
      <div class="flex flex-wrap gap-2">
        <button type="button" :class="BTN_GHOST" :disabled="busy || !validContactId(contactId)" @click="downloadExport">{{ t('TOLZAR_SETTINGS.TRUST.EXPORT') }}</button>
        <button type="button" :class="BTN_DANGER" :disabled="busy || !validContactId(contactId)" @click="askErase">{{ t('TOLZAR_SETTINGS.TRUST.ERASE') }}</button>
      </div>
      <div v-if="erased" class="p-3 mt-3 rounded-lg border border-solid border-n-weak text-[13px]">
        <div v-for="(n, k) in erased.counts" :key="k" class="flex justify-between"><span class="text-n-slate-11">{{ t(`TOLZAR_SETTINGS.TRUST.COUNT.${k}`) }}</span><b>{{ n }}</b></div>
        <p class="mt-2 mb-0 text-xs text-n-slate-11">{{ t('TOLZAR_SETTINGS.TRUST.NEXT_STEP') }}</p>
        <router-link :to="`/app/accounts/${accountId}/contacts/${erased.id}`" class="text-n-brand">{{ t('TOLZAR_SETTINGS.TRUST.OPEN_CONTACT') }}</router-link>
      </div>
      <Dialog
        ref="dialogRef"
        type="alert"
        :title="t('TOLZAR_SETTINGS.TRUST.CONFIRM_TITLE')"
        :description="t('TOLZAR_SETTINGS.TRUST.CONFIRM_TEXT', { id: contactId })"
        :confirm-button-label="t('TOLZAR_SETTINGS.TRUST.CONFIRM_BUTTON')"
        :disable-confirm-button="confirmText.trim() !== String(contactId).trim()"
        :is-loading="busy"
        @confirm="erase"
      >
        <label :class="LABEL">{{ t('TOLZAR_SETTINGS.TRUST.CONFIRM_TYPE', { id: contactId }) }}</label>
        <input v-model="confirmText" inputmode="numeric" :class="INPUT" />
      </Dialog>
    </div>
    <BrainNotice :result="result" :saved="saved" />
  </div>
</template>
