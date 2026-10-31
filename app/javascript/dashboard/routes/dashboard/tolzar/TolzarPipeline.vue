<script setup>
import { ref, computed, onMounted, onBeforeUnmount, nextTick } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import ContactAPI from 'dashboard/api/contacts';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';
import { useLocale } from 'shared/composables/useLocale';
import {
  STAGES as SHARED_STAGES,
  applyPipelineStages,
  loadStageAttributes,
  stageConditions,
  stageChipStyle,
  stageColor,
  stageIcon,
  dealValue,
  leadScore,
  scoreTone,
  money as formatMoney,
} from 'dashboard/components-next/Tolzar/tolzarStages';
import { contactChannel } from 'dashboard/components-next/Tolzar/tolzarChannel';
import { ago } from 'dashboard/components-next/Tolzar/tolzarTime';
import {
  HOVER_REVEAL,
  TONE_OK,
  TONE_MUTED,
} from 'dashboard/components-next/Tolzar/settings/tzClasses';

const route = useRoute();
const { t } = useI18n();
const { resolvedLocale } = useLocale();
const router = useRouter();
const accountId = computed(() => route.params.accountId);
const currentUser = useMapGetter('getCurrentUser');

// The workspace's stages (account setting `pipeline_stages`, else the defaults).
const getAccount = useMapGetter('accounts/getAccount');
const STAGES = computed(() =>
  SHARED_STAGES.map(s => ({
    ...s,
    color: stageColor(s.key),
    icon: stageIcon(s.key),
  }))
);

// cols[stageKey] = { count, contacts: [...], loading, page, more, error }. Built in onMounted,
// after the stage list and the defined attributes are known; `col()` guards a stage that
// arrived later (account store catching up) so the template never reads off undefined.
const EMPTY_COL = Object.freeze({ count: 0, contacts: [], loading: true });
const cols = ref({});
const col = key => cols.value[key] || EMPTY_COL;
const loaded = ref(false);
const movingId = ref(null);

function initials(name) {
  return (name || '?')
    .split(' ')
    .map(w => w[0])
    .join('')
    .slice(0, 2)
    .toUpperCase();
}
function money(v) {
  return v ? formatMoney(v) : '';
}
const since = ts => (ts ? ago(new Date(ts * 1000), resolvedLocale.value) : '');
function cardValue(c) {
  return dealValue(c.ca);
}
const channelName = c => {
  const ch = c.channel;
  if (!ch) return '';
  return ch.name || String(ch.channel_type || '').replace(/^Channel::/, '');
};

// ---- Filter bar --------------------------------------------------------------------------------
// The contact filter API has no assignee, team or inbox attribute (stageConditions returns a
// closed OR-group over the stage fields), so these filters work on the cards loaded so far:
// "Mine" by the contact's `assignee` attribute, "Inbox" by the contact's inboxes.
const filter = ref('all'); // 'all' | 'mine' | 'inbox:<id>'
const inboxOptions = computed(() => {
  const seen = new Map();
  Object.values(cols.value).forEach(c =>
    (c.contacts || []).forEach(card =>
      (card.inboxes || []).forEach(ib => {
        if (ib?.id && !seen.has(ib.id)) seen.set(ib.id, ib.name || `#${ib.id}`);
      })
    )
  );
  return [...seen.entries()].map(([id, name]) => ({ id, name }));
});
const isMine = card => {
  const me = currentUser.value || {};
  const a = card.assignee;
  if (!a) return false;
  if (typeof a === 'object') return a.id === me.id || a.name === me.name;
  return String(a) === String(me.id) || String(a) === me.name;
};
const visible = key => {
  const list = col(key).contacts || [];
  if (filter.value === 'all') return list;
  if (filter.value === 'mine') return list.filter(isMine);
  const id = Number(filter.value.slice('inbox:'.length));
  return list.filter(c => (c.inboxes || []).some(ib => ib?.id === id));
};

// ---- Values -----------------------------------------------------------------------------------
// Each column holds the pages loaded so far, so a value is "at least" until the whole column is
// in; the label says how much of it is loaded instead of hiding the number.
const colValue = key =>
  (col(key).contacts || []).reduce((a, c) => a + cardValue(c), 0);
