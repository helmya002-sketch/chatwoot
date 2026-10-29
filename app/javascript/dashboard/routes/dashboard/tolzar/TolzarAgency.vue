<script setup>
import { ref, computed, onMounted } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';
import { brainErrors, isOwnerOnly } from 'dashboard/components-next/Tolzar/tolzarBrainApi';

// Agency console (R11, approved mock agency-white-label-v1): every workspace this person
// administers, with usage and AI quality side by side, and per-workspace branding. Each client
// still sees only its own workspace (Chatwoot accounts stay separate).
const currentUser = useMapGetter('getCurrentUser');
const workspaces = computed(() => (currentUser.value?.accounts || []).filter(a => a.role === 'administrator'));
const rows = ref({});
const editing = ref(null);
const brand = ref({});
const saved = ref('');
const saveError = ref('');

const { t } = useI18n();
const tz = id => `/api/v1/accounts/${id}/tolzar`;

async function loadRow(a) {
  const [u, s] = await Promise.all([
    window.axios.get(`${tz(a.id)}/brain/usage`, { params: { days: 30 } }).then(r => r.data).catch(() => ({})),
    window.axios.get(`${tz(a.id)}/scoreboard`, { params: { days: 30 } }).then(r => r.data).catch(() => ({})),
  ]);
  const agreement = (s.checks || []).find(c => c.key === 'agreement');
  rows.value[a.id] = {
    conversations: u.total?.conversations ?? 0,
    tokens: (u.total?.input_tokens ?? 0) + (u.total?.output_tokens ?? 0),
    agreement: agreement && agreement.value != null ? Math.round(agreement.value * 100) : null,
  };
}

async function openBrand(a) {
  editing.value = a;
  saved.value = '';
  const r = await window.axios.get(`${tz(a.id)}/brain/branding`).then(x => x.data).catch(() => ({}));
  brand.value = { product_name: '', color: '#3e63dd', logo_url: '', support_email: '', ...(r.branding || {}) };
}
async function saveBrand() {
  const r = await window.axios
    .post(`${tz(editing.value.id)}/brain/branding`, brand.value)
    .then(x => x.data)
    .catch(e => e?.response?.data || { ok: false, error: 'brain_unreachable' });
  if (r.ok === false || r.detail !== undefined) {
    saved.value = '';
    saveError.value = isOwnerOnly(r) ? t('TOLZAR_SETTINGS.R1.OWNER_ONLY') : brainErrors(r).join(' · ');
    return;
  }
  saveError.value = '';
  brand.value = { ...brand.value, ...(r.branding || {}) };
  saved.value = 'ok';
}

onMounted(() => workspaces.value.forEach(loadRow));
</script>

