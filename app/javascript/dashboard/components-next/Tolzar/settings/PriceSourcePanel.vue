<script setup>
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import BrainNotice from './BrainNotice.vue';
import { BTN, BTN_GHOST, INPUT, LABEL } from './tzClasses';
import {
  PRICE_TYPES,
  defaultRefreshHours,
  getPriceSource,
  savePriceSource,
  testPriceSource,
  priceSourceForm,
  priceSourceProblems,
  priceSourceBody,
  sampleColumns,
} from '../tolzarWorkspace';

// AI Agents → one agent → Price source: where the agent's prices come from (a web page with
// structured data, a JSON feed, a CSV table or the shop's catalogue). "Test fetch" is read-only
// (row count + 3 sample rows); saving is Owner-only (the proxy refuses a Manager).
const props = defineProps({ agentId: { type: String, required: true } });
const emit = defineEmits(['saved']);
const { t } = useI18n();
const accountId = useMapGetter('getCurrentAccountId');

const view = ref(null);
const form = ref(priceSourceForm(null));
const test = ref(null); // the last test fetch's answer, for the form it was made with
const testedFor = ref('');
const result = ref(null);
const saved = ref('');
const busy = ref(false);

const problems = computed(() => priceSourceProblems(form.value));
const body = computed(() => priceSourceBody(form.value));
const tested = computed(
  () =>
    !!test.value &&
    test.value.ok &&
    testedFor.value === JSON.stringify(body.value)
);
const columns = computed(() => sampleColumns(test.value && test.value.sample));

async function load() {
  view.value = null;
  test.value = null;
  result.value = null;
  saved.value = '';
  try {
    const v = await getPriceSource(accountId.value, props.agentId);
    if (v && v.ok) {
      view.value = v;
      form.value = priceSourceForm(v);
    }
  } catch (e) {
    /* non-fatal: the form starts empty */
  }
}
watch(() => props.agentId, load, { immediate: true });
watch(
  () => form.value.type,
  (type, was) => {
    if (was && form.value.refresh_hours === defaultRefreshHours(was))
      form.value.refresh_hours = defaultRefreshHours(type);
  }
);

async function runTest() {
  if (problems.value.length) return;
  busy.value = true;
  saved.value = '';
  result.value = null;
  const sent = JSON.stringify(body.value);
  try {
    const r = await testPriceSource(accountId.value, props.agentId, body.value);
    test.value = r;
    testedFor.value = sent;
  } catch (e) {
    result.value = { ok: false, error: 'brain_unreachable' };
  } finally {
    busy.value = false;
  }
}
async function save() {
  busy.value = true;
  saved.value = '';
  try {
    const r = await savePriceSource(accountId.value, props.agentId, body.value);
    result.value = r;
    if (r && r.ok) {
      view.value = r;
      form.value = priceSourceForm(r);
      saved.value = t('TOLZAR_WORKSPACE.PRICE.SAVED');
      emit('saved', r.source);
    }
  } catch (e) {
    result.value = { ok: false, error: 'brain_unreachable' };
  } finally {
    busy.value = false;
  }
}
const cell = v => {
  if (v === null || v === undefined) return '';
  return typeof v === 'object' ? JSON.stringify(v) : String(v);
};
</script>