const colLoadedAll = key => {
  const c = col(key);
  return !c.loading && (c.contacts?.length || 0) >= (c.count || 0);
};
const valueLabel = (value, n, m, all) =>
  all
    ? t('TOLZAR_PIPELINE_UI.VALUE_FULL', { value: money(value) })
    : t('TOLZAR_PIPELINE_UI.VALUE_PARTIAL', { value: money(value), n, m });
const colValueLabel = key => {
  const v = colValue(key);
  const c = col(key);
  // No deal value on any loaded card: say nothing rather than "≥  (15 of 260 loaded)".
  if (!v) return '';
  return valueLabel(
    v,
    c.contacts?.length || 0,
    c.count || 0,
    colLoadedAll(key)
  );
};
const totalValue = computed(() =>
  STAGES.value.reduce((a, s) => a + colValue(s.key), 0)
);
const totalLoaded = computed(() =>
  STAGES.value.reduce((a, s) => a + (col(s.key).contacts?.length || 0), 0)
);
const totalCount = computed(() =>
  STAGES.value.reduce((a, s) => a + (col(s.key).count || 0), 0)
);
const allLoaded = computed(() => STAGES.value.every(s => colLoadedAll(s.key)));
const totalValueLabel = computed(() =>
  valueLabel(
    totalValue.value,
    totalLoaded.value,
    totalCount.value,
    allLoaded.value
  )
);

// ---- Loading ----------------------------------------------------------------------------------
async function fetchStage(stage, page = 1) {
  const conditions = stageConditions(stage.key);
  if (!conditions) return { count: 0, contacts: [], loading: false, page };
  const { data } = await ContactAPI.filter(page, 'name', {
    payload: conditions,
  });
  const payload = data?.payload || [];
  return {
    count: data?.meta?.count ?? payload.length,
    loading: false,
    page,
    contacts: payload.map(c => ({
      id: c.id,
      name: c.name || t('TOLZAR_DASHBOARD.UNKNOWN'),
      email: c.email,
      phone: c.phone_number,
      ca: c.custom_attributes || {},
      ts: c.last_activity_at,
      assignee: c.custom_attributes?.assignee,
      score: leadScore(c.custom_attributes),
      channel: contactChannel(c),
      inboxes: (c.contact_inboxes || []).map(ci => ci.inbox).filter(Boolean),
    })),
  };
}

// The next page of a column (15 cards a page), added below the cards already shown.
async function loadMore(stage) {
  const c = cols.value[stage.key];
  if (!c || c.more) return;
  c.more = true;
  try {
    const next = await fetchStage(stage, (c.page || 1) + 1);
    const seen = new Set(c.contacts.map(x => x.id));
    c.contacts = [...c.contacts, ...next.contacts.filter(x => !seen.has(x.id))];
    c.count = next.count;
    c.page = next.page;
  } catch (e) {
    useAlert(t('TOLZAR_UI.LOAD_FAILED'));
  } finally {
    c.more = false;
  }
}

async function loadColumn(s) {
  cols.value[s.key] = { ...EMPTY_COL, contacts: [] };
  try {
    cols.value[s.key] = await fetchStage(s);
  } catch (e) {
    cols.value[s.key] = { count: 0, contacts: [], loading: false, error: true };
  }
}

// The move menu is teleported to <body> so the scrolling column cannot clip it; it is placed
// from the button's box, flipped to the start side or upward when it would leave the viewport.
const menu = ref(null); // { card, fromKey, style }
const menuEl = ref(null);
let menuButton = null;
const MENU_W = 176;
const MENU_H_PER_ITEM = 36;
function closeMenu() {
  if (!menu.value) return;
  menu.value = null;
  if (menuButton) menuButton.focus();
  menuButton = null;
}
function openMenu(e, card, fromKey) {
  if (menu.value?.card.id === card.id) {
    closeMenu();
    return;
  }
  menuButton = e.currentTarget;
  const r = menuButton.getBoundingClientRect();
  const h = 32 + MENU_H_PER_ITEM * (STAGES.value.length - 1);
  const rtl = document.documentElement.dir === 'rtl';
  let left = rtl ? r.left : r.right - MENU_W;
  left = Math.max(8, Math.min(left, window.innerWidth - MENU_W - 8));
  const top =
    r.bottom + h + 8 > window.innerHeight
      ? Math.max(8, r.top - h - 4)
      : r.bottom + 4;
  menu.value = {
    card,
    fromKey,
    style: { left: `${left}px`, top: `${top}px`, width: `${MENU_W}px` },
  };
  nextTick(() => menuEl.value?.querySelector('button')?.focus());
}
function onKey(e) {
  if (e.key === 'Escape' && menu.value) {
    e.preventDefault();
    closeMenu();
  }
}