<template>
  <div class="overflow-auto flex-1 bg-n-background" data-tz-build="agency-1">
    <div class="mx-auto max-w-[1100px] px-5 pb-16 pt-7">
      <h1 class="m-0 text-[22px] font-extrabold tracking-tight text-n-slate-12">{{ $t('TOLZAR_AGENCY.TITLE') }}</h1>
      <p class="mt-1 text-sm text-n-slate-11">{{ $t('TOLZAR_AGENCY.LEAD') }}</p>

      <div class="overflow-hidden mt-5 rounded-xl border bg-n-solid-1 border-n-weak">
        <table class="w-full text-[13.5px]">
          <thead>
            <tr class="text-xs text-left text-n-slate-10">
              <th class="px-4 py-2.5">{{ $t('TOLZAR_AGENCY.WORKSPACE') }}</th>
              <th>{{ $t('TOLZAR_AGENCY.CONVERSATIONS') }}</th>
              <th>{{ $t('TOLZAR_AGENCY.AGREEMENT') }}</th>
              <th>{{ $t('TOLZAR_AGENCY.TOKENS') }}</th>
              <th />
            </tr>
          </thead>
          <tbody>
            <tr v-for="a in workspaces" :key="a.id" class="border-t border-n-weak">
              <td class="px-4 py-2.5 font-semibold text-n-slate-12">{{ a.name }}</td>
              <td>{{ rows[a.id]?.conversations ?? '…' }}</td>
              <td>
                <span v-if="rows[a.id]?.agreement != null" class="px-2 py-0.5 text-xs rounded-full text-emerald-700 bg-emerald-500/10">{{ rows[a.id].agreement }}%</span>
                <span v-else class="text-n-slate-10">—</span>
              </td>
              <td class="text-n-slate-11">{{ rows[a.id] ? rows[a.id].tokens.toLocaleString() : '…' }}</td>
              <td class="pr-4 text-right whitespace-nowrap">
                <router-link :to="`/app/accounts/${a.id}/dashboard`" class="mr-3 text-n-brand">{{ $t('TOLZAR_AGENCY.OPEN') }}</router-link>
                <button type="button" class="text-n-brand" @click="openBrand(a)">{{ $t('TOLZAR_AGENCY.BRANDING') }}</button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
      <p class="mt-2 text-xs text-n-slate-10">{{ $t('TOLZAR_AGENCY.NEW_HINT') }}</p>

      <div v-if="editing" class="grid gap-5 p-5 mt-5 rounded-xl border bg-n-solid-1 border-n-weak md:grid-cols-2">
        <div>
          <h2 class="mt-0 text-[16px] font-bold">{{ $t('TOLZAR_AGENCY.BRANDING') }}: {{ editing.name }}</h2>
          <label class="tz-lab">{{ $t('TOLZAR_AGENCY.PRODUCT_NAME') }}</label>
          <input v-model="brand.product_name" class="tz-in" />
          <label class="tz-lab">{{ $t('TOLZAR_AGENCY.COLOR') }}</label>
          <input v-model="brand.color" type="color" class="h-9 rounded border border-n-weak" />
          <label class="tz-lab">{{ $t('TOLZAR_AGENCY.LOGO') }}</label>
          <input v-model="brand.logo_url" class="tz-in" placeholder="https://…/logo.png" />
          <label class="tz-lab">{{ $t('TOLZAR_AGENCY.SUPPORT') }}</label>
          <input v-model="brand.support_email" class="tz-in" />
          <button type="button" class="tz-btn" @click="saveBrand">{{ $t('TOLZAR_SETTINGS.SAVE') }}</button>
          <span v-if="saved" class="ml-2 text-xs text-emerald-600">✓</span>
          <span v-if="saveError" class="ml-2 text-xs text-rose-600" role="alert">{{ saveError }}</span>
          <p class="text-xs text-n-slate-10">{{ $t('TOLZAR_AGENCY.APPLY_HINT') }}</p>
        </div>
        <div>
          <label class="tz-lab">{{ $t('TOLZAR_AGENCY.PREVIEW') }}</label>
          <div class="overflow-hidden rounded-lg border border-n-weak">
            <div class="flex gap-2 items-center px-3 py-2.5 font-semibold text-white" :style="{ background: brand.color || '#3e63dd' }">
              <img v-if="brand.logo_url" :src="brand.logo_url" alt="" class="rounded size-6" />
              {{ brand.product_name || 'Tolzar' }}
            </div>
            <div class="p-3 text-[13px] text-n-slate-11">Inbox · Contacts · Workflows · Reports<br /><span class="text-xs">{{ brand.support_email }}</span></div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.tz-lab {
  display: block;
  margin: 0.75rem 0 0.25rem;
  font-size: 0.75rem;
  color: rgb(var(--slate-11));
}
.tz-btn {
  display: inline-flex;
  align-items: center;
  height: 2.25rem;
  margin-top: 1rem;
  padding: 0 1rem;
  font-size: 0.875rem;
  font-weight: 600;
  color: #fff;
  background: #3e63dd;
  border: 0;
  border-radius: 0.75rem;
  cursor: pointer;
}
.tz-in {
  box-sizing: border-box;
  width: 100%;
  padding: 0.5rem 0.625rem;
  font-size: 0.8125rem;
  color: rgb(var(--slate-12));
  background: rgb(var(--solid-1));
  border: 1px solid rgb(var(--border-weak));
  border-radius: 0.5rem;
  outline: none;
}
</style>
