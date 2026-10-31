<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { BTN, BTN_GHOST, BTN_DANGER, INPUT, LABEL, CHECK } from './tzClasses';
import {
  MAX_MEMBERS,
  getBillingGroup,
  saveBillingGroup,
  deleteBillingGroup,
  poolMeter,
  countingSince,
  billingErrorKey,
} from '../tolzarBilling';

// Settings hub → Plan and usage: the Business plan's shared AI-reply allowance (a billing group of up
// to 5 workspaces). Every administrator sees the pooled meter and each member's own limits
// (read-only); only an Owner of every member workspace changes the group (Rails checks it again).
const { t } = useI18n();
const accountId = useMapGetter('getCurrentAccountId');

const status = ref(null);
const form = ref({
  members: [],
  monthly_ai_replies: '',
  tz: 'UTC',
  enabled: false,
});
const error = ref('');
const saved = ref('');
const busy = ref(false);
const DEFAULT_TZ = 'UTC';
const confirmDelete = ref(false);

const group = computed(() => status.value?.group || null);
const meter = computed(() => poolMeter(status.value));
const since = computed(() => countingSince(status.value));
const canManage = computed(() => !!status.value?.can_manage);
const max = computed(() => status.value?.max_members || MAX_MEMBERS);
// The workspaces the Owner may tick: the current members and their own workspaces in no other group.
const choices = computed(() => {
  const rows = (status.value?.members || []).map(m => ({
    id: m.id,
    name: m.name,
  }));
  (status.value?.candidates || []).forEach(c => {
    if (!rows.some(r => r.id === c.id)) rows.push(c);
  });
  return rows;
});
const fmt = v =>
  v === null || v === undefined ? '∞' : Number(v).toLocaleString();
const nameOf = m =>
  m.name || t('TOLZAR_SETTINGS.BILLING.WORKSPACE_ID', { id: m.id });
const capsText = caps =>
  caps
    ? t('TOLZAR_SETTINGS.BILLING.CAPS_VALUE', {
        calls: caps.daily_calls ?? t('TOLZAR_SETTINGS.BILLING.NO_CAP'),
        tokens: caps.monthly_tokens ?? t('TOLZAR_SETTINGS.BILLING.NO_CAP'),
      })
    : t('TOLZAR_SETTINGS.BILLING.CAPS_HIDDEN');

function apply(s) {
  status.value = s;
  const g = s?.group;
  form.value = {
    members: g ? [...g.members] : [Number(accountId.value)],
    monthly_ai_replies: g?.monthly_ai_replies ?? '',
    tz: g?.tz || 'UTC',
    enabled: !!g?.enabled,
  };
  confirmDelete.value = false;
}
function report(r, okText) {
  const key = billingErrorKey(r);
  error.value = key ? t(`TOLZAR_SETTINGS.BILLING.ERRORS.${key}`) : '';
  saved.value = key ? '' : okText;
  return !key;
}
async function load() {
  const r = await getBillingGroup(accountId.value);
  if (report(r, '')) apply(r);
}
const ticked = id => form.value.members.includes(id);
function toggle(id) {
  const list = form.value.members;
  form.value.members = ticked(id) ? list.filter(x => x !== id) : [...list, id];
}
async function save() {
  busy.value = true;
  try {
    const r = await saveBillingGroup(accountId.value, form.value);
    if (report(r, t('TOLZAR_SETTINGS.BILLING.SAVED'))) apply(r);
  } finally {
    busy.value = false;
  }
}
async function remove() {
  if (!confirmDelete.value) {
    confirmDelete.value = true;
    return;
  }
  busy.value = true;
  try {
    const r = await deleteBillingGroup(accountId.value);
    if (report(r, t('TOLZAR_SETTINGS.BILLING.DELETED'))) apply(r);
  } finally {
    busy.value = false;
  }
}

onMounted(load);
</script>

