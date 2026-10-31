<script setup>
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import {
  emptyLine,
  linesTotal,
  toSpec,
  showsField,
  isPlaceholder,
  nextStep,
} from './settings/tolzarDocuments';

// Conversation sidebar → this contact's booking documents (Tolzar::Document), and a draft made here, in the
// conversation: lines from the workspace's industry pack, placeholders in amber, then Issue and a person's Send
// (the PDF into this conversation). Nothing is sent without that click. Hidden when documents are off (404).
const props = defineProps({
  contactId: { type: [Number, String], default: null },
  conversationId: { type: [Number, String], default: null },
});
const { t } = useI18n();
const accountId = useMapGetter('getCurrentAccountId');
const base = computed(() => `/api/v1/accounts/${accountId.value}/tolzar`);
const enabled = ref(false);
const docs = ref([]);
const lineTypes = ref(null);
const editing = ref(null);
const busy = ref(false);
const notice = ref('');
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

const say = (e, fallback) =>
  e?.response?.data?.error ||
  (e?.response?.data?.errors || []).join(' ') ||
  fallback;

async function load() {
  docs.value = [];
  if (!props.contactId) return;
  try {
    const { data } = await window.axios.get(`${base.value}/documents`, {
      params: { contact_id: props.contactId },
    });
    enabled.value = true;
    docs.value = (data.documents || []).slice(0, 10);
  } catch {
    enabled.value = false;
  }
}

async function loadPacks() {
  if (lineTypes.value) return;
  try {
    const { data } = await window.axios.get(`${base.value}/documents_settings`);
    lineTypes.value = data.line_types || null;
  } catch {
    lineTypes.value = null;
  }
}

function startDraft() {
  notice.value = '';
  editing.value = {
    doc_type: 'quote',
    currency: 'USD',
    guests: '',
    lines: [emptyLine()],
    notes: '',
  };
  loadPacks();
}

const total = computed(() =>
  editing.value ? (linesTotal(editing.value.lines) / 100).toFixed(2) : ''
);
const hasPlaceholder = computed(
  () =>
    !!editing.value &&
    editing.value.lines.some(
      l => isPlaceholder(l.unit_price) || isPlaceholder(l.description)
    )
);

async function saveDraft() {
  busy.value = true;
  notice.value = '';
  try {
    await window.axios.post(`${base.value}/documents`, {
      doc_type: editing.value.doc_type,
      currency: editing.value.currency,
      conversation_id: props.conversationId,
      spec: toSpec(editing.value),
    });
    editing.value = null;
    notice.value = t('TOLZAR_SETTINGS_UI.DOCS.SAVED');
    await load();
  } catch (e) {
    notice.value = say(e, t('TOLZAR_SETTINGS_UI.DOCS.FAILED'));
  } finally {
    busy.value = false;
  }
}

async function act(doc, step) {
  busy.value = true;
  notice.value = '';
  try {
    await window.axios.post(`${base.value}/documents/${doc.id}/${step}`);
    notice.value = t('TOLZAR_SETTINGS_UI.DOCS.SAVED');
    await load();
  } catch (e) {
    notice.value = say(e, t('TOLZAR_SETTINGS_UI.DOCS.FAILED'));
  } finally {
    busy.value = false;
  }
}

const label = d => d.number || t('TOLZAR_SETTINGS_UI.DOCS.NO_NUMBER');
const amber = v => (isPlaceholder(v) ? '!bg-n-amber-3 !outline-n-amber-8' : '');
const FIELD =
  'w-full mb-1 px-2 py-1 text-xs rounded-md border border-solid border-n-weak bg-n-solid-1 text-n-slate-12';
const SMALL_BTN =
  'px-2 py-1 text-xs rounded-md border border-solid border-n-weak bg-n-solid-2 text-n-slate-12 disabled:opacity-50';

watch(() => props.contactId, load, { immediate: true });
</script>

