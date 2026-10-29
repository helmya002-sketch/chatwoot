<script setup>
import { ref, computed, onMounted } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import ContactAPI from 'dashboard/api/contacts';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';
import {
  STAGES as SHARED_STAGES,
  applyPipelineStages,
  loadStageAttributes,
  stageConditions,
  stageColor,
  stageIcon,
  dealValue,
  money as formatMoney,
} from 'dashboard/components-next/Tolzar/tolzarStages';

const route = useRoute();
const { t } = useI18n();
const router = useRouter();
const accountId = computed(() => route.params.accountId);

// The workspace's stages (account setting `pipeline_stages`, else the defaults).
const getAccount = useMapGetter('accounts/getAccount');
const STAGES = computed(() =>
  SHARED_STAGES.map(s => ({
    ...s,
    color: stageColor(s.key),
    icon: stageIcon(s.key),
  }))
);

// cols[stageKey] = { count, contacts: [...], loading }
const cols = ref({});
const loaded = ref(false);
const moveFor = ref(null); // contact id whose move-menu is open
const movingId = ref(null);

applyPipelineStages(getAccount.value(accountId.value)?.settings);
STAGES.value.forEach(s => {
  cols.value[s.key] = { count: 0, contacts: [], loading: true };
});

function stageStyle(color) {
  return { backgroundColor: `${color}1a`, color };
}
function initials(name) {
  return (name || '?').split(' ').map(w => w[0]).join('').slice(0, 2).toUpperCase();
}
function money(v) {
  return v ? formatMoney(v) : '';
}
function timeAgo(ts) {
  if (!ts) return '';
  const s = Math.max(0, Math.floor(Date.now() / 1000 - ts));
  if (s < 3600) return `${Math.floor(s / 60)}m`;
  if (s < 86400) return `${Math.floor(s / 3600)}h`;
  return `${Math.floor(s / 86400)}d`;
}
function cardValue(c) {
  return dealValue(c.ca);
}
function colValue(key) {
  return (cols.value[key]?.contacts || []).reduce((a, c) => a + cardValue(c), 0);
}

async function fetchStage(stage, page = 1) {
  const conditions = stageConditions(stage.key);
  if (!conditions) return { count: 0, contacts: [], loading: false, page };
  const { data } = await ContactAPI.filter(page, 'name', { payload: conditions });
  const payload = data?.payload || [];
  return {
    count: data?.meta?.count ?? payload.length,
    loading: false,
    page,
    contacts: payload.map(c => ({
      id: c.id,
      name: c.name || 'Unknown',
      email: c.email,
      phone: c.phone_number,
      ca: c.custom_attributes || {},
      ts: c.last_activity_at,
      assignee: c.custom_attributes?.assignee,
    })),
  };
}

// The next page of a column (15 cards a page), added below the cards already shown.
async function loadMore(stage) {
  const col = cols.value[stage.key];
  if (!col || col.more) return;
  col.more = true;
  try {
    const next = await fetchStage(stage, (col.page || 1) + 1);
    const seen = new Set(col.contacts.map(c => c.id));
    col.contacts = [...col.contacts, ...next.contacts.filter(c => !seen.has(c.id))];
    col.count = next.count;
    col.page = next.page;
  } finally {
    col.more = false;
  }
}

const totalValue = computed(() =>
  STAGES.value.reduce((a, s) => a + colValue(s.key), 0)
);

// Each column loads only the first page (≤15 cards), so a column with more
// leads would make the summed value wrong. Only surface the total when every
// column is fully loaded — otherwise we'd show a misleadingly low number.
const allLoaded = computed(() =>
  STAGES.value.every(s => {
    const c = cols.value[s.key];
    return c && !c.loading && (c.contacts?.length || 0) >= (c.count || 0);
  })
);

onMounted(async () => {
  await loadStageAttributes(accountId.value);
  await Promise.all(
    STAGES.value.map(async s => {
      try {
        cols.value[s.key] = await fetchStage(s);
      } catch (e) {
        cols.value[s.key] = { count: 0, contacts: [], loading: false, error: true };
      }
    })
  );
  loaded.value = true;
});