<template>
  <div>
    <p class="mt-0 text-[13px] text-n-slate-11">
      {{ t('TOLZAR_SETTINGS.BILLING.WHAT_COUNTS') }}
    </p>
    <div
      v-if="error"
      class="p-2 mt-3 text-[13px] rounded-lg text-n-ruby-11 bg-n-ruby-9/10"
      role="alert"
    >
      {{ error }}
    </div>
    <p
      v-else-if="saved"
      class="p-2 mt-3 text-[13px] rounded-lg text-n-brand bg-n-brand/10"
    >
      {{ saved }}
    </p>

    <template v-if="status">
      <p
        v-if="!status.switch_on"
        class="p-2 mt-3 text-[13px] rounded-lg text-amber-700 bg-amber-500/10"
      >
        {{ t('TOLZAR_SETTINGS.BILLING.SWITCH_OFF') }}
      </p>
      <p v-if="!group" class="mt-3 text-[13px] text-n-slate-10">
        {{ t('TOLZAR_SETTINGS.BILLING.NO_GROUP') }}
      </p>

      <div
        v-if="group"
        class="p-3 mt-3 rounded-lg border border-solid border-n-weak"
      >
        <div class="flex flex-wrap gap-2 justify-between items-baseline">
          <div class="text-xs text-n-slate-10">
            {{ t('TOLZAR_SETTINGS.BILLING.POOL_TITLE') }} ·
            {{ t('TOLZAR_SETTINGS.BILLING.PLAN', { plan: group.plan }) }}
          </div>
          <div class="text-xs text-n-slate-10">
            {{
              since
                ? t('TOLZAR_SETTINGS.BILLING.COUNTING_SINCE', { date: since })
                : t('TOLZAR_SETTINGS.BILLING.NOT_COUNTING')
            }}
          </div>
        </div>
        <div class="mt-1 text-xl font-bold text-n-slate-12">
          {{ fmt(meter.used) }}
          <span class="text-sm font-normal text-n-slate-10">
            {{ `/ ${fmt(meter.limit)}` }}
          </span>
        </div>
        <div class="overflow-hidden mt-2 h-1.5 rounded bg-n-alpha-2">
          <div
            v-if="meter.share !== null"
            class="h-full"
            :class="meter.reached ? 'bg-n-ruby-9' : 'bg-n-brand'"
            :style="{ width: `${Math.round(meter.share * 100)}%` }"
          />
        </div>
        <div
          class="mt-1 text-xs"
          :class="meter.reached ? 'text-n-ruby-11' : 'text-n-slate-11'"
        >
          {{
            meter.limit === null
              ? t('TOLZAR_SETTINGS.BILLING.UNLIMITED')
              : meter.reached
                ? t('TOLZAR_SETTINGS.BILLING.REACHED')
                : t('TOLZAR_SETTINGS.BILLING.REMAINING', {
                    n: fmt(meter.remaining),
                  })
          }}
        </div>
        <div class="mt-1 text-xs text-n-slate-10">
          {{
            t('TOLZAR_SETTINGS.BILLING.PERIOD', {
              month: status.period?.month || '',
              tz: status.period?.timezone || group.tz,
            })
          }}
          ·
          {{
            group.enabled
              ? t('TOLZAR_SETTINGS.BILLING.ENABLED')
              : t('TOLZAR_SETTINGS.BILLING.PAUSED')
          }}
        </div>

        <h3 class="mt-4 mb-1 text-sm font-semibold text-n-slate-12">
          {{ t('TOLZAR_SETTINGS.BILLING.MEMBERS') }}
        </h3>
        <table class="w-full text-[13px]">
          <thead>
            <tr class="text-xs text-start text-n-slate-10">
              <th class="py-1 font-medium">
                {{ t('TOLZAR_SETTINGS.BILLING.WORKSPACE') }}
              </th>
              <th class="py-1 font-medium">
                {{ t('TOLZAR_SETTINGS.BILLING.USED') }}
              </th>
              <th class="py-1 font-medium">
                {{ t('TOLZAR_SETTINGS.BILLING.CAPS') }}
              </th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="m in status.members"
              :key="m.id"
              class="border-t border-solid border-n-weak"
            >
              <td class="py-1.5 text-n-slate-12">
                {{ nameOf(m) }}
                <span v-if="m.current" class="ms-1 text-xs text-n-slate-10">
                  {{ `(${t('TOLZAR_SETTINGS.BILLING.THIS_WORKSPACE')})` }}
                </span>
              </td>
              <td class="py-1.5 text-n-slate-12">{{ fmt(m.used) }}</td>
              <td class="py-1.5 text-n-slate-11">{{ capsText(m.caps) }}</td>
            </tr>
          </tbody>
        </table>
      </div>

      <p v-if="!canManage" class="mt-3 text-xs text-n-slate-10">
        {{ t('TOLZAR_SETTINGS.BILLING.READ_ONLY') }}
      </p>

      <div v-if="canManage" class="mt-4">
        <h3 class="m-0 text-sm font-semibold text-n-slate-12">
          {{ t('TOLZAR_SETTINGS.BILLING.MANAGE') }}
        </h3>
        <label :class="LABEL">{{
          t('TOLZAR_SETTINGS.BILLING.CHOOSE', { n: max })
        }}</label>
        <label v-for="c in choices" :key="c.id" :class="CHECK">
          <input
            type="checkbox"
            :checked="ticked(c.id)"
            :disabled="!ticked(c.id) && form.members.length >= max"
            @change="toggle(c.id)"
          />
          {{ nameOf(c) }}
        </label>
        <label :class="LABEL">{{
          t('TOLZAR_SETTINGS.BILLING.ALLOWANCE')
        }}</label>
        <input
          v-model="form.monthly_ai_replies"
          type="number"
          min="1"
          :class="INPUT"
          :placeholder="t('TOLZAR_SETTINGS.BILLING.EMPTY_UNLIMITED')"
        />
        <label :class="LABEL">{{ t('TOLZAR_SETTINGS.BILLING.TZ') }}</label>
        <input
          v-model="form.tz"
          type="text"
          :class="INPUT"
          :placeholder="DEFAULT_TZ"
        />
        <label :class="CHECK">
          <input v-model="form.enabled" type="checkbox" />
          <span>{{ t('TOLZAR_SETTINGS.BILLING.ENABLE') }}</span>
        </label>
        <div class="flex flex-wrap gap-2">
          <button
            type="button"
            :class="BTN"
            :disabled="busy || !form.members.length"
            @click="save"
          >
            {{
              group
                ? t('TOLZAR_SETTINGS.BILLING.SAVE')
                : t('TOLZAR_SETTINGS.BILLING.CREATE')
            }}
          </button>
          <button
            v-if="group"
            type="button"
            :class="confirmDelete ? BTN_DANGER : BTN_GHOST"
            :disabled="busy"
            @click="remove"
          >
            {{
              confirmDelete
                ? t('TOLZAR_SETTINGS.BILLING.CONFIRM_DELETE')
                : t('TOLZAR_SETTINGS.BILLING.DELETE')
            }}
          </button>
        </div>
      </div>
    </template>
  </div>
</template>