<template>
  <section
    v-if="enabled"
    class="mt-3 p-3 rounded-xl border border-solid border-n-weak bg-n-solid-1"
  >
    <div class="flex items-center justify-between mb-2">
      <h3 class="m-0 text-xs font-semibold text-n-slate-11 uppercase">
        {{ t('TOLZAR_SETTINGS_UI.DOCS.CARD_TITLE') }}
      </h3>
      <button
        v-if="!editing && conversationId"
        type="button"
        :class="SMALL_BTN"
        @click="startDraft"
      >
        {{ t('TOLZAR_SETTINGS_UI.DOCS.NEW') }}
      </button>
    </div>
    <p v-if="notice" class="m-0 mb-2 text-xs text-n-slate-12" role="status">
      {{ notice }}
    </p>

    <form v-if="editing" class="mb-3" @submit.prevent="saveDraft">
      <label class="text-xs text-n-slate-11" for="tz-dc-type">{{
        t('TOLZAR_SETTINGS_UI.DOCS.TYPE')
      }}</label>
      <select id="tz-dc-type" v-model="editing.doc_type" :class="FIELD">
        <option v-for="ty in TYPES" :key="ty" :value="ty">
          {{ t(`TOLZAR_SETTINGS_UI.DOCS.T_${ty}`) }}
        </option>
      </select>
      <label class="text-xs text-n-slate-11" for="tz-dc-guests">{{
        t('TOLZAR_SETTINGS_UI.DOCS.GUESTS')
      }}</label>
      <input id="tz-dc-guests" v-model="editing.guests" :class="FIELD" />
      <p class="m-0 mb-1 text-[11px] text-n-slate-10">
        {{ t('TOLZAR_SETTINGS_UI.DOCS.NO_ID') }}
      </p>
      <fieldset
        v-for="(line, i) in editing.lines"
        :key="line.key"
        class="p-2 mb-2 rounded-lg border border-solid border-n-weak"
      >
        <legend class="px-1 text-[11px] text-n-slate-11">
          {{ t('TOLZAR_SETTINGS_UI.DOCS.LINES') }} {{ i + 1 }}
        </legend>
        <select
          v-model="line.type"
          :class="FIELD"
          :aria-label="t('TOLZAR_SETTINGS_UI.DOCS.LINE_TYPE')"
        >
          <option v-for="lt in LINE_TYPES" :key="lt" :value="lt">
            {{ t(`TOLZAR_SETTINGS_UI.DOCS.L_${lt}`) }}
          </option>
        </select>
        <input
          v-model="line.description"
          :class="[FIELD, amber(line.description)]"
          :aria-label="t('TOLZAR_SETTINGS_UI.DOCS.DESCRIPTION')"
          :placeholder="t('TOLZAR_SETTINGS_UI.DOCS.DESCRIPTION')"
        />
        <input
          v-if="showsField(lineTypes, line.type, 'date')"
          v-model="line.date"
          type="date"
          :class="FIELD"
          :aria-label="t('TOLZAR_SETTINGS_UI.DOCS.DATE')"
        />
        <div class="flex gap-1">
          <input
            v-if="
              showsField(lineTypes, line.type, 'qty') ||
              showsField(lineTypes, line.type, 'nights') ||
              showsField(lineTypes, line.type, 'guests')
            "
            v-model="line.qty"
            :class="FIELD"
            inputmode="decimal"
            :aria-label="t('TOLZAR_SETTINGS_UI.DOCS.QTY')"
            :placeholder="t('TOLZAR_SETTINGS_UI.DOCS.QTY')"
          />
          <input
            v-model="line.unit_price"
            :class="[FIELD, amber(line.unit_price)]"
            inputmode="decimal"
            :aria-label="t('TOLZAR_SETTINGS_UI.DOCS.PRICE')"
            :placeholder="t('TOLZAR_SETTINGS_UI.DOCS.PRICE')"
          />
        </div>
        <button
          v-if="editing.lines.length > 1"
          type="button"
          class="p-0 text-[11px] text-n-ruby-11 bg-transparent"
          @click="editing.lines.splice(i, 1)"
        >
          {{ t('TOLZAR_SETTINGS_UI.DOCS.REMOVE_LINE') }}
        </button>
      </fieldset>
      <button
        type="button"
        :class="SMALL_BTN"
        @click="editing.lines.push(emptyLine())"
      >
        {{ t('TOLZAR_SETTINGS_UI.DOCS.ADD_LINE') }}
      </button>
      <p class="my-2 text-xs font-semibold text-n-slate-12">
        {{ t('TOLZAR_SETTINGS_UI.DOCS.TOTAL', { total }) }}
      </p>
      <p v-if="hasPlaceholder" class="m-0 mb-2 text-[11px] text-n-amber-11">
        {{ t('TOLZAR_SETTINGS_UI.DOCS.PLACEHOLDER_HINT') }}
      </p>
      <div class="flex gap-2">
        <button type="submit" :class="SMALL_BTN" :disabled="busy">
          {{ t('TOLZAR_SETTINGS_UI.DOCS.SAVE_DRAFT') }}
        </button>
        <button type="button" :class="SMALL_BTN" @click="editing = null">
          {{ t('TOLZAR_SETTINGS_UI.DOCS.CANCEL') }}
        </button>
      </div>
    </form>

    <p v-if="!docs.length && !editing" class="m-0 text-xs text-n-slate-11">
      {{ t('TOLZAR_SETTINGS_UI.DOCS.EMPTY') }}
    </p>
    <ul class="m-0 p-0 list-none flex flex-col gap-1.5">
      <li v-for="d in docs" :key="d.id" class="flex flex-col gap-1 text-xs">
        <div class="flex justify-between gap-2">
          <span class="font-mono text-n-slate-12">{{ label(d) }}</span>
          <span class="text-n-slate-11">{{
            t(`TOLZAR_SETTINGS_UI.DOCS.T_${d.doc_type}`)
          }}</span>
          <span class="text-n-slate-11">{{
            t(`TOLZAR_SETTINGS_UI.DOCS.ST_${d.status}`)
          }}</span>
        </div>
        <p
          v-if="nextStep(d) === 'fill'"
          class="m-0 text-[11px] text-n-amber-11"
        >
          {{ t('TOLZAR_SETTINGS_UI.DOCS.HAS_PLACEHOLDERS') }}
        </p>
        <button
          v-else-if="nextStep(d) === 'issue'"
          type="button"
          :class="SMALL_BTN"
          class="self-start"
          :disabled="busy"
          @click="act(d, 'issue')"
        >
          {{ t('TOLZAR_SETTINGS_UI.DOCS.ISSUE') }}
        </button>
        <button
          v-else-if="nextStep(d) === 'send' && d.conversation_id"
          type="button"
          :class="SMALL_BTN"
          class="self-start"
          :disabled="busy"
          @click="act(d, 'send')"
        >
          {{ t('TOLZAR_SETTINGS_UI.DOCS.SEND') }}
        </button>
      </li>
    </ul>
  </section>
</template>