<template>
  <section
    class="p-[18px] rounded-2xl border shadow-sm bg-n-solid-1 border-n-weak"
    data-tz-price-source
  >
    <h3 class="m-0 text-[15px] font-semibold text-n-slate-12">
      {{ t('TOLZAR_WORKSPACE.PRICE.TITLE') }}
    </h3>
    <p class="mt-1.5 mb-0 text-xs text-n-slate-11">
      {{ t('TOLZAR_WORKSPACE.PRICE.HINT') }}
    </p>
    <p class="mt-1.5 mb-0 text-xs text-n-slate-10">
      {{
        view && view.rows
          ? t('TOLZAR_WORKSPACE.PRICE.LOADED', {
              n: view.rows,
              at: String(view.fetched_at || '—')
                .slice(0, 16)
                .replace('T', ' '),
            })
          : t('TOLZAR_WORKSPACE.PRICE.NOT_LOADED')
      }}
    </p>
    <div
      class="grid gap-x-3 max-w-[620px] md:grid-cols-[180px_minmax(0,1fr)_120px]"
    >
      <div>
        <label :class="LABEL">{{ t('TOLZAR_WORKSPACE.PRICE.TYPE') }}</label>
        <select v-model="form.type" :class="INPUT">
          <option v-for="ty in PRICE_TYPES" :key="ty" :value="ty">
            {{ t(`TOLZAR_WORKSPACE.PRICE.TYPES.${ty}`) }}
          </option>
        </select>
      </div>
      <template v-if="form.type !== 'commerce'">
        <div>
          <label :class="LABEL">{{ t('TOLZAR_WORKSPACE.PRICE.URL') }}</label>
          <input
            v-model="form.url"
            type="url"
            :class="INPUT"
            :placeholder="t('TOLZAR_WORKSPACE.PRICE.URL_PLACEHOLDER')"
          />
        </div>
        <div>
          <label :class="LABEL">{{
            t('TOLZAR_WORKSPACE.PRICE.REFRESH')
          }}</label>
          <input
            v-model.number="form.refresh_hours"
            type="number"
            min="1"
            max="168"
            :class="INPUT"
          />
        </div>
      </template>
      <p v-else class="self-end m-0 mt-2 text-xs md:col-span-2 text-n-slate-10">
        {{ t('TOLZAR_WORKSPACE.PRICE.COMMERCE_HINT') }}
      </p>
    </div>
    <p v-for="p in problems" :key="p" class="m-0 mt-1 text-xs text-n-ruby-11">
      {{ t(`TOLZAR_WORKSPACE.PRICE.PROBLEM.${p}`) }}
    </p>

    <div class="flex flex-wrap gap-2 items-center">
      <button
        type="button"
        :class="BTN_GHOST"
        :disabled="busy || problems.length > 0"
        data-tz-price-test
        @click="runTest"
      >
        {{ t('TOLZAR_WORKSPACE.PRICE.TEST') }}
      </button>
      <button
        type="button"
        :class="BTN"
        :disabled="busy || !tested"
        @click="save"
      >
        {{ t('TOLZAR_WORKSPACE.PRICE.SAVE') }}
      </button>
      <span
        v-if="!tested && !problems.length"
        class="mt-3 text-xs text-n-slate-10"
      >
        {{ t('TOLZAR_WORKSPACE.PRICE.TEST_FIRST') }}
      </span>
    </div>

    <div v-if="test && test.ok" class="mt-3">
      <p class="m-0 text-[13px] font-semibold text-n-slate-12">
        {{ t('TOLZAR_WORKSPACE.PRICE.ROWS', { n: test.rows }) }}
      </p>
      <div v-if="columns.length" class="overflow-auto mt-2">
        <div class="mb-1 text-xs text-n-slate-10">
          {{ t('TOLZAR_WORKSPACE.PRICE.SAMPLE') }}
        </div>
        <table class="w-full text-xs">
          <thead>
            <tr>
              <th
                v-for="c in columns"
                :key="c"
                class="px-2 py-1 font-semibold text-left text-n-slate-11"
              >
                {{ c }}
              </th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="(r, i) in test.sample"
              :key="i"
              class="border-t border-n-weak"
            >
              <td
                v-for="c in columns"
                :key="c"
                class="px-2 py-1 text-n-slate-12"
              >
                {{ cell(r[c]) }}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    <p
      v-else-if="test && test.error === 'fetch_failed'"
      class="p-2 mt-3 text-[13px] rounded-lg text-n-ruby-11 bg-n-ruby-9/10"
    >
      {{
        t('TOLZAR_WORKSPACE.PRICE.FETCH_FAILED', { detail: test.detail || '' })
      }}
    </p>
    <BrainNotice v-else-if="test && !test.ok" :result="test" />
    <p
      v-if="result && result.error === 'owner_only'"
      class="p-2 mt-3 text-[13px] rounded-lg text-amber-700 bg-amber-500/10"
    >
      {{ t('TOLZAR_WORKSPACE.PRICE.OWNER_SAVE') }}
    </p>
    <BrainNotice v-else :result="result" :saved="saved" />
  </section>
</template>