// ---- Moving -----------------------------------------------------------------------------------
// Tolzar (round 4, c94): after a move, "Undo" for a few seconds (TOLZAR_INBOX_TOOLS_ACCOUNTS workspaces).
const UNDO_MS = 8000;
const lastMove = ref(null); // { card, fromKey, toKey }
let undoTimer = null;
const inboxTools = computed(
  () => !!getAccount.value(accountId.value)?.tolzar_inbox_tools
);
function offerUndo(card, fromKey, toKey) {
  if (!inboxTools.value) return;
  window.clearTimeout(undoTimer);
  lastMove.value = { card, fromKey, toKey };
  undoTimer = window.setTimeout(() => {
    lastMove.value = null;
  }, UNDO_MS);
}
async function undoMove() {
  const m = lastMove.value;
  lastMove.value = null;
  window.clearTimeout(undoTimer);
  // eslint-disable-next-line no-use-before-define
  if (m) await move(m.card, m.toKey, m.fromKey, { undo: true });
}

async function move(card, fromKey, toKey, { undo = false } = {}) {
  closeMenu();
  if (fromKey === toKey) return;
  const from = cols.value[fromKey];
  const to = cols.value[toKey];
  if (!from || !to) return;
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
      current =
        data?.payload?.custom_attributes || data?.custom_attributes || card.ca;
    } catch (readErr) {
      current = card.ca; // fall back to the snapshot if the re-read fails
    }
    const merged = { ...current, lifecycle_stage: toKey };
    await ContactAPI.update(card.id, { custom_attributes: merged });
    card.ca = merged;
    if (!undo) offerUndo(card, fromKey, toKey);
    useAlert(
      t('TOLZAR_CONTACTS.STAGES.SET_SUCCESS', {
        stage: STAGES.value.find(s => s.key === toKey)?.label || toKey,
      })
    );
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

// Drag and drop between columns (HTML5), the same move() as the menu; the menu stays for
// keyboard users.
const drag = ref(null); // { card, fromKey }
const dropKey = ref(null);
function onDragStart(e, card, fromKey) {
  drag.value = { card, fromKey };
  e.dataTransfer.effectAllowed = 'move';
  e.dataTransfer.setData('text/plain', String(card.id));
}
function onDragEnd() {
  drag.value = null;
  dropKey.value = null;
}
function onDragOver(e, key) {
  if (!drag.value) return;
  e.preventDefault();
  e.dataTransfer.dropEffect = 'move';
  dropKey.value = key;
}
function onDrop(e, key) {
  e.preventDefault();
  const d = drag.value;
  onDragEnd();
  if (d && d.fromKey !== key) move(d.card, d.fromKey, key);
}

function openContact(id) {
  // contact detail: where the Merge tab + full profile live
  router.push(`/app/accounts/${accountId.value}/contacts/${id}`);
}
// Contacts with this stage view applied (ContactsIndex reads ?stage=).
function openStageInContacts(key) {
  router.push({
    name: 'contacts_dashboard_index',
    params: { accountId: accountId.value },
    query: { stage: key },
  });
}
function otherStages(key) {
  return STAGES.value.filter(s => s.key !== key);
}

onMounted(async () => {
  applyPipelineStages(getAccount.value(accountId.value)?.settings);
  await loadStageAttributes(accountId.value);
  await Promise.all(STAGES.value.map(loadColumn));
  loaded.value = true;
  window.addEventListener('keydown', onKey);
});
onBeforeUnmount(() => window.removeEventListener('keydown', onKey));
</script>

