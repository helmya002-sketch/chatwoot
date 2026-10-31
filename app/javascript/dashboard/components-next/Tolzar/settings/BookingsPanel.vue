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

// Settings hub → Workspace → Bookings (Tolzar::Booking): today and the next 14 days, the list, a booking editor,
// status moves, the payments record (Tolzar never charges) and a draft voucher from a booking.
const { t } = useI18n();
const accountId = useMapGetter('getCurrentAccountId');
const base = computed(
  () => `/api/v1/accounts/${accountId.value}/tolzar/bookings`
);
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
const STATUSES = ['draft', 'confirmed', 'completed', 'cancelled'];
const NEXT = {
  draft: ['confirmed', 'cancelled'],
  confirmed: ['completed', 'cancelled'],
  completed: [],
  cancelled: [],
};

const view = ref('agenda');
const days = ref([]);
const balancesDue = ref([]);
const rows = ref([]);
const statusFilter = ref('');
const editing = ref(null);
const notice = ref('');
const error = ref('');
const payment = ref({});

const money = c => (Number(c || 0) / 100).toFixed(2);
// Per currency, never added across currencies: "EUR 120.00 · USD 40.00".
const dueText = list =>
  list.length
    ? list.map(d => `${d.currency} ${money(d.cents)}`).join(' · ')
    : money(0);
const tone = s =>
  ({ confirmed: TONE_OK, draft: TONE_WARN, cancelled: TONE_BAD })[s] ||
  TONE_MUTED;
const say = (e, fallback) =>
  e?.response?.data?.error ||
  (e?.response?.data?.errors || []).join(' ') ||
  fallback;

async function loadAgenda() {
  error.value = '';
  try {
    const { data } = await window.axios.get(`${base.value}/agenda`);
    days.value = (data.days || []).filter(d => d.bookings.length);
    balancesDue.value = data.balances_due_by_currency || [];
  } catch (e) {
    error.value =
      e?.response?.status === 404
        ? t('TOLZAR_SETTINGS_UI.BOOKINGS.OFF')
        : t('TOLZAR_SETTINGS_UI.DOCS.FAILED');
  }
}

async function loadList() {
  error.value = '';
  try {
    const { data } = await window.axios.get(base.value, {
      params: { status: statusFilter.value || undefined },
    });
    rows.value = data.bookings || [];
  } catch (e) {
    error.value =
      e?.response?.status === 404
        ? t('TOLZAR_SETTINGS_UI.BOOKINGS.OFF')
        : t('TOLZAR_SETTINGS_UI.DOCS.FAILED');
  }
}

function open(which) {
  view.value = which;
  notice.value = '';
  if (which === 'agenda') loadAgenda();
  if (which === 'list') loadList();
  if (which === 'new')
    editing.value = {
      currency: 'USD',
      conversation_id: '',
      guests: '',
      lines: [{ ...emptyLine(), until: '' }],
      notes: '',
    };
}

async function save() {
  const d = editing.value;
  const spec = toSpec(d);
  spec.lines = spec.lines.map((l, i) =>
    d.lines[i]?.until ? { ...l, until: d.lines[i].until } : l
  );
  try {
    await window.axios.post(base.value, {
      currency: d.currency,
      conversation_id: d.conversation_id || undefined,
      data: spec,
    });
    notice.value = t('TOLZAR_SETTINGS_UI.DOCS.SAVED');
    editing.value = null;
    open('list');
  } catch (e) {
    notice.value = say(e, t('TOLZAR_SETTINGS_UI.DOCS.FAILED'));
  }
}

async function post(row, path, body = {}) {
  notice.value = '';
  try {
    await window.axios.post(`${base.value}/${row.id}/${path}`, body);
    notice.value = t('TOLZAR_SETTINGS_UI.DOCS.SAVED');
    loadList();
  } catch (e) {
    notice.value = say(e, t('TOLZAR_SETTINGS_UI.DOCS.FAILED'));
  }
}

const summary = row =>
  `${row.contact_name || '–'} · ${row.starts_on || t('TOLZAR_SETTINGS_UI.BOOKINGS.NO_DATE')}`;
const amountOf = row => `${row.currency} ${money(row.total_cents)}`;
const draftTotal = computed(() =>
  editing.value ? linesTotal(editing.value.lines) : 0
);