async function move(card, fromKey, toKey) {
  moveFor.value = null;
  if (fromKey === toKey) return;
  const from = cols.value[fromKey];
  const to = cols.value[toKey];
  // optimistic move
  from.contacts = from.contacts.filter(c => c.id !== card.id);
  from.count = Math.max(0, from.count - 1);
  card.ca = { ...card.ca, lifecycle_stage: toKey };
  to.contacts = [card, ...to.contacts];
  to.count += 1;
  movingId.value = card.id;
  try {
    // Re-read the contact's current attributes so we only change lifecycle_stage
    // and don't revert edits another agent made since this board loaded
    // (Chatwoot replaces the whole custom_attributes hash on update).
    let current = card.ca;
    try {
      const { data } = await ContactAPI.show(card.id);
      current = data?.payload?.custom_attributes || data?.custom_attributes || card.ca;
    } catch (readErr) {
      current = card.ca; // fall back to the snapshot if the re-read fails
    }
    const merged = { ...current, lifecycle_stage: toKey };
    await ContactAPI.update(card.id, { custom_attributes: merged });
    card.ca = merged;
  } catch (e) {
    // revert, and say why the card jumped back
    useAlert(t('TOLZAR_CONTACTS.STAGES.SET_FAILED'));
    to.contacts = to.contacts.filter(c => c.id !== card.id);
    to.count = Math.max(0, to.count - 1);
    card.ca = { ...card.ca, lifecycle_stage: fromKey };
    from.contacts = [card, ...from.contacts];
    from.count += 1;
  } finally {
    movingId.value = null;
  }
}

function openContact(id) {
  // contact detail — where the Merge tab + full profile live
  router.push(`/app/accounts/${accountId.value}/contacts/${id}`);
}
// Contacts with this stage view applied (ContactsIndex reads ?stage=).
function openStageInContacts(key) {
  router.push({ name: 'contacts_dashboard_index', params: { accountId: accountId.value }, query: { stage: key } });
}
function otherStages(key) {
  return STAGES.value.filter(s => s.key !== key);
}
</script>

