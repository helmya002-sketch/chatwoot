<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { BTN, INPUT, LABEL } from './tzClasses';
import { readLogo, LOGO_MAX } from './tolzarDocuments';

// Settings hub → Workspace → Documents → Template (Tolzar::DocumentBranding, owner): accent colour, logo (kept in
// the workspace, never fetched from a URL), address, and per type the title and the "Good to know" terms. Empty
// terms use the industry pack's default, shown as the placeholder.
const { t } = useI18n();
const accountId = useMapGetter('getCurrentAccountId');
const base = computed(
  () => `/api/v1/accounts/${accountId.value}/tolzar/documents_settings`
);
const TYPES = ['voucher', 'quote', 'confirmation', 'payment_summary'];
const form = ref({ colour: '', address: '', logo: '', titles: {}, terms: {} });
const defaults = ref({});
const kind = ref('voucher');
const DEFAULT_COLOUR = '#3E63DD';
const notice = ref('');

function fill(data) {
  const b = data.branding || {};
  form.value = {
    colour: b.colour || '',
    address: b.address || '',
    logo: b.logo || '',
    titles: { ...(b.titles || {}) },
    terms: { ...(b.terms || {}) },
  };
  defaults.value = data.default_terms || {};
}

async function load() {
  try {
    const { data } = await window.axios.get(base.value);
    fill(data);
  } catch {
    notice.value = t('TOLZAR_SETTINGS_UI.DOCS.FAILED');
  }
}

async function pickLogo(event) {
  notice.value = '';
  const file = event.target.files && event.target.files[0];
  const result = await readLogo(file);
  if (result.error) {
    notice.value = t('TOLZAR_SETTINGS_UI.DOCS.LOGO_BAD', {
      kb: Math.floor(LOGO_MAX / 1000),
    });
    return;
  }
  form.value.logo = result.dataUrl;
}

async function save() {
  notice.value = '';
  try {
    const { data } = await window.axios.post(base.value, {
      branding: form.value,
    });
    fill(data);
    notice.value = t('TOLZAR_SETTINGS_UI.DOCS.SAVED');
  } catch (e) {
    notice.value =
      e?.response?.status === 403
        ? t('TOLZAR_SETTINGS.R1.OWNER_ONLY')
        : e?.response?.data?.error || t('TOLZAR_SETTINGS_UI.DOCS.FAILED');
  }
}

onMounted(load);
</script>

<template>
  <section class="mt-6">
    <h3 class="m-0 mb-1 text-sm font-semibold text-n-slate-12">
      {{ t('TOLZAR_SETTINGS_UI.DOCS.TEMPLATE') }}
    </h3>
    <p class="m-0 text-xs text-n-slate-10">
      {{ t('TOLZAR_SETTINGS_UI.DOCS.TEMPLATE_HINT') }}
    </p>
    <p v-if="notice" class="text-[13px] text-n-slate-12" role="status">
      {{ notice }}
    </p>
    <div class="grid gap-3 md:grid-cols-2">
      <div>
        <label :class="LABEL" for="tz-doc-colour">{{
          t('TOLZAR_SETTINGS_UI.DOCS.COLOUR')
        }}</label>
        <div class="flex gap-2 items-center">
          <input
            id="tz-doc-colour"
            v-model="form.colour"
            :class="INPUT"
            class="!w-32 font-mono"
            :placeholder="DEFAULT_COLOUR"
            maxlength="7"
          />
          <span
            class="inline-block w-6 h-6 rounded border border-solid border-n-weak"
            :style="{ background: form.colour || DEFAULT_COLOUR }"
            aria-hidden="true"
          />
        </div>
      </div>
      <div>
        <label :class="LABEL" for="tz-doc-logo">{{
          t('TOLZAR_SETTINGS_UI.DOCS.LOGO')
        }}</label>
        <input
          id="tz-doc-logo"
          type="file"
          accept="image/png,image/jpeg"
          class="text-xs"
          @change="pickLogo"
        />
        <div v-if="form.logo" class="flex gap-2 items-center mt-1">
          <img
            :src="form.logo"
            :alt="t('TOLZAR_SETTINGS_UI.DOCS.LOGO')"
            class="max-h-10 max-w-[140px]"
          />
          <button
            type="button"
            class="p-0 text-xs text-n-ruby-11 bg-transparent"
            @click="form.logo = ''"
          >
            {{ t('TOLZAR_SETTINGS_UI.DOCS.REMOVE') }}
          </button>
        </div>
      </div>
    </div>
    <label :class="LABEL" for="tz-doc-address">{{
      t('TOLZAR_SETTINGS_UI.DOCS.ADDRESS')
    }}</label>
    <input
      id="tz-doc-address"
      v-model="form.address"
      :class="INPUT"
      maxlength="300"
    />
    <label :class="LABEL" for="tz-doc-kind">{{
      t('TOLZAR_SETTINGS_UI.DOCS.TYPE')
    }}</label>
    <select id="tz-doc-kind" v-model="kind" :class="INPUT" class="!w-60">
      <option v-for="ty in TYPES" :key="ty" :value="ty">
        {{ t(`TOLZAR_SETTINGS_UI.DOCS.T_${ty}`) }}
      </option>
    </select>
    <label :class="LABEL" for="tz-doc-title">{{
      t('TOLZAR_SETTINGS_UI.DOCS.DOC_TITLE')
    }}</label>
    <input
      id="tz-doc-title"
      v-model="form.titles[kind]"
      :class="INPUT"
      maxlength="60"
      :placeholder="t(`TOLZAR_SETTINGS_UI.DOCS.T_${kind}`)"
    />
    <label :class="LABEL" for="tz-doc-terms">{{
      t('TOLZAR_SETTINGS_UI.DOCS.TERMS')
    }}</label>
    <textarea
      id="tz-doc-terms"
      v-model="form.terms[kind]"
      :class="INPUT"
      rows="4"
      maxlength="2000"
      :placeholder="defaults[kind] || ''"
    />
    <button type="button" :class="BTN" @click="save">
      {{ t('TOLZAR_SETTINGS_UI.DOCS.SAVE_TEMPLATE') }}
    </button>
  </section>
</template>
