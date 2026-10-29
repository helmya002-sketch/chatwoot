<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import BrainNotice from './BrainNotice.vue';
import { BTN, BTN_GHOST, INPUT } from './tzClasses';
import {
  DEFAULT_STAGES,
  DEFAULT_STAGE_ATTRIBUTES,
  applyPipelineStages,
} from '../tolzarStages';

// Settings hub → Pipeline: this workspace's stages (in funnel order; the last two are won and
// lost), which contact fields hold the stage, which one holds a deal's value, and its currency.
// Stored in account.settings through TolzarController#pipeline_settings_save (Owner only).
const { t } = useI18n();
const store = useStore();
const accountId = useMapGetter('getCurrentAccountId');
const TONES = ['slate', 'amber', 'iris', 'teal', 'ruby'];

const stages = ref([]);
const stageFields = ref('');
const dealField = ref('');
const currency = ref('');
const result = ref(null);
const saved = ref('');
const busy = ref(false);

const url = computed(
  () => `/api/v1/accounts/${accountId.value}/tolzar/pipeline`
);

function fill(settings = {}) {
  const list =
    Array.isArray(settings.pipeline_stages) && settings.pipeline_stages.length
      ? settings.pipeline_stages
      : DEFAULT_STAGES;
  stages.value = list.map(s => ({
    key: s.key,
    label: s.label || s.key,
    tone: s.tone || 'slate',
  }));
  stageFields.value = (
    settings.stage_attributes || DEFAULT_STAGE_ATTRIBUTES
  ).join(', ');
  dealField.value = settings.deal_value_attribute || '';
  currency.value = settings.deal_currency || '';
}

async function load() {
  try {
    const { data } = await window.axios.get(url.value);
    fill(data?.settings || {});
  } catch (e) {
    result.value = e?.response?.data || {
      ok: false,
      error: 'brain_unreachable',
    };
    fill({});
  }
}

function addStage() {
  stages.value.splice(Math.max(0, stages.value.length - 2), 0, {
    key: '',
    label: '',
    tone: 'iris',
  });
}
function move(i, by) {
  const j = i + by;
  if (j < 0 || j >= stages.value.length) return;
  const [s] = stages.value.splice(i, 1);
  stages.value.splice(j, 0, s);
}

async function save() {
  busy.value = true;
  saved.value = '';
  result.value = null;
  const settings = {
    pipeline_stages: stages.value
      .filter(s => s.key.trim())
      .map(s => ({
        key: s.key.trim(),
        label: (s.label || s.key).trim(),
        tone: s.tone,
      })),
    stage_attributes: stageFields.value
      .split(',')
      .map(x => x.trim())
      .filter(Boolean),
    deal_value_attribute: dealField.value.trim(),
    deal_currency: currency.value.trim().toUpperCase(),
  };
  try {
    const { data } = await window.axios.post(url.value, { settings });
    result.value = data;
    saved.value = t('TOLZAR_SETTINGS.R1.SAVED');
    // The account JSON carries the settings every page reads; refresh it and apply here.
    await store.dispatch('accounts/get').catch(() => {});
    applyPipelineStages(data?.settings || {});
    fill(data?.settings || {});
  } catch (e) {
    result.value = e?.response?.data || {
      ok: false,
      error: 'brain_unreachable',
    };
  } finally {
    busy.value = false;
  }
}

onMounted(load);
</script>

<template>
  <div data-tz-pipeline-settings>
    <h3 class="m-0 text-[14px] font-semibold text-n-slate-12">
      {{ t('TOLZAR_PIPELINE.STAGES') }}
    </h3>
    <p class="mt-1 mb-2 text-xs text-n-slate-10">
      {{ t('TOLZAR_PIPELINE.STAGES_HINT') }}
    </p>
    <div
      v-for="(s, i) in stages"
      :key="i"
      class="flex gap-2 items-center mb-1.5"
    >
      <input
        v-model="s.key"
        :class="INPUT"
        class="!mt-0 !w-[200px]"
        :placeholder="t('TOLZAR_PIPELINE.KEY')"
      />
      <input
        v-model="s.label"
        :class="INPUT"
        class="!mt-0 !w-[160px]"
        :placeholder="t('TOLZAR_PIPELINE.LABEL')"
      />
      <select v-model="s.tone" :class="INPUT" class="!mt-0 !w-auto">
        <option v-for="tone in TONES" :key="tone" :value="tone">
          {{ t(`TOLZAR_PIPELINE.TONE.${tone}`) }}
        </option>
      </select>
      <button
        type="button"
        :class="BTN_GHOST"
        class="!mt-0 !h-8 !px-2"
        :disabled="i === 0"
        @click="move(i, -1)"
      >
        <span class="i-lucide-arrow-up size-3.5" />
      </button>
      <button
        type="button"
        :class="BTN_GHOST"
        class="!mt-0 !h-8 !px-2"
        :disabled="i === stages.length - 1"
        @click="move(i, 1)"
      >
        <span class="i-lucide-arrow-down size-3.5" />
      </button>
      <button
        type="button"
        :class="BTN_GHOST"
        class="!mt-0 !h-8 !px-2"
        :disabled="stages.length <= 2"
        @click="stages.splice(i, 1)"
      >
        <span class="i-lucide-x size-3.5" />
      </button>
    </div>
    <button
      type="button"
      :class="BTN_GHOST"
      :disabled="stages.length >= 12"
      @click="addStage"
    >
      {{ t('TOLZAR_PIPELINE.ADD') }}
    </button>

    <label class="block mt-4 text-[13px] font-semibold text-n-slate-12">
      {{ t('TOLZAR_PIPELINE.STAGE_FIELDS') }}
      <input
        v-model="stageFields"
        :class="INPUT"
        placeholder="lifecycle_stage"
      />
    </label>
    <p class="mt-1 mb-0 text-xs text-n-slate-10">
      {{ t('TOLZAR_PIPELINE.STAGE_FIELDS_HINT') }}
    </p>

    <div class="flex flex-wrap gap-4 mt-3">
      <label class="block text-[13px] font-semibold text-n-slate-12">
        {{ t('TOLZAR_PIPELINE.DEAL_FIELD') }}
        <input
          v-model="dealField"
          :class="INPUT"
          class="!w-[220px]"
          placeholder="deal_value"
        />
      </label>
      <label class="block text-[13px] font-semibold text-n-slate-12">
        {{ t('TOLZAR_PIPELINE.CURRENCY') }}
        <input
          v-model="currency"
          :class="INPUT"
          class="!w-[100px]"
          maxlength="3"
          placeholder="EUR"
        />
      </label>
    </div>

    <button type="button" :class="BTN" :disabled="busy" @click="save">
      {{ t('TOLZAR_PIPELINE.SAVE') }}
    </button>
    <BrainNotice :result="result" :saved="saved" />
  </div>
</template>