<template>
  <div
    class="flex overflow-hidden flex-col flex-1 h-full bg-n-background"
    data-tz-build="pipeline-2"
  >
    <!-- Tolzar (c94): undo the last move -->
    <div
      v-if="lastMove"
      class="fixed z-40 bottom-6 left-1/2 -translate-x-1/2 flex items-center gap-3 px-4 py-2.5 rounded-xl bg-n-slate-12 text-n-solid-1 shadow-lg text-sm"
      role="status"
    >
      <span>{{
        t('TOLZAR_CONTACTS.STAGES.MOVED', {
          name: lastMove.card.name || '',
          stage:
            STAGES.find(s => s.key === lastMove.toKey)?.label || lastMove.toKey,
        })
      }}</span>
      <button
        type="button"
        class="font-semibold underline min-h-[32px]"
        @click="undoMove"
      >
        {{ t('TOLZAR_CONTACTS.STAGES.UNDO') }}
      </button>
    </div>
    <!-- header -->
    <div
      class="tz-rise flex flex-wrap gap-4 justify-between items-center px-5 py-4 border-b md:px-7 border-n-weak"
    >
      <div class="flex gap-3 items-center">
        <span
          class="grid flex-shrink-0 place-content-center rounded-2xl size-11 shadow-md bg-n-brand"
        >
          <span class="i-lucide-columns-3 size-6 text-white" />
        </span>
        <div>
          <h1
            class="m-0 text-[22px] font-extrabold tracking-tight text-n-slate-12"
          >
            {{ t('TOLZAR_PIPELINE_UI.TITLE') }}
          </h1>
          <p class="m-0 text-sm text-n-slate-11">
            {{ t('TOLZAR_PIPELINE_UI.SUBTITLE') }}
          </p>
        </div>
      </div>
      <div class="flex flex-wrap gap-2 items-center">
        <!-- filter bar -->
        <div
          class="inline-flex overflow-hidden items-center rounded-xl border border-solid border-n-weak bg-n-solid-1"
          role="group"
          :aria-label="t('TOLZAR_PIPELINE_UI.FILTER.LABEL')"
          :title="t('TOLZAR_PIPELINE_UI.FILTER.HINT')"
        >
          <button
            v-for="f in ['all', 'mine']"
            :key="f"
            type="button"
            class="px-3 h-9 text-[13px]"
            :class="
              filter === f
                ? 'font-semibold text-n-brand bg-n-brand/10'
                : 'text-n-slate-11 hover:bg-n-alpha-1'
            "
            :aria-pressed="filter === f"
            @click="filter = f"
          >
            {{ t(`TOLZAR_PIPELINE_UI.FILTER.${f.toUpperCase()}`) }}
          </button>
          <select
            v-if="inboxOptions.length"
            v-model="filter"
            class="px-2 h-9 text-[13px] bg-transparent border-0 border-l border-solid border-n-weak outline-none text-n-slate-11"
            :class="{
              'font-semibold text-n-brand': filter.startsWith('inbox:'),
            }"
            :aria-label="t('TOLZAR_PIPELINE_UI.FILTER.INBOX')"
          >
            <option value="all">
              {{ t('TOLZAR_PIPELINE_UI.FILTER.ANY_INBOX') }}
            </option>
            <option
              v-for="ib in inboxOptions"
              :key="ib.id"
              :value="`inbox:${ib.id}`"
            >
              {{ ib.name }}
            </option>
          </select>
        </div>
        <span
          v-if="loaded && totalValue"
          class="px-3 py-1.5 text-[13px] font-semibold rounded-xl bg-n-alpha-2 text-n-slate-11"
        >
          {{ t('TOLZAR_PIPELINE_UI.VALUE') }}
          <span class="text-n-slate-12">{{ totalValueLabel }}</span>
        </span>
      </div>
    </div>

    <!-- board -->
    <div class="flex overflow-x-auto flex-1 gap-4 p-5 md:px-7 items-stretch">
      <div
        v-for="(s, i) in STAGES"
        :key="s.key"
        class="tz-rise flex flex-col flex-shrink-0 w-[300px] rounded-2xl border border-solid bg-n-solid-1 transition-colors"
        :class="
          dropKey === s.key && drag && drag.fromKey !== s.key
            ? 'border-n-brand ring-2 ring-n-brand/20'
            : 'border-n-weak'
        "
        :style="{ animationDelay: 60 + i * 50 + 'ms' }"
        @dragover="onDragOver($event, s.key)"
        @dragenter.prevent
        @dragleave="dropKey === s.key && (dropKey = null)"
        @drop="onDrop($event, s.key)"
      >
        <!-- column header -->
        <div class="flex gap-2 items-center px-4 pt-4 pb-3">
          <span
            class="grid place-content-center rounded-lg size-7"
            :style="stageChipStyle(s.key)"
          >
            <span :class="s.icon" class="size-4" />
          </span>
          <span class="flex-1 text-sm font-bold truncate text-n-slate-12">{{
            s.label
          }}</span>
          <span
            class="px-2 py-0.5 text-xs font-bold rounded-full tabular-nums bg-n-alpha-2 text-n-slate-11"
          >
            {{ col(s.key).count ?? 0 }}
          </span>
        </div>
        <div class="px-4 pb-2 h-4 -mt-1">
          <span
            v-if="colValueLabel(s.key)"
            class="text-[11px] font-semibold tabular-nums text-n-slate-10"
          >
            {{ colValueLabel(s.key) }}
          </span>
        </div>
        <div
          class="h-0.5 mx-4 rounded-full opacity-50"
          :style="{ background: s.color }"
        />

        <!-- cards -->
        <div class="overflow-y-auto flex-1 p-2.5 space-y-2.5 min-h-[120px]">
          <div
            v-if="col(s.key).loading"
            class="pt-6 text-xs text-center text-n-slate-10"
          >
            {{ t('TOLZAR_UI.LOADING') }}
          </div>
          <template v-else>
            <div
              v-for="card in visible(s.key)"
              :key="card.id"
              class="tz-cardlift group relative p-3 rounded-xl border border-solid shadow-sm transition-all cursor-pointer bg-n-solid-1 border-n-weak hover:border-n-slate-6"
              :class="{
                'opacity-50': movingId === card.id,
                'opacity-40': drag && drag.card.id === card.id,
              }"
              draggable="true"
              tabindex="0"
              @click="openContact(card.id)"
              @keydown.enter.self="openContact(card.id)"
              @dragstart="onDragStart($event, card, s.key)"
              @dragend="onDragEnd"
            >
              <div class="flex gap-2.5 items-start">
                <span
                  class="grid flex-shrink-0 place-content-center mt-0.5 text-[11px] font-bold rounded-full size-8 bg-n-alpha-2 text-n-slate-11"
                >
                  {{ initials(card.name) }}
                </span>
                <div class="flex-1 min-w-0">
                  <div
                    class="text-[13px] font-semibold truncate text-n-slate-12"
                  >
                    {{ card.name }}
                  </div>
                  <div class="text-[11px] truncate text-n-slate-10">
                    {{
                      card.email ||
                      card.phone ||
                      t('TOLZAR_PIPELINE_UI.NO_CONTACT_INFO')
                    }}
                  </div>
                </div>
                <button
                  type="button"
                  class="grid flex-shrink-0 place-content-center rounded-lg transition-opacity size-6 text-n-slate-10 hover:bg-n-alpha-2 hover:text-n-slate-12"
                  :class="[
                    HOVER_REVEAL,
                    { '!opacity-100': menu && menu.card.id === card.id },
                  ]"
                  :aria-label="
                    t('TOLZAR_PIPELINE_UI.MOVE', { name: card.name })
                  "
                  aria-haspopup="menu"
                  :aria-expanded="!!menu && menu.card.id === card.id"
                  @click.stop="openMenu($event, card, s.key)"
                  @keydown.enter.stop
                >
                  <span class="i-lucide-arrow-right-left size-3.5" />
                </button>
              </div>
              <div class="flex flex-wrap gap-1.5 items-center mt-2">
                <span
                  v-if="cardValue(card)"
                  class="px-1.5 py-0.5 text-[10px] font-bold rounded-md tabular-nums"
                  :class="TONE_OK"
                >
                  {{ money(cardValue(card)) }}
                </span>
                <span
                  v-if="card.score !== null"
                  class="px-1.5 py-0.5 text-[10px] font-bold rounded-md tabular-nums bg-n-alpha-2"
                  :class="scoreTone(card.score)"
                  :title="t('TOLZAR_PIPELINE_UI.SCORE', { n: card.score })"
                >
                  {{ card.score }}
                </span>
                <span
                  v-if="channelName(card)"
                  class="px-1.5 py-0.5 text-[10px] font-semibold rounded-md"
                  :class="TONE_MUTED"
                >
                  {{ channelName(card) }}
                </span>
                <span
                  v-if="card.assignee"
                  class="grid place-content-center text-[9px] font-bold rounded-full size-5 bg-n-alpha-2 text-n-slate-11"
                  :title="
                    t('TOLZAR_PIPELINE_UI.ASSIGNEE', {
                      name: card.assignee.name || card.assignee,
                    })
                  "
                >
                  {{ initials(card.assignee.name || String(card.assignee)) }}
                </span>
                <span
                  v-if="card.ts"
                  class="ltr:ml-auto rtl:mr-auto text-[10px] text-n-slate-10"
                >
                  {{ since(card.ts) }}
                </span>
              </div>
            </div>
            <div
              v-if="col(s.key).error"
              class="pt-8 text-xs text-center text-n-ruby-11"
            >
              {{ t('TOLZAR_PIPELINE.LOAD_FAILED') }}
              <button
                type="button"
                class="ml-2 underline hover:text-n-slate-12"
                @click="loadColumn(s)"
              >
                {{ t('TOLZAR_UI.RETRY') }}
              </button>
            </div>
            <div
              v-else-if="!visible(s.key).length"
              class="pt-8 text-xs text-center text-n-slate-10"
            >
              {{
                drag && drag.fromKey !== s.key
                  ? t('TOLZAR_PIPELINE_UI.DROP_HERE')
                  : t('TOLZAR_PIPELINE_UI.NO_CONTACTS')
              }}
            </div>
            <div
              v-if="
                !col(s.key).error &&
                col(s.key).count > col(s.key).contacts.length
              "
              class="pt-1 text-[11px] text-center text-n-slate-10"
            >
              <button
                type="button"
                class="underline hover:text-n-slate-12"
                :disabled="col(s.key).more"
                @click="loadMore(s)"
              >
                {{
                  col(s.key).more
                    ? t('TOLZAR_UI.LOADING')
                    : t('TOLZAR_UI.SHOW_MORE', {
                        n: col(s.key).count - col(s.key).contacts.length,
                      })
                }}
              </button>
              <button
                type="button"
                class="ml-2 underline hover:text-n-slate-12"
                @click="openStageInContacts(s.key)"
              >
                {{ t('TOLZAR_PIPELINE_UI.OPEN_IN_CONTACTS') }}
              </button>
            </div>
          </template>
        </div>
      </div>
    </div>

    <!-- move menu: outside the scrolling column so it is never clipped -->
    <Teleport to="body">
      <template v-if="menu">
        <div class="fixed inset-0 z-40" @click="closeMenu" />
        <div
          ref="menuEl"
          class="fixed z-50 overflow-hidden rounded-xl border border-solid shadow-lg bg-n-solid-1 border-n-weak"
          :style="menu.style"
          role="menu"
          :aria-label="t('TOLZAR_PIPELINE_UI.MOVE', { name: menu.card.name })"
          @click.stop
        >
          <div
            class="px-3 py-1.5 text-[10px] font-bold tracking-wide uppercase text-n-slate-10"
          >
            {{ t('TOLZAR_PIPELINE_UI.MOVE_TO') }}
          </div>
          <button
            v-for="o in otherStages(menu.fromKey)"
            :key="o.key"
            type="button"
            role="menuitem"
            class="flex gap-2 items-center px-3 py-2 w-full text-start text-[13px] transition-colors text-n-slate-12 hover:bg-n-alpha-1 focus-visible:bg-n-alpha-1"
            @click.stop="move(menu.card, menu.fromKey, o.key)"
          >
            <span
              class="inline-block rounded-full size-2"
              :style="{ background: o.color }"
            />
            {{ o.label }}
          </button>
        </div>
      </template>
    </Teleport>
  </div>
</template>

<style scoped>
.tz-cardlift {
  transition:
    transform 0.15s ease,
    box-shadow 0.15s ease,
    border-color 0.15s ease;
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
  from {
    opacity: 0;
    transform: translateY(10px);
  }
  to {
    opacity: 1;
    transform: translateY(0);
  }
}
@media (prefers-reduced-motion: reduce) {
  .tz-rise {
    animation: none;
    opacity: 1;
  }
}
</style>
