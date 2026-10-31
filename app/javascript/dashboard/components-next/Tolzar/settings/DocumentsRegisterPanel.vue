<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import {
  BTN,
  BTN_GHOST,
  INPUT,
  LABEL,
  TONE_OK,
  TONE_WARN,
  TONE_BAD,
  TONE_MUTED,
} from './tzClasses';
import { emptyLine, linesTotal, toSpec, PLACEHOLDER } from './tolzarDocuments';

// Settings hub → Workspace → Documents (Tolzar::Document): the register, a draft editor, issue, void and a
// printable view, plus the number prefixes. Staff draft and issue; nothing is sent to a customer from here.
const { t } = useI18n();
const accountId = useMapGetter('getCurrentAccountId');
const base = computed(
  () => `/api/v1/accounts/${accountId.value}/tolzar/documents`
);
const TYPES = ['voucher', 'quote', 'confirmation', 'payment_summary'];
const LINE_TYPES = [
  'course',
  'appointment',
  'room_night',
  'order_item',
  'service',
  'rental',
  'extra',
  'discount',
];

const rows = ref([]);
const loading = ref(true);
const error = ref('');
const notice = ref('');
const filter = ref({ status: '', doc_type: '', q: '' });
const editing = ref(null);
const prefixes = ref({});
const voidReason = ref({});

function blank() {
  return {
    doc_type: 'voucher',
    currency: 'USD',
    conversation_id: '',
    guests: '',
    lines: [emptyLine()],
    paid: '',
    stated_total: '',
    notes: '',
    terms: '',
  };
}

async function load() {
  loading.value = true;
  error.value = '';
  try {
    const { data } = await window.axios.get(base.value, {
      params: filter.value,
    });
    rows.value = data.documents || [];
  } catch (e) {
    error.value =
      e?.response?.status === 404
        ? t('TOLZAR_SETTINGS_UI.DOCS.OFF')
        : t('TOLZAR_SETTINGS_UI.DOCS.FAILED');
  } finally {
    loading.value = false;
  }
}

async function loadPrefixes() {
  try {
    const { data } = await window.axios.get(
      `/api/v1/accounts/${accountId.value}/tolzar/documents_settings`
    );
    prefixes.value = data.prefixes || {};
  } catch {
    prefixes.value = {};
  }
}

const say = (e, fallback) =>
  e?.response?.data?.error ||
  (e?.response?.data?.errors || []).join(' ') ||
  fallback;

async function save() {
  notice.value = '';
  const d = editing.value;
  try {
    await window.axios.post(base.value, {
      doc_type: d.doc_type,
      currency: d.currency,
      conversation_id: d.conversation_id || undefined,
      spec: toSpec(d),
    });
    editing.value = null;
    notice.value = t('TOLZAR_SETTINGS_UI.DOCS.SAVED');
    load();
  } catch (e) {
    notice.value = say(e, t('TOLZAR_SETTINGS_UI.DOCS.FAILED'));
  }
}

async function act(row, action, body = {}) {
  notice.value = '';
  try {
    await window.axios.post(`${base.value}/${row.id}/${action}`, body);
    load();
  } catch (e) {
    notice.value = say(e, t('TOLZAR_SETTINGS_UI.DOCS.FAILED'));
  }
}

async function printDoc(row) {
  const { data } = await window.axios.get(`${base.value}/${row.id}/print`, {
    responseType: 'text',
  });
  const url = URL.createObjectURL(new Blob([data], { type: 'text/html' }));
  window.open(url, '_blank', 'noopener');
  setTimeout(() => URL.revokeObjectURL(url), 60000);
}

async function savePrefixes() {
  notice.value = '';
  try {
    const { data } = await window.axios.post(
      `/api/v1/accounts/${accountId.value}/tolzar/documents_settings`,
      { prefixes: prefixes.value }
    );
    prefixes.value = data.prefixes;
    notice.value = t('TOLZAR_SETTINGS_UI.DOCS.SAVED');
  } catch (e) {
    notice.value =
      e?.response?.status === 403
        ? t('TOLZAR_SETTINGS.R1.OWNER_ONLY')
        : say(e, t('TOLZAR_SETTINGS_UI.DOCS.FAILED'));
  }
}

const tone = s =>
  ({ issued: TONE_OK, draft: TONE_WARN, void: TONE_BAD })[s] || TONE_MUTED;
const money = c => (Number(c || 0) / 100).toFixed(2);
const draftTotal = computed(() =>
  editing.value ? linesTotal(editing.value.lines) : 0
);
const hasPlaceholder = computed(() =>
  editing.value?.lines.some(l => PLACEHOLDER.test(String(l.unit_price)))
);

