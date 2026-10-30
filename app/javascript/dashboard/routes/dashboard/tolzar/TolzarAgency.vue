<script setup>
import { ref, computed, onMounted, onBeforeUnmount } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';
import { useLocale } from 'shared/composables/useLocale';
import BrainNotice from 'dashboard/components-next/Tolzar/settings/BrainNotice.vue';
import {
  BTN,
  INPUT,
  LABEL,
  TONE_BAD,
  TONE_OK,
  TONE_WARN,
} from 'dashboard/components-next/Tolzar/settings/tzClasses';

// Agency console (R11, approved mock agency-white-label-v1): every workspace this person
// administers, with usage and AI quality side by side, and per-workspace branding. Each client
// still sees only its own workspace (Chatwoot accounts stay separate).
const currentUser = useMapGetter('getCurrentUser');
const workspaces = computed(() =>
  (currentUser.value?.accounts || []).filter(a => a.role === 'administrator')
);
const rows = ref({});
const editing = ref(null);
const brand = ref({});
const busy = ref(false);
const saved = ref('');
const result = ref(null); // the proxy's refusal or the brain's errors, for BrainNotice

const { t } = useI18n();
const { resolvedLocale } = useLocale();
const tz = id => `/api/v1/accounts/${id}/tolzar`;
const number = n => {
  try {
    return new Intl.NumberFormat(resolvedLocale.value).format(Number(n) || 0);
  } catch (e) {
    return String(n);
  }
};

// Two reads per workspace (usage, scoreboard). A failed one marks the row instead of showing
// zeros as if they were real; a pooled agency overview on the proxy would make this one call.
async function loadRow(a) {
  const [u, s] = await Promise.allSettled([
    window.axios
      .get(`${tz(a.id)}/brain/usage`, { params: { days: 30 } })
      .then(r => r.data),
    window.axios
      .get(`${tz(a.id)}/scoreboard`, { params: { days: 30 } })
      .then(r => r.data),
  ]);
  const usage =
    u.status === 'fulfilled' && u.value && u.value.ok !== false
      ? u.value
      : null;
  const board =
    s.status === 'fulfilled' && s.value && s.value.ok !== false
      ? s.value
      : null;
  const agreement = (board?.checks || []).find(c => c.key === 'agreement');
  rows.value[a.id] = {
    error: !usage || !board,
    conversations: usage ? (usage.total?.conversations ?? 0) : null,
    tokens: usage
      ? (usage.total?.input_tokens ?? 0) + (usage.total?.output_tokens ?? 0)
      : null,
    agreement:
      agreement && agreement.value != null
        ? Math.round(agreement.value * 100)
        : null,
  };
}

async function openBrand(a) {
  editing.value = a;
  saved.value = '';
  result.value = null;
  const r = await window.axios
    .get(`${tz(a.id)}/brain/branding`)
    .then(x => x.data)
    .catch(e => e?.response?.data || { ok: false, error: 'brain_unreachable' });
  if (r && r.ok === false) result.value = r;
  // No colour from the brain: the input shows its own default and the preview keeps the theme's
  // brand utilities, so no hex lives here.
  brand.value = {
    product_name: '',
    color: '',
    logo_url: '',
    support_email: '',
    ...(r?.branding || {}),
  };
}

let savedTimer = null;
async function saveBrand() {
  if (busy.value || !editing.value) return;
  busy.value = true;
  saved.value = '';
  result.value = null;
  try {
    const r = await window.axios
      .post(`${tz(editing.value.id)}/brain/branding`, brand.value)
      .then(x => x.data)
      .catch(
        e => e?.response?.data || { ok: false, error: 'brain_unreachable' }
      );
    if (r.ok === false || r.detail !== undefined) {
      result.value = r;
      return;
    }
    brand.value = { ...brand.value, ...(r.branding || {}) };
    saved.value = t('TOLZAR_AGENCY_UI.SAVED');
    clearTimeout(savedTimer);
    savedTimer = setTimeout(() => {
      saved.value = '';
    }, 4000);
  } finally {
    busy.value = false;
  }
}

