<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { BTN, BTN_GHOST, LABEL } from './tzClasses';

// AI Agents → one agent → Upload a price file: a private CSV or XLSX (columns item, price, currency,
// optional category, where, url). Strict: one bad row rejects the file, with every problem listed
// by row. Accepted files become the agent's price table; the last 10 are kept and can be restored.
// The file is never published anywhere. Upload and restore are Owner-only.
const props = defineProps({ agentId: { type: String, required: true } });
const emit = defineEmits(['saved']);
const { t } = useI18n();
const accountId = useMapGetter('getCurrentAccountId');

const versions = ref([]);
const file = ref(null);
const busy = ref(false);
const error = ref('');
const problems = ref([]);
const done = ref(null);
const base = computed(
  () =>
    `/api/v1/accounts/${accountId.value}/tolzar/agents/${encodeURIComponent(props.agentId)}/price_upload`
);
const current = computed(() => versions.value.find(v => v.current));

async function load() {
  try {
    const { data } = await window.axios.get(base.value);
    versions.value = (data && data.versions) || [];
  } catch (e) {
    versions.value = [];
  }
}

function failed(e) {
  const status = e?.response?.status;
  const data = e?.response?.data || {};
  problems.value = Array.isArray(data.errors) ? data.errors : [];
  if (status === 403) {
    error.value = t('TOLZAR_SETTINGS.PRICE_UPLOAD.OWNER_ONLY');
  } else if (data.error && !problems.value.length) {
    error.value = String(data.error);
  } else {
    error.value = t('TOLZAR_SETTINGS.PRICE_UPLOAD.REJECTED');
  }
}

async function upload() {
  if (!file.value) return;
  busy.value = true;
  error.value = '';
  problems.value = [];
  done.value = null;
  try {
    const form = new FormData();
    form.append('file', file.value);
    const { data } = await window.axios.post(base.value, form);
    done.value = data.version;
    file.value = null;
    await load();
    emit('saved');
  } catch (e) {
    failed(e);
  } finally {
    busy.value = false;
  }
}

async function restore(version) {
  busy.value = true;
  error.value = '';
  problems.value = [];
  try {
    await window.axios.post(`${base.value}/restore`, { version });
    await load();
    emit('saved');
  } catch (e) {
    failed(e);
  } finally {
    busy.value = false;
  }
}

const at = s =>
  String(s || '')
    .slice(0, 16)
    .replace('T', ' ');

onMounted(load);
</script>

<template>
  <div class="mt-4">
    <h4 class="m-0 text-sm font-semibold text-n-slate-12">
      {{ t('TOLZAR_SETTINGS.PRICE_UPLOAD.TITLE') }}
    </h4>
    <p class="mt-1 mb-0 text-[13px] text-n-slate-11">
      {{ t('TOLZAR_SETTINGS.PRICE_UPLOAD.WHAT') }}
    </p>
    <p v-if="current" class="mt-2 mb-0 text-[13px] text-n-slate-12">
      {{
        t('TOLZAR_SETTINGS.PRICE_UPLOAD.CURRENT', {
          version: current.version,
          rows: current.rows,
          file: current.filename,
          at: at(current.at),
        })
      }}
    </p>
    <label :class="LABEL">{{ t('TOLZAR_SETTINGS.PRICE_UPLOAD.CHOOSE') }}</label>
    <input
      type="file"
      accept=".csv,.xlsx"
      class="text-[13px]"
      @change="file = $event.target.files[0] || null"
    />
    <button :class="BTN" :disabled="!file || busy" @click="upload">
      {{ t('TOLZAR_SETTINGS.PRICE_UPLOAD.UPLOAD') }}
    </button>
    <p v-if="done" class="mt-3 mb-0 text-[13px] text-n-slate-12">
      {{
        t('TOLZAR_SETTINGS.PRICE_UPLOAD.ACCEPTED', {
          version: done.version,
          rows: done.rows,
        })
      }}
    </p>
    <p v-if="error" class="mt-3 mb-0 text-[13px] text-n-ruby-11">{{ error }}</p>
    <ul
      v-if="problems.length"
      class="mt-1 mb-0 pl-4 text-[13px] text-n-ruby-11 list-disc"
    >
      <li v-for="(p, i) in problems" :key="i">
        {{
          p.row
            ? t('TOLZAR_SETTINGS.PRICE_UPLOAD.ROW', {
                row: p.row,
                error: p.error,
              })
            : p.error
        }}
      </li>
    </ul>
    <div v-if="versions.length > 1" class="mt-4">
      <div :class="LABEL">{{ t('TOLZAR_SETTINGS.PRICE_UPLOAD.VERSIONS') }}</div>
      <div
        v-for="v in versions"
        :key="v.version"
        class="flex gap-2 items-center text-[13px] text-n-slate-11"
      >
        <span>{{
          t('TOLZAR_SETTINGS.PRICE_UPLOAD.VERSION_ROW', {
            version: v.version,
            rows: v.rows,
            at: at(v.at),
          })
        }}</span>
        <button
          v-if="!v.current"
          :class="BTN_GHOST"
          class="!mt-0 !h-7"
          :disabled="busy"
          @click="restore(v.version)"
        >
          {{ t('TOLZAR_SETTINGS.PRICE_UPLOAD.RESTORE') }}
        </button>
      </div>
    </div>
  </div>
</template>