onMounted(() => {
  load();
  loadPrefixes();
});
</script>

<template>
  <div class="max-w-[900px]">
    <p class="mt-0 text-[13px] text-n-slate-11">
      {{ t('TOLZAR_SETTINGS_UI.DOCS.WHAT') }}
    </p>
    <p v-if="notice" class="text-[13px] text-n-slate-12" role="status">
      {{ notice }}
    </p>

    <div v-if="!editing" class="flex flex-wrap gap-2 items-end">
      <div>
        <label :class="LABEL" for="tz-doc-status">{{
          t('TOLZAR_SETTINGS_UI.DOCS.STATUS')
        }}</label>
        <select
          id="tz-doc-status"
          v-model="filter.status"
          :class="INPUT"
          @change="load"
        >
          <option value="">{{ t('TOLZAR_SETTINGS_UI.DOCS.ALL') }}</option>
          <option v-for="s in ['draft', 'issued', 'void']" :key="s" :value="s">
            {{ t(`TOLZAR_SETTINGS_UI.DOCS.ST_${s}`) }}
          </option>
        </select>
      </div>
      <div>
        <label :class="LABEL" for="tz-doc-type">{{
          t('TOLZAR_SETTINGS_UI.DOCS.TYPE')
        }}</label>
        <select
          id="tz-doc-type"
          v-model="filter.doc_type"
          :class="INPUT"
          @change="load"
        >
          <option value="">{{ t('TOLZAR_SETTINGS_UI.DOCS.ALL') }}</option>
          <option v-for="ty in TYPES" :key="ty" :value="ty">
            {{ t(`TOLZAR_SETTINGS_UI.DOCS.T_${ty}`) }}
          </option>
        </select>
      </div>
      <div class="flex-1 min-w-[180px]">
        <label :class="LABEL" for="tz-doc-q">{{
          t('TOLZAR_SETTINGS_UI.DOCS.SEARCH')
        }}</label>
        <input
          id="tz-doc-q"
          v-model="filter.q"
          :class="INPUT"
          @keyup.enter="load"
        />
      </div>
      <button type="button" :class="BTN" @click="editing = blank()">
        {{ t('TOLZAR_SETTINGS_UI.DOCS.NEW') }}
      </button>
    </div>

    <section
      v-if="editing"
      class="mt-3 p-4 rounded-xl border border-solid border-n-weak"
    >
      <div class="grid grid-cols-3 gap-3">
        <div>
          <label :class="LABEL" for="tz-ed-type">{{
            t('TOLZAR_SETTINGS_UI.DOCS.TYPE')
          }}</label>
          <select id="tz-ed-type" v-model="editing.doc_type" :class="INPUT">
            <option v-for="ty in TYPES" :key="ty" :value="ty">
              {{ t(`TOLZAR_SETTINGS_UI.DOCS.T_${ty}`) }}
            </option>
          </select>
        </div>
        <div>
          <label :class="LABEL" for="tz-ed-cur">{{
            t('TOLZAR_SETTINGS_UI.DOCS.CURRENCY')
          }}</label>
          <input
            id="tz-ed-cur"
            v-model="editing.currency"
            :class="INPUT"
            maxlength="3"
          />
        </div>
        <div>
          <label :class="LABEL" for="tz-ed-conv">{{
            t('TOLZAR_SETTINGS_UI.DOCS.CONVERSATION')
          }}</label>
          <input
            id="tz-ed-conv"
            v-model="editing.conversation_id"
            :class="INPUT"
            inputmode="numeric"
          />
        </div>
      </div>
      <label :class="LABEL" for="tz-ed-guests">{{
        t('TOLZAR_SETTINGS_UI.DOCS.GUESTS')
      }}</label>
      <input id="tz-ed-guests" v-model="editing.guests" :class="INPUT" />
      <p class="mt-1 mb-0 text-xs text-n-slate-10">
        {{ t('TOLZAR_SETTINGS_UI.DOCS.NO_ID') }}
      </p>

      <h3 class="mt-4 mb-1 text-sm font-semibold text-n-slate-12">
        {{ t('TOLZAR_SETTINGS_UI.DOCS.LINES') }}
      </h3>
      <div
        v-for="(line, i) in editing.lines"
        :key="line.key"
        class="grid grid-cols-[8rem_1fr_7rem_4rem_6rem_auto] gap-2 items-center mt-2"
      >
        <select
          v-model="line.type"
          :class="INPUT"
          :aria-label="t('TOLZAR_SETTINGS_UI.DOCS.LINE_TYPE')"
        >
          <option v-for="lt in LINE_TYPES" :key="lt" :value="lt">
            {{ t(`TOLZAR_SETTINGS_UI.DOCS.L_${lt}`) }}
          </option>
        </select>
        <input
          v-model="line.description"
          :class="INPUT"
          :aria-label="t('TOLZAR_SETTINGS_UI.DOCS.DESCRIPTION')"
          :placeholder="t('TOLZAR_SETTINGS_UI.DOCS.DESCRIPTION')"
        />
        <input
          v-model="line.date"
          :class="INPUT"
          type="date"
          :aria-label="t('TOLZAR_SETTINGS_UI.DOCS.DATE')"
        />
        <input
          v-model="line.qty"
          :class="INPUT"
          inputmode="decimal"
          :aria-label="t('TOLZAR_SETTINGS_UI.DOCS.QTY')"
        />
        <input
          v-model="line.unit_price"
          :class="[
            INPUT,
            PLACEHOLDER.test(String(line.unit_price)) ? '!bg-n-amber-3' : '',
          ]"
          inputmode="decimal"
          :aria-label="t('TOLZAR_SETTINGS_UI.DOCS.PRICE')"
          :placeholder="t('TOLZAR_SETTINGS_UI.DOCS.PRICE')"
        />
        <button
          type="button"
          :class="BTN_GHOST"
          class="!mt-0"
          :aria-label="t('TOLZAR_SETTINGS_UI.DOCS.REMOVE_LINE')"
          @click="editing.lines.splice(i, 1)"
        >
          {{ t('TOLZAR_SETTINGS_UI.DOCS.REMOVE') }}
        </button>
      </div>
      <button
        type="button"
        :class="BTN_GHOST"
        @click="editing.lines.push(emptyLine())"
      >
        {{ t('TOLZAR_SETTINGS_UI.DOCS.ADD_LINE') }}
      </button>
      <p class="mt-2 mb-0 text-[13px] text-n-slate-12">
        {{
          t('TOLZAR_SETTINGS_UI.DOCS.TOTAL', {
            total: `${editing.currency} ${money(draftTotal)}`,
          })
        }}
      </p>
      <p v-if="hasPlaceholder" class="mt-1 mb-0 text-xs text-n-amber-11">
        {{ t('TOLZAR_SETTINGS_UI.DOCS.PLACEHOLDER_HINT') }}
      </p>

      <div class="grid grid-cols-2 gap-3">
        <div>
          <label :class="LABEL" for="tz-ed-paid">{{
            t('TOLZAR_SETTINGS_UI.DOCS.PAID')
          }}</label>
          <input
            id="tz-ed-paid"
            v-model="editing.paid"
            :class="INPUT"
            inputmode="decimal"
          />
        </div>
        <div>
          <label :class="LABEL" for="tz-ed-stated">{{
            t('TOLZAR_SETTINGS_UI.DOCS.STATED_TOTAL')
          }}</label>
          <input
            id="tz-ed-stated"
            v-model="editing.stated_total"
            :class="INPUT"
            inputmode="decimal"
          />
        </div>
      </div>
      <label :class="LABEL" for="tz-ed-notes">{{
        t('TOLZAR_SETTINGS_UI.DOCS.NOTES')
      }}</label>
      <textarea
        id="tz-ed-notes"
        v-model="editing.notes"
        :class="INPUT"
        rows="2"
      />
      <label :class="LABEL" for="tz-ed-terms">{{
        t('TOLZAR_SETTINGS_UI.DOCS.TERMS')
      }}</label>
      <textarea
        id="tz-ed-terms"
        v-model="editing.terms"
        :class="INPUT"
        rows="2"
      />
      <div class="flex gap-2">
        <button type="button" :class="BTN" @click="save">
          {{ t('TOLZAR_SETTINGS_UI.DOCS.SAVE_DRAFT') }}
        </button>
        <button type="button" :class="BTN_GHOST" @click="editing = null">
          {{ t('TOLZAR_SETTINGS_UI.DOCS.CANCEL') }}
        </button>
      </div>
    </section>

    <p v-if="loading" class="mt-3 text-[13px] text-n-slate-11">
      {{ t('TOLZAR_SETTINGS_UI.LEAD_INTAKE.LOADING') }}
    </p>
    <p v-else-if="error" class="mt-3 text-[13px] text-n-ruby-11" role="alert">
      {{ error }}
    </p>
    <p
      v-else-if="!rows.length && !editing"
      class="mt-3 text-[13px] text-n-slate-11"
    >
      {{ t('TOLZAR_SETTINGS_UI.DOCS.EMPTY') }}
    </p>
    <table v-else-if="!editing" class="mt-3 w-full text-[13px]">
      <thead class="text-xs text-n-slate-11">
        <tr class="border-b border-n-weak">
          <th class="py-2 pe-3 text-start font-medium">
            {{ t('TOLZAR_SETTINGS_UI.DOCS.NUMBER') }}
          </th>
          <th class="py-2 pe-3 text-start font-medium">
            {{ t('TOLZAR_SETTINGS_UI.DOCS.TYPE') }}
          </th>
          <th class="py-2 pe-3 text-start font-medium">
            {{ t('TOLZAR_SETTINGS_UI.DOCS.CONTACT') }}
          </th>
          <th class="py-2 pe-3 text-end font-medium">
            {{ t('TOLZAR_SETTINGS_UI.DOCS.TOTAL_COL') }}
          </th>
          <th class="py-2 pe-3 text-start font-medium">
            {{ t('TOLZAR_SETTINGS_UI.DOCS.STATUS') }}
          </th>
          <th class="py-2 text-end font-medium">
            {{ t('TOLZAR_SETTINGS_UI.DOCS.ACTIONS') }}
          </th>
        </tr>
      </thead>
      <tbody>
        <tr
          v-for="row in rows"
          :key="row.id"
          class="border-b border-n-weak align-top"
        >
          <td class="py-2 pe-3 font-mono">
            {{ row.number || t('TOLZAR_SETTINGS_UI.DOCS.NO_NUMBER') }}
          </td>
          <td class="py-2 pe-3">
            {{ t(`TOLZAR_SETTINGS_UI.DOCS.T_${row.doc_type}`) }}
          </td>
          <td class="py-2 pe-3">{{ row.contact_name || '–' }}</td>
          <td class="py-2 pe-3 text-end tabular-nums">
            {{ row.currency }} {{ money(row.total_cents) }}
          </td>
          <td class="py-2 pe-3">
            <span class="px-1.5 rounded text-xs" :class="tone(row.status)">{{
              t(`TOLZAR_SETTINGS_UI.DOCS.ST_${row.status}`)
            }}</span>
            <div
              v-if="row.placeholders?.length"
              class="text-xs text-n-amber-11"
            >
              {{ t('TOLZAR_SETTINGS_UI.DOCS.HAS_PLACEHOLDERS') }}
            </div>
          </td>
          <td class="py-2 text-end">
            <div class="flex gap-2 justify-end flex-wrap">
              <button
                type="button"
                :class="BTN_GHOST"
                class="!mt-0"
                @click="printDoc(row)"
              >
                {{ t('TOLZAR_SETTINGS_UI.DOCS.PRINT') }}
              </button>
              <button
                v-if="row.status === 'draft'"
                type="button"
                :class="BTN"
                class="!mt-0"
                @click="act(row, 'issue')"
              >
                {{ t('TOLZAR_SETTINGS_UI.DOCS.ISSUE') }}
              </button>
              <template v-if="row.status === 'issued'">
                <input
                  v-model="voidReason[row.id]"
                  :class="INPUT"
                  class="!w-40"
                  :aria-label="t('TOLZAR_SETTINGS_UI.DOCS.VOID_REASON')"
                  :placeholder="t('TOLZAR_SETTINGS_UI.DOCS.VOID_REASON')"
                />
                <button
                  type="button"
                  :class="BTN_GHOST"
                  class="!mt-0"
                  :disabled="!voidReason[row.id]"
                  @click="act(row, 'void', { reason: voidReason[row.id] })"
                >
                  {{ t('TOLZAR_SETTINGS_UI.DOCS.VOID') }}
                </button>
              </template>
            </div>
          </td>
        </tr>
      </tbody>
    </table>

    <h3 class="mt-6 mb-1 text-sm font-semibold text-n-slate-12">
      {{ t('TOLZAR_SETTINGS_UI.DOCS.PREFIXES') }}
    </h3>
    <p class="m-0 text-xs text-n-slate-10">
      {{ t('TOLZAR_SETTINGS_UI.DOCS.PREFIXES_HINT') }}
    </p>
    <div class="grid grid-cols-4 gap-3">
      <div v-for="ty in TYPES" :key="ty">
        <label :class="LABEL" :for="`tz-prefix-${ty}`">{{
          t(`TOLZAR_SETTINGS_UI.DOCS.T_${ty}`)
        }}</label>
        <input
          :id="`tz-prefix-${ty}`"
          v-model="prefixes[ty]"
          :class="INPUT"
          maxlength="8"
        />
      </div>
    </div>
    <button type="button" :class="BTN" @click="savePrefixes">
      {{ t('TOLZAR_SETTINGS_UI.DOCS.SAVE_PREFIXES') }}
    </button>
  </div>
</template>