// WCAG relative luminance of the brand colour; white text needs a contrast of 4.5:1, which is
// luminance <= 0.1833 ((1.05 / 4.5) - 0.05). No dependency: the input is always #rrggbb.
const luminance = hex => {
  const m = /^#?([0-9a-f]{6})$/i.exec(String(hex || '').trim());
  if (!m) return null;
  const chan = i => {
    const c = parseInt(m[1].slice(i, i + 2), 16) / 255;
    return c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4;
  };
  return 0.2126 * chan(0) + 0.7152 * chan(2) + 0.0722 * chan(4);
};
const whiteContrast = computed(() => {
  const l = luminance(brand.value.color);
  return l === null ? null : 1.05 / (l + 0.05);
});
const lowContrast = computed(
  () => whiteContrast.value !== null && whiteContrast.value < 4.5
);

onMounted(() => workspaces.value.forEach(loadRow));
onBeforeUnmount(() => clearTimeout(savedTimer));
</script>

<template>
  <div class="overflow-auto flex-1 bg-n-background" data-tz-build="agency-2">
    <div class="mx-auto max-w-[1100px] px-5 pb-16 pt-7">
      <h1 class="m-0 text-[22px] font-extrabold tracking-tight text-n-slate-12">
        {{ t('TOLZAR_AGENCY.TITLE') }}
      </h1>
      <p class="mt-1 text-sm text-n-slate-11">{{ t('TOLZAR_AGENCY.LEAD') }}</p>

      <div
        class="overflow-hidden mt-5 rounded-xl border bg-n-solid-1 border-n-weak"
      >
        <table class="w-full text-[13.5px]">
          <thead>
            <tr class="text-xs text-start text-n-slate-10">
              <th class="px-4 py-2.5 text-start">
                {{ t('TOLZAR_AGENCY.WORKSPACE') }}
              </th>
              <th class="text-start">{{ t('TOLZAR_AGENCY.CONVERSATIONS') }}</th>
              <th class="text-start">{{ t('TOLZAR_AGENCY.AGREEMENT') }}</th>
              <th class="text-start">{{ t('TOLZAR_AGENCY.TOKENS') }}</th>
              <th />
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="a in workspaces"
              :key="a.id"
              class="border-t border-n-weak"
            >
              <td class="px-4 py-2.5 font-semibold text-n-slate-12">
                {{ a.name }}
                <span
                  v-if="rows[a.id]?.error"
                  v-tooltip.top="t('TOLZAR_AGENCY_UI.ROW_FAILED_HINT')"
                  class="ml-2 px-2 py-0.5 text-[11px] font-semibold rounded-full align-middle"
                  :class="TONE_BAD"
                  role="status"
                >
                  {{ t('TOLZAR_AGENCY_UI.ROW_FAILED') }}
                </span>
              </td>
              <td>
                <template v-if="!rows[a.id]">{{
                  t('TOLZAR_UI.LOADING')
                }}</template>
                <template v-else-if="rows[a.id].conversations === null">
                  {{ t('TOLZAR_UI.NOT_AVAILABLE') }}
                </template>
                <template v-else>{{
                  number(rows[a.id].conversations)
                }}</template>
              </td>
              <td>
                <span
                  v-if="rows[a.id]?.agreement != null"
                  class="px-2 py-0.5 text-xs rounded-full"
                  :class="TONE_OK"
                >
                  {{ rows[a.id].agreement }}%
                </span>
                <span v-else class="text-n-slate-10">—</span>
              </td>
              <td class="text-n-slate-11">
                <template v-if="!rows[a.id]">{{
                  t('TOLZAR_UI.LOADING')
                }}</template>
                <template v-else-if="rows[a.id].tokens === null">
                  {{ t('TOLZAR_UI.NOT_AVAILABLE') }}
                </template>
                <template v-else>{{ number(rows[a.id].tokens) }}</template>
              </td>
              <td class="pr-4 text-end whitespace-nowrap">
                <router-link
                  :to="`/app/accounts/${a.id}/dashboard`"
                  class="mr-3 text-n-brand"
                >
                  {{ t('TOLZAR_AGENCY.OPEN') }}
                </router-link>
                <button
                  type="button"
                  class="text-n-brand"
                  :aria-expanded="editing?.id === a.id"
                  @click="openBrand(a)"
                >
                  {{ t('TOLZAR_AGENCY.BRANDING') }}
                </button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
      <p class="mt-2 text-xs text-n-slate-10">
        {{ t('TOLZAR_AGENCY.NEW_HINT') }}
      </p>

      <div
        v-if="editing"
        class="grid gap-5 p-5 mt-5 rounded-xl border bg-n-solid-1 border-n-weak md:grid-cols-2"
      >
        <div>
          <h2 class="mt-0 text-[16px] font-bold">
            {{ t('TOLZAR_AGENCY.BRANDING') }}: {{ editing.name }}
          </h2>
          <label :class="LABEL" for="tz-brand-name">{{
            t('TOLZAR_AGENCY.PRODUCT_NAME')
          }}</label>
          <input
            id="tz-brand-name"
            v-model="brand.product_name"
            :class="INPUT"
          />
          <label :class="LABEL" for="tz-brand-color">{{
            t('TOLZAR_AGENCY.COLOR')
          }}</label>
          <input
            id="tz-brand-color"
            v-model="brand.color"
            type="color"
            class="h-9 rounded border border-solid border-n-weak"
            :aria-describedby="lowContrast ? 'tz-brand-contrast' : undefined"
          />
          <p
            v-if="lowContrast"
            id="tz-brand-contrast"
            class="p-2 mt-2 text-xs rounded-lg"
            :class="TONE_WARN"
            role="alert"
          >
            {{ t('TOLZAR_AGENCY_UI.CONTRAST_WARN') }}
          </p>
          <label :class="LABEL" for="tz-brand-logo">{{
            t('TOLZAR_AGENCY.LOGO')
          }}</label>
          <input
            id="tz-brand-logo"
            v-model="brand.logo_url"
            :class="INPUT"
            type="url"
          />
          <label :class="LABEL" for="tz-brand-mail">{{
            t('TOLZAR_AGENCY.SUPPORT')
          }}</label>
          <input
            id="tz-brand-mail"
            v-model="brand.support_email"
            :class="INPUT"
            type="email"
          />
          <button
            type="button"
            :class="BTN"
            :disabled="busy"
            @click="saveBrand"
          >
            {{ busy ? t('TOLZAR_UI.SAVING') : t('TOLZAR_SETTINGS.SAVE') }}
          </button>
          <BrainNotice :result="result" :saved="saved" />
          <p class="text-xs text-n-slate-10">
            {{ t('TOLZAR_AGENCY.APPLY_HINT') }}
          </p>
        </div>
        <div>
          <span :class="LABEL">{{ t('TOLZAR_AGENCY.PREVIEW') }}</span>
          <div
            class="overflow-hidden rounded-lg border border-solid border-n-weak"
          >
            <div
              class="flex gap-2 items-center px-3 py-2.5 font-semibold text-white"
              :class="{ 'bg-n-brand': !brand.color }"
              :style="brand.color ? { background: brand.color } : undefined"
            >
              <img
                v-if="brand.logo_url"
                :src="brand.logo_url"
                alt=""
                class="rounded size-6"
              />
              {{ brand.product_name || t('TOLZAR_AGENCY_UI.DEFAULT_NAME') }}
            </div>
            <div class="p-3 text-[13px] text-n-slate-11">
              {{ t('TOLZAR_AGENCY_UI.PREVIEW_NAV') }}<br />
              <span class="text-xs">{{ brand.support_email }}</span>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