<template>
  <div class="flex overflow-hidden flex-col flex-1 h-full bg-n-background" data-tz-build="pipeline-1">
    <!-- header -->
    <div class="tz-rise flex flex-wrap gap-4 justify-between items-center px-5 py-4 border-b md:px-7 border-n-weak">
      <div class="flex gap-3 items-center">
        <span class="tz-mark grid flex-shrink-0 place-content-center rounded-2xl size-11">
          <span class="i-lucide-columns-3 size-6 text-white" />
        </span>
        <div>
          <h1 class="m-0 text-[22px] font-extrabold tracking-tight text-n-slate-12">Pipeline</h1>
          <p class="m-0 text-sm text-n-slate-11">Your lifecycle funnel: move each lead to its next stage.</p>
        </div>
      </div>
      <div class="flex gap-2 items-center">
        <span v-if="totalValue && allLoaded" class="px-3 py-1.5 text-[13px] font-semibold rounded-xl bg-n-alpha-2 text-n-slate-11">
          Pipeline value <span class="text-n-slate-12">{{ money(totalValue) }}</span>
        </span>
      </div>
    </div>

    <!-- board -->
    <div class="flex overflow-x-auto flex-1 gap-4 p-5 md:px-7 items-stretch">
      <div
        v-for="(s, i) in STAGES"
        :key="s.key"
        class="tz-rise flex flex-col flex-shrink-0 w-[300px] rounded-2xl border bg-n-solid-1 border-n-weak"
        :style="{ animationDelay: 60 + i * 50 + 'ms' }"
      >
        <!-- column header -->
        <div class="flex gap-2 items-center px-4 pt-4 pb-3">
          <span class="grid place-content-center rounded-lg size-7" :style="stageStyle(s.color)">
            <span :class="s.icon" class="size-4" />
          </span>
          <span class="flex-1 text-sm font-bold truncate text-n-slate-12">{{ s.label }}</span>
          <span class="px-2 py-0.5 text-xs font-bold rounded-full tabular-nums bg-n-alpha-2 text-n-slate-11">{{ cols[s.key].count }}</span>
        </div>
        <div class="px-4 pb-2 h-4 -mt-1">
          <span v-if="colValue(s.key)" class="text-[11px] font-semibold tabular-nums text-n-slate-10">{{ money(colValue(s.key)) }}</span>
        </div>
        <div class="h-0.5 mx-4 rounded-full" :style="{ background: s.color, opacity: 0.5 }" />

        <!-- cards -->
        <div class="overflow-y-auto flex-1 p-2.5 space-y-2.5 min-h-[120px]">
          <div v-if="cols[s.key].loading" class="pt-6 text-xs text-center text-n-slate-10">Loading…</div>
          <template v-else>
            <div
              v-for="card in cols[s.key].contacts"
              :key="card.id"
              class="tz-cardlift group relative p-3 rounded-xl border shadow-sm transition-all cursor-pointer bg-n-solid-1 border-n-weak hover:border-n-slate-6"
              :class="{ 'opacity-50': movingId === card.id }"
              @click="openContact(card.id)"
            >
              <div class="flex gap-2.5 items-start">
                <span class="grid flex-shrink-0 place-content-center mt-0.5 text-[11px] font-bold rounded-full size-8 bg-n-alpha-2 text-n-slate-11">{{ initials(card.name) }}</span>
                <div class="flex-1 min-w-0">
                  <div class="text-[13px] font-semibold truncate text-n-slate-12">{{ card.name }}</div>
                  <div class="text-[11px] truncate text-n-slate-10">{{ card.email || card.phone || 'No contact info' }}</div>
                </div>
                <button
                  type="button"
                  class="grid flex-shrink-0 place-content-center rounded-lg opacity-0 transition-opacity size-6 text-n-slate-10 group-hover:opacity-100 hover:bg-n-alpha-2 hover:text-n-slate-12"
                  @click.stop="moveFor = moveFor === card.id ? null : card.id"
                >
                  <span class="i-lucide-arrow-right-left size-3.5" />
                </button>
              </div>
              <div class="flex gap-2 items-center mt-2">
                <span v-if="cardValue(card)" class="px-1.5 py-0.5 text-[10px] font-bold rounded-md tabular-nums" :style="stageStyle('#10b981')">{{ money(cardValue(card)) }}</span>
                <span v-if="card.ts" class="ltr:ml-auto rtl:mr-auto text-[10px] text-n-slate-10">{{ timeAgo(card.ts) }}</span>
              </div>

              <!-- move menu -->
              <div v-if="moveFor === card.id" class="overflow-hidden absolute right-2 top-10 z-20 w-44 rounded-xl border shadow-lg bg-n-solid-1 border-n-weak" @click.stop>
                <div class="px-3 py-1.5 text-[10px] font-bold tracking-wide uppercase text-n-slate-10">Move to</div>
                <button
                  v-for="t in otherStages(s.key)"
                  :key="t.key"
                  type="button"
                  class="flex gap-2 items-center px-3 py-2 w-full text-left text-[13px] transition-colors text-n-slate-12 hover:bg-n-alpha-1"
                  @click.stop="move(card, s.key, t.key)"
                >
                  <span class="inline-block rounded-full size-2" :style="{ background: t.color }" />
                  {{ t.label }}
                </button>
              </div>
            </div>
            <div v-if="cols[s.key].error" class="pt-8 text-xs text-center text-n-ruby-11">{{ t('TOLZAR_PIPELINE.LOAD_FAILED') }}</div>
            <div v-else-if="!cols[s.key].contacts.length" class="pt-8 text-xs text-center text-n-slate-10">No contacts</div>
            <div v-else-if="cols[s.key].count > cols[s.key].contacts.length" class="pt-1 text-[11px] text-center text-n-slate-10">
              <button type="button" class="underline hover:text-n-slate-12" :disabled="cols[s.key].more" @click="loadMore(s)">
                {{ cols[s.key].more ? 'Loading…' : `Show more (${cols[s.key].count - cols[s.key].contacts.length} left)` }}
              </button>
              <button type="button" class="ml-2 underline hover:text-n-slate-12" @click="openStageInContacts(s.key)">
                Open in Contacts
              </button>
            </div>
          </template>
        </div>
      </div>
    </div>

    <!-- click-catcher to close the move menu -->
    <div v-if="moveFor" class="fixed inset-0 z-10" @click="moveFor = null" />
  </div>
</template>

<style scoped>
.tz-mark {
  background: linear-gradient(140deg, #5472e4, #3e63dd);
  box-shadow: 0 8px 20px -6px rgba(62, 99, 221, 0.5);
}
.tz-btn-primary {
  display: inline-flex;
  gap: 0.5rem;
  align-items: center;
  height: 2.25rem;
  padding: 0 1rem;
  font-size: 0.875rem;
  font-weight: 600;
  color: #fff;
  background: #3e63dd;
  border: 0;
  border-radius: 0.75rem;
  cursor: pointer;
}
.tz-cardlift {
  transition: transform 0.15s ease, box-shadow 0.15s ease, border-color 0.15s ease;
}
.tz-cardlift:hover {
  transform: translateY(-1px);
  box-shadow: 0 10px 22px -14px rgba(15, 23, 42, 0.3);
}
.tz-rise {
  opacity: 0;
  animation: tz-rise 0.45s cubic-bezier(0.22, 1, 0.36, 1) forwards;
}
@keyframes tz-rise {
  from { opacity: 0; transform: translateY(10px); }
  to { opacity: 1; transform: translateY(0); }
}
@media (prefers-reduced-motion: reduce) {
  .tz-rise { animation: none; opacity: 1; }
}
</style>
