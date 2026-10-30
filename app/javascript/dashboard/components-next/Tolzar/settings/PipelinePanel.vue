<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import ConfirmDialog from '../ConfirmDialog.vue';
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
// TODO(backend): Tolzar::PipelineSettings::KEYS has no `won_stage` / `lost_stage` field, so won and
// lost are still "the last two by position". Add those keys to the save body and the view, then
// replace the position rule with two selects here and in tolzarStages.wonStage/lostStage.
const { t } = useI18n();
const store = useStore();
const accountId = useMapGetter('getCurrentAccountId');
const TONES = ['slate', 'amber', 'iris', 'teal', 'ruby'];
// A swatch next to the tone select, in theme tokens (static strings so Tailwind keeps them).
const TONE_DOT = {
  slate: 'bg-n-slate-9',
  amber: 'bg-n-amber-9',
  iris: 'bg-n-iris-9',
  teal: 'bg-n-teal-9',
  ruby: 'bg-n-ruby-9',
};

const stages = ref([]);
const stageFields = ref('');
const dealField = ref('');
const currency = ref('');
const result = ref(null);
const saved = ref('');
const busy = ref(false);
const confirmRef = ref(null);

const url = computed(
  () => `/api/v1/accounts/${accountId.value}/tolzar/pipeline`
);

// Rows carry a stable id so reordering keeps focus and Vue never re-mounts an input by index.
let rowSeq = 0;
const rowId = () => {
  rowSeq += 1;
  return `stage-${Date.now().toString(36)}-${rowSeq}`;
};

function fill(settings = {}) {
  const list =
    Array.isArray(settings.pipeline_stages) && settings.pipeline_stages.length
      ? settings.pipeline_stages
      : DEFAULT_STAGES;
  stages.value = list.map(s => ({
    id: rowId(),
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
    id: rowId(),
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
// Deleting a stage never touches contacts: those still in it keep a value that is no longer in
// the list and show as an unknown stage until someone moves them. Say so before removing.
async function removeStage(i) {
  const s = stages.value[i];
  if (!s) return;
  const name = (s.label || s.key || '').trim();
  const ok = await confirmRef.value?.ask({
    title: name
      ? t('TOLZAR_SETTINGS_UI.PIPELINE.DELETE_TITLE', { name })
      : t('TOLZAR_SETTINGS_UI.PIPELINE.DELETE_TITLE_EMPTY'),
    description: t('TOLZAR_SETTINGS_UI.PIPELINE.DELETE_BODY'),
    confirmLabel: t('TOLZAR_UI.DELETE'),
    cancelLabel: t('TOLZAR_UI.CANCEL'),
    danger: true,
  });
  if (ok) stages.value.splice(i, 1);
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
      :key="s.id"
      class="flex flex-wrap gap-2 items-center mb-1.5"
    >
      <input
        v-model="s.key"
        :class="INPUT"
        class="!mt-0 !w-[200px]"
        :placeholder="t('TOLZAR_PIPELINE.KEY')"
        :aria-label="t('TOLZAR_PIPELINE.KEY')"
      />
      <input
        v-model="s.label"
        :class="INPUT"
        class="!mt-0 !w-[160px]"
        :placeholder="t('TOLZAR_PIPELINE.LABEL')"
        :aria-label="t('TOLZAR_PIPELINE.LABEL')"
      />
      <span
        class="rounded-full size-3 shrink-0"
        :class="TONE_DOT[s.tone] || TONE_DOT.slate"
        aria-hidden="true"
      />
      <select
        v-model="s.tone"
        :class="INPUT"
        class="!mt-0 !w-auto"
        :aria-label="t('TOLZAR_SETTINGS_UI.PIPELINE.TONE')"
      >
        <option v-for="tone in TONES" :key="tone" :value="tone">
          {{ t(`TOLZAR_PIPELINE.TONE.${tone}`) }}
        </option>
      </select>
      <button
        type="button"
        :class="BTN_GHOST"
        class="!mt-0 !h-8 !px-2"
        :disabled="i === 0"
        :aria-label="t('TOLZAR_SETTINGS_UI.PIPELINE.MOVE_UP')"
        @click="move(i, -1)"
      >
        <span class="i-lucide-arrow-up size-3.5" aria-hidden="true" />
      </button>
      <button
        type="button"
        :class="BTN_GHOST"
        class="!mt-0 !h-8 !px-2"
        :disabled="i === stages.length - 1"
        :aria-label="t('TOLZAR_SETTINGS_UI.PIPELINE.MOVE_DOWN')"
        @click="move(i, 1)"
      >
        <span class="i-lucide-arrow-down size-3.5" aria-hidden="true" />
      </button>
      <button
        type="button"
        :class="BTN_GHOST"
        class="!mt-0 !h-8 !px-2"
        :disabled="stages.length <= 2"
        :aria-label="t('TOLZAR_SETTINGS_UI.PIPELINE.REMOVE')"
        @click="removeStage(i)"
      >
        <span class="i-lucide-x size-3.5" aria-hidden="true" />
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
        :placeholder="t('TOLZAR_SETTINGS_UI.PIPELINE.STAGE_FIELDS_PLACEHOLDER')"
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
          :placeholder="t('TOLZAR_SETTINGS_UI.PIPELINE.DEAL_FIELD_PLACEHOLDER')"
        />
      </label>
      <label class="block text-[13px] font-semibold text-n-slate-12">
        {{ t('TOLZAR_PIPELINE.CURRENCY') }}
        <input
          v-model="currency"
          :class="INPUT"
          class="!w-[100px]"
          maxlength="3"
          :placeholder="t('TOLZAR_SETTINGS_UI.PIPELINE.CURRENCY_PLACEHOLDER')"
        />
      </label>
    </div>

    <button type="button" :class="BTN" :disabled="busy" @click="save">
      {{ busy ? t('TOLZAR_UI.SAVING') : t('TOLZAR_PIPELINE.SAVE') }}
    </button>
    <ConfirmDialog ref="confirmRef" />
    <BrainNotice :result="result" :saved="saved" />
  </div>
</template>