onMounted(() => open('agenda'));
</script>

<template>
  <div class="max-w-[900px]">
    <p class="mt-0 text-[13px] text-n-slate-11">
      {{ t('TOLZAR_SETTINGS_UI.BOOKINGS.WHAT') }}
    </p>
    <div class="flex gap-2" role="tablist">
      <button
        v-for="v in ['agenda', 'list', 'new']"
        :key="v"
        type="button"
        role="tab"
        :aria-selected="view === v"
        :class="view === v ? BTN : BTN_GHOST"
        @click="open(v)"
      >
        {{ t(`TOLZAR_SETTINGS_UI.BOOKINGS.TAB_${v}`) }}
      </button>
    </div>
    <p v-if="notice" class="text-[13px] text-n-slate-12" role="status">
      {{ notice }}
    </p>
    <p v-if="error" class="mt-3 text-[13px] text-n-ruby-11" role="alert">
      {{ error }}
    </p>

    <section v-if="view === 'agenda' && !error" class="mt-3">
      <p class="m-0 text-[13px] text-n-slate-12">
        {{
          t('TOLZAR_SETTINGS_UI.BOOKINGS.BALANCES', {
            amount: dueText(balancesDue),
          })
        }}
      </p>
      <p v-if="!days.length" class="text-[13px] text-n-slate-11">
        {{ t('TOLZAR_SETTINGS_UI.BOOKINGS.EMPTY_AGENDA') }}
      </p>
      <div v-for="d in days" :key="d.date" class="mt-3">
        <h3 class="m-0 text-sm font-semibold text-n-slate-12">{{ d.date }}</h3>
        <ul class="m-0 mt-1 p-0 list-none">
          <li
            v-for="b in d.bookings"
            :key="b.id"
            class="flex gap-3 text-[13px] py-1 border-b border-n-weak"
          >
            <span class="font-mono text-n-slate-11">#{{ b.id }}</span>
            <span class="flex-1 text-n-slate-12">{{
              b.contact_name || '–'
            }}</span>
            <span class="px-1.5 rounded text-xs" :class="tone(b.status)">{{
              t(`TOLZAR_SETTINGS_UI.BOOKINGS.ST_${b.status}`)
            }}</span>
            <span v-if="b.balance_cents" class="tabular-nums text-n-amber-11">
              {{
                t('TOLZAR_SETTINGS_UI.BOOKINGS.DUE', {
                  amount: `${b.currency} ${money(b.balance_cents)}`,
                })
              }}
            </span>
          </li>
        </ul>
      </div>
    </section>

    <section v-if="view === 'list' && !error" class="mt-3">
      <label :class="LABEL" for="tz-bk-status">{{
        t('TOLZAR_SETTINGS_UI.DOCS.STATUS')
      }}</label>
      <select
        id="tz-bk-status"
        v-model="statusFilter"
        :class="INPUT"
        class="!w-48"
        @change="loadList"
      >
        <option value="">{{ t('TOLZAR_SETTINGS_UI.DOCS.ALL') }}</option>
        <option v-for="s in STATUSES" :key="s" :value="s">
          {{ t(`TOLZAR_SETTINGS_UI.BOOKINGS.ST_${s}`) }}
        </option>
      </select>
      <p v-if="!rows.length" class="text-[13px] text-n-slate-11">
        {{ t('TOLZAR_SETTINGS_UI.BOOKINGS.EMPTY') }}
      </p>
      <div
        v-for="row in rows"
        :key="row.id"
        class="mt-3 p-3 rounded-xl border border-solid border-n-weak"
      >
        <div class="flex flex-wrap gap-3 items-center text-[13px]">
          <span class="font-mono text-n-slate-11">#{{ row.id }}</span>
          <span class="flex-1 text-n-slate-12">{{ summary(row) }}</span>
          <span class="px-1.5 rounded text-xs" :class="tone(row.status)">{{
            t(`TOLZAR_SETTINGS_UI.BOOKINGS.ST_${row.status}`)
          }}</span>
          <span class="tabular-nums">{{ amountOf(row) }}</span>
          <span v-if="row.balance_cents" class="tabular-nums text-n-amber-11">
            {{
              t('TOLZAR_SETTINGS_UI.BOOKINGS.DUE', {
                amount: money(row.balance_cents),
              })
            }}
          </span>
        </div>
        <div class="flex flex-wrap gap-2 items-center mt-2">
          <button
            v-for="to in NEXT[row.status]"
            :key="to"
            type="button"
            :class="to === 'cancelled' ? BTN_GHOST : BTN"
            class="!mt-0"
            @click="post(row, 'status', { to })"
          >
            {{ t(`TOLZAR_SETTINGS_UI.BOOKINGS.TO_${to}`) }}
          </button>
          <template v-if="row.status !== 'cancelled'">
            <input
              v-model="payment[row.id]"
              :class="INPUT"
              class="!w-28"
              inputmode="decimal"
              :aria-label="t('TOLZAR_SETTINGS_UI.BOOKINGS.PAYMENT')"
              :placeholder="t('TOLZAR_SETTINGS_UI.BOOKINGS.PAYMENT')"
            />
            <button
              type="button"
              :class="BTN_GHOST"
              class="!mt-0"
              :disabled="!payment[row.id]"
              @click="post(row, 'payment', { amount: payment[row.id] })"
            >
              {{ t('TOLZAR_SETTINGS_UI.BOOKINGS.RECORD_PAYMENT') }}
            </button>
          </template>
          <button
            type="button"
            :class="BTN_GHOST"
            class="!mt-0"
            @click="post(row, 'document', { doc_type: 'voucher' })"
          >
            {{ t('TOLZAR_SETTINGS_UI.BOOKINGS.MAKE_VOUCHER') }}
          </button>
        </div>
      </div>
    </section>

    <section
      v-if="view === 'new' && editing"
      class="mt-3 p-4 rounded-xl border border-solid border-n-weak"
    >
      <div class="grid grid-cols-2 gap-3">
        <div>
          <label :class="LABEL" for="tz-bk-conv">{{
            t('TOLZAR_SETTINGS_UI.DOCS.CONVERSATION')
          }}</label>
          <input
            id="tz-bk-conv"
            v-model="editing.conversation_id"
            :class="INPUT"
            inputmode="numeric"
          />
        </div>
        <div>
          <label :class="LABEL" for="tz-bk-cur">{{
            t('TOLZAR_SETTINGS_UI.DOCS.CURRENCY')
          }}</label>
          <input
            id="tz-bk-cur"
            v-model="editing.currency"
            :class="INPUT"
            maxlength="3"
          />
        </div>
      </div>
      <label :class="LABEL" for="tz-bk-guests">{{
        t('TOLZAR_SETTINGS_UI.DOCS.GUESTS')
      }}</label>
      <input id="tz-bk-guests" v-model="editing.guests" :class="INPUT" />
      <p class="mt-1 mb-0 text-xs text-n-slate-10">
        {{ t('TOLZAR_SETTINGS_UI.DOCS.NO_ID') }}
      </p>
      <h3 class="mt-4 mb-1 text-sm font-semibold text-n-slate-12">
        {{ t('TOLZAR_SETTINGS_UI.DOCS.LINES') }}
      </h3>
      <div
        v-for="(line, i) in editing.lines"
        :key="line.key"
        class="grid grid-cols-[8rem_1fr_7rem_7rem_4rem_6rem_auto] gap-2 items-center mt-2"
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
          :aria-label="t('TOLZAR_SETTINGS_UI.BOOKINGS.FROM')"
        />
        <input
          v-model="line.until"
          :class="INPUT"
          type="date"
          :aria-label="t('TOLZAR_SETTINGS_UI.BOOKINGS.UNTIL')"
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
        @click="editing.lines.push({ ...emptyLine(), until: '' })"
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
      <label :class="LABEL" for="tz-bk-notes">{{
        t('TOLZAR_SETTINGS_UI.DOCS.NOTES')
      }}</label>
      <textarea
        id="tz-bk-notes"
        v-model="editing.notes"
        :class="INPUT"
        rows="2"
      />
      <button type="button" :class="BTN" @click="save">
        {{ t('TOLZAR_SETTINGS_UI.BOOKINGS.SAVE') }}
      </button>
    </section>
  </div>
</template>
