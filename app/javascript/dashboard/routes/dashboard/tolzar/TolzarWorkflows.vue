<script setup>
import { ref, computed, onMounted, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { useLocale } from 'shared/composables/useLocale';
import ContactAPI from 'dashboard/api/contacts';
import WorkflowSteps from 'dashboard/components-next/Tolzar/WorkflowSteps.vue';
import ShadowBadge from 'dashboard/components-next/Tolzar/ShadowBadge.vue';
import UnsavedDialog from 'dashboard/components-next/Tolzar/UnsavedDialog.vue';
import ConfirmDialog from 'dashboard/components-next/Tolzar/ConfirmDialog.vue';
import BrainNotice from 'dashboard/components-next/Tolzar/settings/BrainNotice.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import {
  useUnsavedGuard,
  snapshot,
} from 'dashboard/components-next/Tolzar/useUnsavedGuard';
import {
  BTN,
  BTN_GHOST,
  INPUT,
  LABEL,
  TONE_WARN,
  TONE_OK,
  TONE_BAD,
  TONE_MUTED,
} from 'dashboard/components-next/Tolzar/settings/tzClasses';
import { fmtAt } from 'dashboard/components-next/Tolzar/tolzarTime';
import {
  STAGES,
  applyPipelineStages,
} from 'dashboard/components-next/Tolzar/tolzarStages';
import { getWorkspaceSettings } from 'dashboard/components-next/Tolzar/tolzarWorkspace';
import {
  normaliseBranches,
  STEP_TYPES,
  TRIGGERS,
  CONDITIONS,
  stepMeta,
  newStep,
  uid,
  waitParts,
  waitMinutes,
  WAIT_UNITS,
  duplicateWorkflow,
  runTone,
  workspaceLanguages,
  pickLang,
} from 'dashboard/components-next/Tolzar/tolzarWorkflows';

// --- Workflows (roadmap B1): real, server-side. The brain stores, validates and runs them;
// everything runs in Shadow (a send is a private "would send" note). Approved mock: workflows-v1.
const { t } = useI18n();
const { resolvedLocale } = useLocale();
const store = useStore();
const accountId = useMapGetter('getCurrentAccountId');
const getAccount = useMapGetter('accounts/getAccount');
const teams = useMapGetter('teams/getTeams');
const contactAttrs = useMapGetter('attributes/getContactAttributes');
const getContact = useMapGetter('contacts/getContact');
const api = computed(() => `/api/v1/accounts/${accountId.value}/tolzar/workflows`);

// A refusal (403 owner_only, brain 400) comes back as data so the page can say why; a network
// failure becomes `brain_unreachable`. Nothing here throws into the template.
const answer = request =>
  request
    .then(r => r.data || {})
    .catch(e => e?.response?.data || { ok: false, error: 'brain_unreachable' });
const refused = r => !r || r.ok === false || r.detail !== undefined;
// The brain's validation errors ({ ok: false, errors: [...] }) as lines BrainNotice can show.
const asNotice = r =>
  r && Array.isArray(r.errors) && r.errors.length ? { detail: r.errors } : r;

const flows = ref([]);
const stats = ref({});
const templates = ref([]);
const loading = ref(true);
const loadResult = ref(null);
const draft = ref(null);
const stored = ref(''); // snapshot of the draft as the brain has it (or as it was opened)
const isNew = ref(false);
const selected = ref(null); // a step object, or 'trigger' / 'settings'
const palette = ref(null); // { list, at } where a new step goes
const tab = ref('flow');
const saving = ref(false);
const saveResult = ref(null);
const savedText = ref('');
const removeResult = ref(null);
const runs = ref([]);
const runsBusy = ref(false);
const runsLimit = ref(100);
const runsResult = ref(null);
const BLANK_TEST = {
  contactId: null,
  contactName: '',
  conversationId: '',
  replied: true,
  result: null,
  busy: false,
};
const test = ref({ ...BLANK_TEST });
const testResult = ref(null);
const lang = ref('en');
const wsLangs = ref([]);
const unsavedRef = ref(null);
const confirmRef = ref(null);

const clone = o => JSON.parse(JSON.stringify(o));

// Never lose a draft: Back, opening another workflow, Duplicate and leaving the route all ask first.
const dirty = computed(() => !!draft.value && snapshot(draft.value) !== stored.value);
const { guard } = useUnsavedGuard({
  isDirty: () => dirty.value,
  confirm: () => unsavedRef.value?.ask(),
});

async function load() {
  loading.value = true;
  loadResult.value = null;
  const data = await answer(window.axios.get(api.value));
  if (refused(data)) {
    loadResult.value = data;
    flows.value = [];
  } else {
    flows.value = data.workflows || [];
    stats.value = data.stats || {};
  }
  // Templates are a convenience: a failure here must not hide the list.
  const tpl = await answer(window.axios.get(`${api.value}/templates`));
  templates.value = refused(tpl) ? [] : tpl.templates || [];
  loading.value = false;
}

function show(f, fresh = false) {
  draft.value = clone(f);
  normaliseBranches(draft.value.steps);
  draft.value.settings = draft.value.settings || {};
  stored.value = snapshot(draft.value);
  isNew.value = fresh;
  selected.value = 'trigger';
  palette.value = null;
  saveResult.value = null;
  savedText.value = '';
  removeResult.value = null;
  tab.value = 'flow';
  runs.value = [];
  runsLimit.value = 100;
  runsResult.value = null;
  test.value = { ...BLANK_TEST };
  testResult.value = null;
}
async function open(f, fresh = false) {
  if (draft.value && !(await guard())) return;
  show(f, fresh);
}
function createBlank() {
  open(
    {
      id: uid(),
      name: t('TOLZAR_WORKFLOWS_UI.NEW_NAME'),
      status: 'draft',
      trigger: { type: 'guest_message' },
      steps: [],
      settings: {},
    },
    true
  );
}
function fromTemplate(tpl, ev) {
  // Close the <details> menu after a pick.
  const d = ev?.target?.closest?.('details');
  if (d) d.open = false;
  open({ ...clone(tpl), id: `${tpl.id}-${uid()}`, status: 'draft' }, true);
}
async function duplicate() {
  if (!(await guard())) return;
  show(duplicateWorkflow(draft.value, t('TOLZAR_WORKFLOWS_UI.COPY_SUFFIX')), true);
}
async function back() {
  if (!(await guard())) return;
  draft.value = null;
  load();
}

async function save() {
  if (saving.value) return;
  saving.value = true;
  saveResult.value = null;
  savedText.value = '';
  const data = await answer(window.axios.post(api.value, { workflow: draft.value }));
  saving.value = false;
  if (refused(data)) {
    saveResult.value = asNotice(data);
    return;
  }
  draft.value = data.workflow || draft.value;
  normaliseBranches(draft.value?.steps);
  draft.value.settings = draft.value.settings || {};
  stored.value = snapshot(draft.value);
  isNew.value = false;
  savedText.value = t('TOLZAR_WORKFLOWS_UI.SAVED');
}
async function remove() {
  const ok = await confirmRef.value?.ask({
    title: t('TOLZAR_WORKFLOWS_UI.DELETE_TITLE'),
    description: t('TOLZAR_WORKFLOWS_UI.DELETE_BODY', { name: draft.value.name }),
    confirmLabel: t('TOLZAR_WORKFLOWS_UI.DELETE_CONFIRM'),
    cancelLabel: t('TOLZAR_UI.CANCEL'),
    danger: true,
  });
  if (!ok) return;
  removeResult.value = null;
  const data = await answer(window.axios.post(`${api.value}/delete`, { id: draft.value.id }));
  if (refused(data)) {
    removeResult.value = data;
    return;
  }
  draft.value = null;
  load();
}
async function loadRuns(more = false) {
  if (isNew.value) return;
  tab.value = 'runs';
  if (more) runsLimit.value += 100;
  runsBusy.value = true;
  runsResult.value = null;
  const data = await answer(
    window.axios.get(`${api.value}/runs`, {
      params: { workflow_id: draft.value.id, limit: runsLimit.value },
    })
  );
  runsBusy.value = false;
  if (refused(data)) {
    runsResult.value = data;
    return;
  }
  runs.value = data.runs || [];
}
async function runTest() {
  if (test.value.busy) return;
  test.value.busy = true;
  testResult.value = null;
  const data = await answer(
    window.axios.post(`${api.value}/test`, {
      workflow: draft.value,
      contact_id: test.value.contactId || null,
      conversation_id: test.value.conversationId || null,
      replied: test.value.replied,
    })
  );
  test.value.busy = false;
  if (refused(data) && !Array.isArray(data.trace)) {
    testResult.value = asNotice(data);
    test.value.result = null;
    return;
  }
  test.value.result = data;
}

// Test tab: pick the contact by name (Chatwoot's own contact search), not by typing an id.
const search = ref({ q: '', hits: [], busy: false, done: false });
let searchTimer = null;
let searchSeq = 0;
function onSearch(q) {
  search.value.q = q;
  clearTimeout(searchTimer);
  const text = q.trim();
  if (text.length < 2) {
    search.value = { q, hits: [], busy: false, done: false };
    return;
  }
  searchSeq += 1;
  const seq = searchSeq;
  search.value.busy = true;
  searchTimer = setTimeout(async () => {
    try {
      const { data } = await ContactAPI.search(text, 1, 'name');
      if (seq !== searchSeq) return;
      search.value.hits = (data?.payload || []).slice(0, 8);
    } catch (e) {
      if (seq === searchSeq) search.value.hits = [];
    }
    if (seq === searchSeq) {
      search.value.busy = false;
      search.value.done = true;
    }
  }, 300);
}
function pickContact(c) {
  test.value.contactId = c.id;
  test.value.contactName = c.name || c.email || c.phone_number || `#${c.id}`;
  search.value = { q: '', hits: [], busy: false, done: false };
}
function clearContact() {
  test.value.contactId = null;
  test.value.contactName = '';
}

function addAt(list, at) {
  palette.value = { list, at };
  selected.value = null;
}
function pick(type) {
  const s = newStep(type);
  palette.value.list.splice(palette.value.at, 0, s);
  palette.value = null;
  selected.value = s;
}
function removeAt(list, at) {
  if (list[at] === selected.value) selected.value = null;
  list.splice(at, 1);
}

const sel = computed(() =>
  selected.value && typeof selected.value === 'object' ? selected.value : null
);

// Message languages: chips from the workspace's languages; the textarea always says which
// language it edits and never falls back to another one silently.
const langs = computed(() => {
  const txt = sel.value?.config?.text;
  return txt && typeof txt === 'object' ? Object.keys(txt) : [];
});
const addableLangs = computed(() => wsLangs.value.filter(l => !langs.value.includes(l)));
// Wait step: the unit lives here, so typing 90 in "minutes" does not flip the select.
const waitUnit = ref(1);
watch(langs, list => {
  lang.value = pickLang(list, lang.value);
});
watch(sel, s => {
  if (s?.type === 'send_message') lang.value = pickLang(langs.value, lang.value);
  if (s?.type === 'wait') waitUnit.value = waitParts(s.config?.minutes).unit;
});
function addLang(code) {
  if (!sel.value || !code) return;
  if (!sel.value.config.text || typeof sel.value.config.text !== 'object') {
    sel.value.config.text = {};
  }
  if (!(code in sel.value.config.text)) sel.value.config.text[code] = '';
  lang.value = code;
}
function removeLang(code) {
  if (!sel.value?.config?.text) return;
  delete sel.value.config.text[code];
}

const waitN = computed(() => {
  const m = Number(sel.value?.config?.minutes) || 0;
  return Math.round((m / waitUnit.value) * 100) / 100;
});
function setWaitN(n) {
  sel.value.config.minutes = waitMinutes(n, waitUnit.value);
}
function setWaitUnit(u) {
  const n = waitN.value;
  waitUnit.value = Number(u);
  sel.value.config.minutes = waitMinutes(n, waitUnit.value);
}
const UNIT_KEYS = { 1: 'UNIT_MIN', 60: 'UNIT_H', 1440: 'UNIT_D' };

// Pickers instead of internal keys: fields from the custom attribute definitions, stages from the
// pipeline, teams from the store. A stored value the lists do not know stays selectable.
const fieldOptions = computed(() =>
  (contactAttrs.value || []).map(a => ({
    value: a.attributeKey,
    label: a.attributeDisplayName || a.attributeKey,
  }))
);
const fieldLabel = key => fieldOptions.value.find(o => o.value === key)?.label || key;
const stageKnown = key => !key || STAGES.some(s => s.key === key);
const teamKnown = id => !id || (teams.value || []).some(tm => String(tm.id) === String(id));
function setTeam(ev) {
  const id = ev.target.value;
  const team = (teams.value || []).find(tm => String(tm.id) === String(id));
  sel.value.config.team_id = team ? team.id : id;
  if (team) sel.value.config.team = team.name;
  else delete sel.value.config.team;
}

const settingsRows = computed(() =>
  Object.entries(draft.value?.settings || {}).filter(([k]) => k !== 'by_team' && k !== 'by_place')
);
const settingKey = ref('');
const settingKeyOk = computed(() => /^[a-z0-9_]{1,40}$/i.test(settingKey.value.trim()));
function addSetting() {
  const key = settingKey.value.trim();
  if (!settingKeyOk.value) return;
  if (!(key in draft.value.settings)) draft.value.settings[key] = '';
  settingKey.value = '';
}
const runCounts = f => {
  const s = stats.value[f.id] || {};
  return {
    running: (s.waiting || 0) + (s.waiting_reply || 0) + (s.running || 0),
    done: s.done || 0,
  };
};

// Status: one switch ("Run in Shadow") plus the one Shadow badge. Live is never offered here
// (owner rule); a workflow that is live already keeps it until switched off.
const shadowOn = computed({
  get: () => ['shadow', 'live'].includes(draft.value?.status),
  set: on => {
    if (!draft.value) return;
    if (on) {
      if (draft.value.status !== 'live') draft.value.status = 'shadow';
    } else draft.value.status = 'draft';
  },
});
const BADGE_STATE = { live: 'live', shadow: 'shadow' };
const badgeState = status => BADGE_STATE[status] || 'off';
const TONES = { ok: TONE_OK, bad: TONE_BAD, muted: TONE_MUTED, warn: TONE_WARN };
const runStatusLabel = s => {
  const key = `TOLZAR_WORKFLOWS_UI.RUN.STATUS.${s}`;
  const label = t(key);
  return label === key ? String(s || '') : label;
};
const contactName = id => (id ? getContact.value(id)?.name || '' : '');
const at = iso => fmtAt(iso, resolvedLocale.value);

const TABS = ['flow', 'runs', 'test'];
const tabLocked = name => name !== 'flow' && isNew.value;
function openTab(name) {
  if (tabLocked(name)) return;
  if (name === 'runs') loadRuns();
  else tab.value = name;
}

async function loadLookups() {
  applyPipelineStages(getAccount.value(accountId.value)?.settings);
  if (!(teams.value || []).length) store.dispatch('teams/get');
  if (!(contactAttrs.value || []).length) store.dispatch('attributes/get');
  const view = await getWorkspaceSettings(accountId.value).catch(() => null);
  wsLangs.value = workspaceLanguages(view);
}

onMounted(() => {
  load();
  loadLookups();
});
</script>

<template>
  <div class="overflow-auto flex-1 bg-n-background" data-tz-build="workflows-ux-r2">
    <UnsavedDialog ref="unsavedRef" />
    <ConfirmDialog ref="confirmRef" />

    <!-- ===================== LIST ===================== -->
    <div v-if="!draft" class="mx-auto max-w-[1120px] px-5 pb-16 pt-7 md:px-6">
      <div class="flex flex-wrap gap-4 justify-between items-center">
        <div class="flex gap-3 items-center">
          <span class="grid flex-shrink-0 place-content-center rounded-2xl shadow-md size-11 bg-n-brand">
            <span class="i-lucide-workflow size-6 text-white" />
          </span>
          <div>
            <h1 class="m-0 text-[22px] font-extrabold tracking-tight text-n-slate-12">
              {{ $t('TOLZAR_WORKFLOWS.TITLE') }}
            </h1>
            <p class="m-0 text-sm text-n-slate-11">{{ $t('TOLZAR_WORKFLOWS.LEAD') }}</p>
          </div>
        </div>
        <div class="flex gap-2 items-center">
          <details class="relative">
            <summary class="!mt-0 gap-1.5 list-none" :class="BTN_GHOST">
              <span class="i-lucide-layout-template size-4" /> {{ $t('TOLZAR_WORKFLOWS.FROM_TEMPLATE') }}
            </summary>
            <div class="absolute z-20 p-1.5 mt-1 w-[320px] rounded-xl border shadow-lg end-0 bg-n-solid-1 border-n-weak">
              <button
                v-for="tpl in templates"
                :key="tpl.id"
                type="button"
                class="block px-3 py-2 w-full rounded-lg text-start text-[13px] text-n-slate-12 hover:bg-n-alpha-1"
                @click="fromTemplate(tpl, $event)"
              >
                {{ tpl.name }}
              </button>
              <p v-if="!templates.length" class="px-3 py-2 m-0 text-xs text-n-slate-10">{{ $t('TOLZAR_UI.NONE_YET') }}</p>
            </div>
          </details>
          <button type="button" class="!mt-0 gap-2" :class="BTN" @click="createBlank">
            <span class="i-lucide-plus size-4" /> {{ $t('TOLZAR_WORKFLOWS.NEW') }}
          </button>
        </div>
      </div>

      <div v-if="loadResult" class="flex flex-wrap gap-3 items-center max-w-[640px]">
        <div class="flex-1 min-w-[240px]"><BrainNotice :result="loadResult" /></div>
        <button type="button" :class="BTN_GHOST" @click="load">{{ $t('TOLZAR_UI.RETRY') }}</button>
      </div>

      <div class="overflow-hidden mt-5 rounded-2xl border shadow-sm bg-n-solid-1 border-n-weak">
        <div v-if="loading" class="flex gap-2 justify-center items-center p-6 text-sm text-n-slate-10" role="status">
          <Spinner :size="18" /> {{ $t('TOLZAR_UI.LOADING') }}
        </div>
        <div
          v-for="f in flows"
          :key="f.id"
          role="button"
          tabindex="0"
          class="flex flex-wrap gap-3 items-center px-[18px] py-3.5 border-b transition-colors cursor-pointer border-n-weak last:border-0 hover:bg-n-alpha-1 focus-visible:bg-n-alpha-1 outline-none"
          @click="open(f)"
          @keydown.enter.prevent="open(f)"
        >
          <ShadowBadge :state="badgeState(f.status)" />
          <span class="flex-1 font-semibold truncate text-n-slate-12">{{ f.name }}</span>
          <span class="text-[13px] text-n-slate-11">{{ $t(`TOLZAR_WORKFLOWS.TRIGGER.${f.trigger.type}`) }}</span>
          <span class="text-[13px] text-n-slate-10 w-[180px] text-end">{{
            $t('TOLZAR_WORKFLOWS.RUN_COUNTS', runCounts(f))
          }}</span>
        </div>
        <div v-if="!loading && !loadResult && !flows.length" class="p-6 text-center text-n-slate-10">
          {{ $t('TOLZAR_WORKFLOWS.EMPTY') }}
        </div>
      </div>
    </div>

    <!-- ===================== BUILDER ===================== -->
    <div v-else class="flex flex-col h-full">
      <div class="flex flex-wrap gap-3 items-center px-[18px] py-3 border-b bg-n-solid-1 border-n-weak">
        <button type="button" class="!mt-0" :class="BTN_GHOST" @click="back"><span class="i-lucide-chevron-left size-4 rtl:rotate-180" /> {{ $t('TOLZAR_WORKFLOWS.BACK') }}</button>
        <input
          v-model="draft.name"
          :aria-label="$t('TOLZAR_WORKFLOWS_UI.NAME_LABEL')"
          class="flex-1 px-2 py-1 min-w-[160px] text-base font-extrabold rounded-lg border border-transparent outline-none text-n-slate-12 bg-n-background focus:border-n-weak"
        />
        <label class="flex gap-2 items-center text-[13px] text-n-slate-12" :title="$t('TOLZAR_WORKFLOWS_UI.RUN_IN_SHADOW_HINT')">
          <Switch v-model="shadowOn" />
          <span>{{ $t('TOLZAR_WORKFLOWS_UI.RUN_IN_SHADOW') }}</span>
          <ShadowBadge :state="badgeState(draft.status)" :hint="$t('TOLZAR_WORKFLOWS_UI.RUN_IN_SHADOW_HINT')" />
        </label>
        <!-- The raw status stays in the payload (draft / shadow / live / off); the switch is its only control here. -->
        <select v-model="draft.status" class="hidden" aria-hidden="true" tabindex="-1">
          <option value="draft">{{ $t('TOLZAR_WORKFLOWS.STATUS.draft') }}</option>
          <option value="shadow">{{ $t('TOLZAR_WORKFLOWS.STATUS.shadow') }}</option>
          <option value="off">{{ $t('TOLZAR_WORKFLOWS.STATUS.off') }}</option>
          <option value="live">{{ $t('TOLZAR_WORKFLOWS.STATUS.live') }}</option>
        </select>
        <button
          v-if="!isNew"
          type="button"
          class="!mt-0 gap-1.5"
          :class="BTN_GHOST"
          :title="$t('TOLZAR_WORKFLOWS_UI.DUPLICATE_HINT')"
          @click="duplicate"
        >
          <span class="i-lucide-copy size-4" /> {{ $t('TOLZAR_WORKFLOWS_UI.DUPLICATE') }}
        </button>
        <button type="button" class="!mt-0 gap-2" :class="BTN" :disabled="saving" @click="save">
          <Spinner v-if="saving" :size="16" />
          <span v-else class="i-lucide-check size-4" />
          {{ saving ? $t('TOLZAR_UI.SAVING') : $t('TOLZAR_WORKFLOWS.SAVE') }}
        </button>
      </div>
      <div v-if="saveResult || savedText" class="px-[18px] -mt-1">
        <div class="max-w-[720px]"><BrainNotice :result="saveResult" :saved="savedText" /></div>
      </div>
      <div class="flex gap-1 px-[18px] border-b bg-n-solid-1 border-n-weak" role="tablist">
        <span
          v-for="name in TABS"
          :key="name"
          v-tooltip.bottom="tabLocked(name) ? $t('TOLZAR_WORKFLOWS.SAVE_FIRST') : null"
        >
          <button
            type="button"
            role="tab"
            class="px-3 py-2.5 text-sm border-b-2 aria-disabled:opacity-50 aria-disabled:cursor-not-allowed"
            :class="tab === name ? 'font-semibold border-n-brand text-n-slate-12' : 'border-transparent text-n-slate-10'"
            :aria-selected="tab === name"
            :aria-disabled="tabLocked(name)"
            @click="openTab(name)"
          >
            {{ $t(`TOLZAR_WORKFLOWS.TAB.${name}`) }}
          </button>
        </span>
      </div>

      <!-- flow -->
      <div v-if="tab === 'flow'" class="flex flex-col flex-1 min-h-0 lg:flex-row">
        <div class="tz-canvas overflow-auto flex-1 px-5 pt-8 pb-20">
          <div class="flex flex-col items-center">
            <div
              role="button"
              tabindex="0"
              class="overflow-hidden w-[250px] rounded-xl border border-t-[3px] shadow-sm cursor-pointer bg-n-solid-1 border-t-n-ruby-9 outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
              :class="selected === 'trigger' ? 'border-n-brand ring-2 ring-n-brand/20' : 'border-n-weak'"
              @click="selected = 'trigger'; palette = null"
              @keydown.enter.prevent="selected = 'trigger'; palette = null"
            >
              <div class="flex gap-2 items-center px-3 py-2 font-bold border-b border-n-weak text-n-slate-12">
                <span class="i-lucide-zap size-4 text-n-ruby-11" /> {{ $t('TOLZAR_WORKFLOWS.TRIGGER_TITLE') }}
              </div>
              <div class="px-3 py-1.5 text-xs text-n-slate-11">
                {{ $t(`TOLZAR_WORKFLOWS.TRIGGER.${draft.trigger.type}`) }}
                <span v-if="draft.trigger.field"> · {{ fieldLabel(draft.trigger.field) }}{{ draft.trigger.value ? ` = ${draft.trigger.value}` : '' }}</span>
              </div>
            </div>
            <WorkflowSteps
              :steps="draft.steps"
              :selected="sel"
              @select="n => { selected = n; palette = null; }"
              @add="addAt"
              @remove="removeAt"
            />
            <span class="mt-3 text-xs text-n-slate-10">{{ $t('TOLZAR_WORKFLOWS.END') }}</span>
          </div>
        </div>

        <!-- side panel: a column on wide screens, a sheet under the canvas on narrow ones -->
        <div class="overflow-auto flex-shrink-0 p-[18px] w-full border-t max-h-[45vh] lg:max-h-none lg:w-[340px] lg:border-t-0 lg:border-s bg-n-solid-1 border-n-weak">
          <template v-if="palette">
            <h3 class="mt-0 mb-3 text-[15px] font-semibold text-n-slate-12">{{ $t('TOLZAR_WORKFLOWS.ADD_STEP') }}</h3>
            <button
              v-for="s in STEP_TYPES"
              :key="s.type"
              type="button"
              class="flex gap-2.5 items-center px-3 py-2 mb-1.5 w-full rounded-xl border transition-colors text-start border-n-weak hover:bg-n-alpha-1"
              @click="pick(s.type)"
            >
              <span :class="[s.icon, stepMeta(s.type).text]" class="size-4" />
              <span class="text-[13px] font-semibold text-n-slate-12">{{ $t(stepMeta(s.type).label) }}</span>
            </button>
          </template>

          <template v-else-if="selected === 'trigger'">
            <h3 class="mt-0 mb-1 text-[15px] font-semibold text-n-slate-12">{{ $t('TOLZAR_WORKFLOWS.TRIGGER_TITLE') }}</h3>
            <p class="mt-0 text-xs text-n-slate-10">{{ $t('TOLZAR_WORKFLOWS.TRIGGER_HINT') }}</p>
            <label :class="LABEL" for="tz-wf-trigger">{{ $t('TOLZAR_WORKFLOWS.STARTS_WHEN') }}</label>
            <select id="tz-wf-trigger" v-model="draft.trigger.type" :class="INPUT">
              <option v-for="tr in TRIGGERS" :key="tr" :value="tr">{{ $t(`TOLZAR_WORKFLOWS.TRIGGER.${tr}`) }}</option>
            </select>
            <template v-if="draft.trigger.type === 'field_equals' || draft.trigger.type === 'field_date'">
              <label :class="LABEL" for="tz-wf-field">{{ $t('TOLZAR_WORKFLOWS.FIELD') }}</label>
              <select v-if="fieldOptions.length" id="tz-wf-field" v-model="draft.trigger.field" :class="INPUT">
                <option value="">{{ $t('TOLZAR_WORKFLOWS_UI.PICK_FIELD') }}</option>
                <option
                  v-if="draft.trigger.field && !fieldOptions.some(o => o.value === draft.trigger.field)"
                  :value="draft.trigger.field"
                >
                  {{ draft.trigger.field }}
                </option>
                <option v-for="o in fieldOptions" :key="o.value" :value="o.value">{{ o.label }}</option>
              </select>
              <input
                v-else
                id="tz-wf-field"
                v-model="draft.trigger.field"
                :class="INPUT"
                :placeholder="$t('TOLZAR_WORKFLOWS_UI.FIELD_PLACEHOLDER')"
              />
            </template>
            <template v-if="draft.trigger.type === 'field_equals'">
              <label :class="LABEL" for="tz-wf-value">{{ $t('TOLZAR_WORKFLOWS.VALUE') }}</label>
              <input id="tz-wf-value" v-model="draft.trigger.value" :class="INPUT" :placeholder="$t('TOLZAR_WORKFLOWS_UI.VALUE_PLACEHOLDER')" />
              <label :class="LABEL" for="tz-wf-delay">{{ $t('TOLZAR_WORKFLOWS.DELAY_MIN') }}</label>
              <input id="tz-wf-delay" v-model.number="draft.trigger.delay_minutes" type="number" min="0" :class="INPUT" />
            </template>
            <template v-if="draft.trigger.type === 'field_date'">
              <label :class="LABEL" for="tz-wf-offset">{{ $t('TOLZAR_WORKFLOWS.OFFSET_MIN') }}</label>
              <input id="tz-wf-offset" v-model.number="draft.trigger.offset_minutes" type="number" :class="INPUT" />
            </template>

            <h4 class="mt-5 mb-0 text-[13px] font-semibold text-n-slate-12">{{ $t('TOLZAR_WORKFLOWS.SETTINGS') }}</h4>
            <p class="mt-1 mb-2 text-xs text-n-slate-10">{{ $t('TOLZAR_WORKFLOWS.SETTINGS_HINT') }}</p>
            <div v-for="[k] in settingsRows" :key="k" class="mb-2">
              <label class="!mt-0" :class="LABEL" :for="`tz-wf-setting-${k}`">{{ '{' + k + '}' }}</label>
              <input :id="`tz-wf-setting-${k}`" v-model="draft.settings[k]" :class="INPUT" />
            </div>
            <div class="flex gap-1 items-end">
              <div class="flex-1">
                <label :class="LABEL" for="tz-wf-setting-new">{{ $t('TOLZAR_WORKFLOWS_UI.SETTING_NAME') }}</label>
                <input
                  id="tz-wf-setting-new"
                  v-model="settingKey"
                  :class="INPUT"
                  :placeholder="$t('TOLZAR_WORKFLOWS_UI.SETTING_PLACEHOLDER')"
                  @keydown.enter.prevent="addSetting"
                />
              </div>
              <button type="button" class="h-[38px] !mt-0" :class="BTN_GHOST" :disabled="!settingKeyOk" @click="addSetting">
                {{ $t('TOLZAR_WORKFLOWS.ADD') }}
              </button>
            </div>
            <p class="mt-1 mb-0 text-xs text-n-slate-10">{{ $t('TOLZAR_WORKFLOWS_UI.SETTING_NAME_HINT') }}</p>
          </template>

          <template v-else-if="sel">
            <h3 class="flex gap-2 items-center mt-0 mb-3 text-[15px] font-semibold text-n-slate-12">
              <span :class="[stepMeta(sel.type).icon, stepMeta(sel.type).text]" class="size-4" />
              {{ $t(stepMeta(sel.type).label) }}
            </h3>

            <template v-if="sel.type === 'send_message'">
              <div class="flex flex-wrap gap-1 items-center mb-2">
                <span
                  v-for="l in langs"
                  :key="l"
                  class="inline-flex overflow-hidden items-center text-xs rounded-md border"
                  :class="l === lang ? 'text-white bg-n-brand border-n-brand' : 'border-n-weak text-n-slate-11'"
                >
                  <button type="button" class="px-2 py-0.5" :aria-pressed="l === lang" @click="lang = l">{{ l.toUpperCase() }}</button>
                  <button
                    type="button"
                    class="px-1 py-0.5 opacity-70 hover:opacity-100"
                    :aria-label="$t('TOLZAR_WORKFLOWS_UI.REMOVE_LANGUAGE', { lang: l.toUpperCase() })"
                    @click="removeLang(l)"
                  ><span class="i-lucide-x size-3.5" aria-hidden="true" /></button>
                </span>
                <button
                  v-for="l in addableLangs"
                  :key="`add-${l}`"
                  type="button"
                  class="px-2 py-0.5 text-xs rounded-md border border-dashed border-n-strong text-n-brand"
                  :aria-label="$t('TOLZAR_WORKFLOWS_UI.ADD_LANGUAGE', { lang: l.toUpperCase() })"
                  @click="addLang(l)"
                ><span class="i-lucide-plus size-3" aria-hidden="true" />{{ l.toUpperCase() }}</button>
              </div>
              <p v-if="!wsLangs.length" class="mt-0 mb-2 text-xs text-n-slate-10">{{ $t('TOLZAR_WORKFLOWS_UI.NO_LANGS_HINT') }}</p>
              <template v-if="lang && sel.config.text && lang in sel.config.text">
                <label class="!mt-0" :class="LABEL" for="tz-wf-text">{{ $t('TOLZAR_WORKFLOWS_UI.EDITING_LANG', { lang: lang.toUpperCase() }) }}</label>
                <textarea id="tz-wf-text" v-model="sel.config.text[lang]" rows="6" class="resize-y" :class="INPUT" />
              </template>
              <p v-else class="text-xs text-n-amber-11">{{ $t('TOLZAR_WORKFLOWS_UI.NO_TEXT_LANG') }}</p>
              <p class="text-xs text-n-slate-10">{{ $t('TOLZAR_WORKFLOWS.SEND_HINT') }}</p>
              <p class="p-2 text-xs rounded-lg" :class="TONE_WARN">{{ $t('TOLZAR_WORKFLOWS.SHADOW_HINT') }}</p>
            </template>

            <template v-else-if="sel.type === 'comment'">
              <textarea v-model="sel.config.text" rows="5" class="resize-y" :class="INPUT" :aria-label="$t(stepMeta(sel.type).label)" />
            </template>

            <template v-else-if="sel.type === 'wait'">
              <label class="!mt-0" :class="LABEL" for="tz-wf-wait">{{ $t('TOLZAR_WORKFLOWS_UI.WAIT_FOR') }}</label>
              <div class="flex gap-2">
                <input
                  id="tz-wf-wait"
                  type="number"
                  min="1"
                  :class="INPUT"
                  :value="waitN"
                  @change="setWaitN($event.target.value)"
                />
                <select :class="INPUT" :value="waitUnit" :aria-label="$t('TOLZAR_WORKFLOWS_UI.WAIT_FOR')" @change="setWaitUnit($event.target.value)">
                  <option v-for="u in WAIT_UNITS" :key="u" :value="u">{{ $t(`TOLZAR_WORKFLOWS_UI.${UNIT_KEYS[u]}`) }}</option>
                </select>
              </div>
              <label class="flex gap-2 items-center mt-3 text-[13px] text-n-slate-12">
                <input v-model="sel.config.until_reply" type="checkbox" class="accent-n-brand" /> {{ $t('TOLZAR_WORKFLOWS.UNTIL_REPLY') }}
              </label>
            </template>

            <template v-else-if="sel.type === 'branch'">
              <label class="!mt-0" :class="LABEL" for="tz-wf-match">{{ $t('TOLZAR_WORKFLOWS.MATCH') }}</label>
              <select id="tz-wf-match" v-model="sel.config.match" :class="INPUT">
                <option value="all">{{ $t('TOLZAR_WORKFLOWS.MATCH_ALL') }}</option>
                <option value="any">{{ $t('TOLZAR_WORKFLOWS.MATCH_ANY') }}</option>
              </select>
              <div v-for="(c, ci) in sel.config.conditions" :key="ci" class="p-2 mt-2 rounded-lg border border-n-weak">
                <div class="flex gap-1">
                  <select v-model="c.kind" :class="INPUT" :aria-label="$t('TOLZAR_WORKFLOWS.MATCH')">
                    <option v-for="k in CONDITIONS" :key="k" :value="k">{{ $t(`TOLZAR_WORKFLOWS.COND.${k}`) }}</option>
                  </select>
                  <button
                    type="button"
                    class="px-2 text-n-slate-9 hover:text-n-ruby-11"
                    :aria-label="$t('TOLZAR_WORKFLOWS_UI.REMOVE_CONDITION')"
                    @click="sel.config.conditions.splice(ci, 1)"
                  ><span class="i-lucide-x size-3.5" aria-hidden="true" /></button>
                </div>
                <template v-if="['field_equals', 'field_empty'].includes(c.kind)">
                  <select v-if="fieldOptions.length" v-model="c.field" class="mt-1" :class="INPUT" :aria-label="$t('TOLZAR_WORKFLOWS.FIELD')">
                    <option value="">{{ $t('TOLZAR_WORKFLOWS_UI.PICK_FIELD') }}</option>
                    <option v-if="c.field && !fieldOptions.some(o => o.value === c.field)" :value="c.field">{{ c.field }}</option>
                    <option v-for="o in fieldOptions" :key="o.value" :value="o.value">{{ o.label }}</option>
                  </select>
                  <input v-else v-model="c.field" class="mt-1" :class="INPUT" :placeholder="$t('TOLZAR_WORKFLOWS_UI.FIELD_PLACEHOLDER')" />
                </template>
                <input v-if="['field_equals', 'channel_is'].includes(c.kind)" v-model="c.value" class="mt-1" :class="INPUT" :placeholder="$t('TOLZAR_WORKFLOWS.VALUE')" />
                <input v-if="c.kind === 'has_tag'" v-model="c.tag" class="mt-1" :class="INPUT" :placeholder="$t('TOLZAR_WORKFLOWS_UI.TAG_PLACEHOLDER')" />
                <input
                  v-if="c.kind === 'reply_matches'"
                  class="mt-1"
                  :class="INPUT"
                  :value="(c.words || []).join(', ')"
                  :placeholder="$t('TOLZAR_WORKFLOWS.WORDS')"
                  @change="c.words = $event.target.value.split(',').map(w => w.trim()).filter(Boolean)"
                />
                <div v-if="c.kind === 'reply_number'" class="flex gap-1 mt-1">
                  <input v-model.number="c.min" type="number" :class="INPUT" :placeholder="$t('TOLZAR_WORKFLOWS_UI.MIN')" :aria-label="$t('TOLZAR_WORKFLOWS_UI.MIN')" />
                  <input v-model.number="c.max" type="number" :class="INPUT" :placeholder="$t('TOLZAR_WORKFLOWS_UI.MAX')" :aria-label="$t('TOLZAR_WORKFLOWS_UI.MAX')" />
                </div>
              </div>
              <button type="button" class="mt-2 text-xs text-n-brand" @click="sel.config.conditions.push({ kind: 'replied' })">+ {{ $t('TOLZAR_WORKFLOWS.ADD') }}</button>
            </template>

            <template v-else-if="sel.type === 'add_tag'">
              <input v-model="sel.config.tag" :class="INPUT" :placeholder="$t('TOLZAR_WORKFLOWS_UI.TAG_PLACEHOLDER')" :aria-label="$t(stepMeta(sel.type).label)" />
              <p class="text-xs text-n-slate-10">{{ $t('TOLZAR_WORKFLOWS.MIRROR_TAG_HINT') }}</p>
            </template>

            <template v-else-if="sel.type === 'ai_tag'">
              <p class="mt-0 text-xs text-n-slate-10">{{ $t('TOLZAR_WORKFLOWS.AI_TAG_HINT') }}</p>
              <div v-for="(tg, ti) in sel.config.tags" :key="ti" class="flex gap-1 mb-1">
                <input v-model="tg.tag" class="!w-[100px]" :class="INPUT" :placeholder="$t('TOLZAR_WORKFLOWS_UI.TAG_PLACEHOLDER')" :aria-label="$t('TOLZAR_WORKFLOWS_UI.TAG_PLACEHOLDER')" />
                <input v-model="tg.when" :class="INPUT" :placeholder="$t('TOLZAR_WORKFLOWS.WHEN')" :aria-label="$t('TOLZAR_WORKFLOWS.WHEN')" />
                <button
                  type="button"
                  class="px-1 text-n-slate-9 hover:text-n-ruby-11"
                  :aria-label="$t('TOLZAR_WORKFLOWS_UI.REMOVE_TAG')"
                  @click="sel.config.tags.splice(ti, 1)"
                ><span class="i-lucide-x size-3.5" aria-hidden="true" /></button>
              </div>
              <button type="button" class="text-xs text-n-brand" @click="sel.config.tags.push({ tag: '', when: '' })">+ {{ $t('TOLZAR_WORKFLOWS.ADD') }}</button>
            </template>

            <template v-else-if="sel.type === 'update_field'">
              <select v-if="fieldOptions.length" v-model="sel.config.field" :class="INPUT" :aria-label="$t('TOLZAR_WORKFLOWS.FIELD')">
                <option value="">{{ $t('TOLZAR_WORKFLOWS_UI.PICK_FIELD') }}</option>
                <option v-if="sel.config.field && !fieldOptions.some(o => o.value === sel.config.field)" :value="sel.config.field">{{ sel.config.field }}</option>
                <option v-for="o in fieldOptions" :key="o.value" :value="o.value">{{ o.label }}</option>
              </select>
              <input v-else v-model="sel.config.field" :class="INPUT" :placeholder="$t('TOLZAR_WORKFLOWS_UI.FIELD_PLACEHOLDER')" :aria-label="$t('TOLZAR_WORKFLOWS.FIELD')" />
              <input v-model="sel.config.value" class="mt-2" :class="INPUT" :placeholder="$t('TOLZAR_WORKFLOWS.VALUE')" :aria-label="$t('TOLZAR_WORKFLOWS.VALUE')" />
            </template>
            <template v-else-if="sel.type === 'update_stage'">
              <select v-model="sel.config.stage" :class="INPUT" :aria-label="$t(stepMeta(sel.type).label)">
                <option value="">{{ $t('TOLZAR_WORKFLOWS_UI.PICK_STAGE') }}</option>
                <option v-if="!stageKnown(sel.config.stage)" :value="sel.config.stage">
                  {{ $t('TOLZAR_WORKFLOWS_UI.STAGE_UNKNOWN', { stage: sel.config.stage }) }}
                </option>
                <option v-for="s in STAGES" :key="s.key" :value="s.key">{{ s.label }}</option>
              </select>
            </template>
            <template v-else-if="sel.type === 'assign_team'">
              <select :value="String(sel.config.team_id ?? '')" :class="INPUT" :aria-label="$t(stepMeta(sel.type).label)" @change="setTeam">
                <option value="">{{ $t('TOLZAR_WORKFLOWS_UI.PICK_TEAM') }}</option>
                <option v-if="!teamKnown(sel.config.team_id)" :value="String(sel.config.team_id)">
                  {{ $t('TOLZAR_WORKFLOWS_UI.TEAM_UNKNOWN', { id: sel.config.team_id }) }}
                </option>
                <option v-for="tm in teams" :key="tm.id" :value="String(tm.id)">{{ tm.name }}</option>
              </select>
              <p v-if="!teams.length" class="text-xs text-n-slate-10">{{ $t('TOLZAR_WORKFLOWS_UI.NO_TEAMS') }}</p>
            </template>
            <template v-else-if="sel.type === 'record_score'">
              <input v-model="sel.config.name" :class="INPUT" :placeholder="$t('TOLZAR_WORKFLOWS_UI.SCORE_PLACEHOLDER')" :aria-label="$t(stepMeta(sel.type).label)" />
              <p class="text-xs text-n-slate-10">{{ $t('TOLZAR_WORKFLOWS.SCORE_HINT') }}</p>
            </template>
          </template>

          <p v-else class="text-sm text-n-slate-10">{{ $t('TOLZAR_WORKFLOWS.PICK_HINT') }}</p>
        </div>
      </div>

      <!-- runs -->
      <div v-else-if="tab === 'runs'" class="overflow-auto flex-1 p-5">
        <div v-if="runsResult" class="flex flex-wrap gap-3 items-center max-w-[640px] mb-3">
          <div class="flex-1 min-w-[240px]"><BrainNotice :result="runsResult" /></div>
          <button type="button" :class="BTN_GHOST" @click="loadRuns()">{{ $t('TOLZAR_UI.RETRY') }}</button>
        </div>
        <div v-if="runsBusy && !runs.length" class="flex gap-2 items-center text-sm text-n-slate-10" role="status">
          <Spinner :size="18" /> {{ $t('TOLZAR_UI.LOADING') }}
        </div>
        <table v-if="runs.length" class="w-full text-sm">
          <thead>
            <tr class="text-xs text-start text-n-slate-10">
              <th class="py-2 font-medium text-start">{{ $t('TOLZAR_WORKFLOWS.RUN.CONTACT') }}</th>
              <th class="font-medium text-start">{{ $t('TOLZAR_WORKFLOWS.RUN.STARTED') }}</th>
              <th class="font-medium text-start">{{ $t('TOLZAR_WORKFLOWS.RUN.STATUS') }}</th>
              <th class="font-medium text-start">{{ $t('TOLZAR_WORKFLOWS.RUN.LAST') }}</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="r in runs" :key="r.id" class="border-t align-top border-n-weak">
              <td class="py-2">
                <router-link
                  v-if="r.contact_id"
                  :to="{ name: 'contacts_edit', params: { accountId, contactId: r.contact_id } }"
                  class="font-medium text-n-brand hover:underline"
                >
                  {{ contactName(r.contact_id) || $t('TOLZAR_WORKFLOWS_UI.RUN.CONTACT', { id: r.contact_id }) }}
                </router-link>
                <span v-else class="text-n-slate-10">{{ $t('TOLZAR_WORKFLOWS_UI.RUN.NO_CONTACT') }}</span>
                <router-link
                  v-if="r.conversation_id"
                  :to="{ name: 'inbox_conversation', params: { accountId, conversation_id: r.conversation_id } }"
                  class="block text-xs text-n-slate-10 hover:underline"
                >
                  {{ $t('TOLZAR_WORKFLOWS_UI.RUN.CONVERSATION', { id: r.conversation_id }) }}
                </router-link>
              </td>
              <td class="py-2 text-n-slate-11">{{ at(r.started_at) }}</td>
              <td class="py-2">
                <span class="inline-flex px-2 py-0.5 text-[11px] font-semibold rounded-full" :class="TONES[runTone(r.status)]">
                  {{ runStatusLabel(r.status) }}
                </span>
              </td>
              <td class="py-2 text-n-slate-11">
                <details>
                  <summary class="cursor-pointer list-none">
                    {{ ((r.log || [])[(r.log || []).length - 1] || {}).result || $t('TOLZAR_WORKFLOWS_UI.RUN.LOG_EMPTY') }}
                    <span v-if="(r.log || []).length > 1" class="text-xs text-n-brand"> · {{ $t('TOLZAR_WORKFLOWS_UI.RUN.LOG') }} ({{ r.log.length }})</span>
                  </summary>
                  <ol v-if="(r.log || []).length" class="ps-4 mt-1 mb-0 text-xs list-decimal text-n-slate-10">
                    <li v-for="(l, li) in r.log" :key="li">
                      <span class="text-n-slate-11">{{ $t(stepMeta(l.type).label) }}</span>: {{ l.result }}
                      <span v-if="l.at" class="text-n-slate-9"> · {{ at(l.at) }}</span>
                    </li>
                  </ol>
                </details>
              </td>
            </tr>
          </tbody>
        </table>
        <div v-if="runs.length" class="flex gap-3 items-center mt-3 text-xs text-n-slate-10">
          <span>{{ $t('TOLZAR_WORKFLOWS_UI.RUN.SHOWING', { n: runs.length }) }}</span>
          <button v-if="runs.length >= runsLimit" type="button" class="!mt-0 h-8" :class="BTN_GHOST" :disabled="runsBusy" @click="loadRuns(true)">
            <Spinner v-if="runsBusy" :size="14" />
            {{ $t('TOLZAR_WORKFLOWS_UI.RUN.LOAD_MORE') }}
          </button>
        </div>
        <p v-if="!runsBusy && !runsResult && !runs.length" class="text-n-slate-10">{{ $t('TOLZAR_WORKFLOWS.NO_RUNS') }}</p>
      </div>

      <!-- test -->
      <div v-else class="overflow-auto flex-1 p-5 max-w-[720px]">
        <p class="mt-0 text-sm text-n-slate-11">{{ $t('TOLZAR_WORKFLOWS.TEST_HINT') }}</p>
        <label class="!mt-0" :class="LABEL" for="tz-wf-contact-search">{{ $t('TOLZAR_WORKFLOWS_UI.TEST.SEARCH') }}</label>
        <div v-if="test.contactId" class="flex gap-2 items-center text-sm text-n-slate-12">
          <span class="px-2 py-0.5 rounded-full" :class="TONE_OK">{{ $t('TOLZAR_WORKFLOWS_UI.TEST.PICKED', { name: test.contactName }) }}</span>
          <button type="button" class="text-xs text-n-slate-10 hover:text-n-slate-12" @click="clearContact">{{ $t('TOLZAR_WORKFLOWS_UI.TEST.CLEAR') }}</button>
        </div>
        <div v-else class="relative max-w-[360px]">
          <input
            id="tz-wf-contact-search"
            :value="search.q"
            :class="INPUT"
            :placeholder="$t('TOLZAR_WORKFLOWS_UI.TEST.SEARCH_PLACEHOLDER')"
            autocomplete="off"
            @input="onSearch($event.target.value)"
          />
          <div v-if="search.busy" class="flex gap-1.5 items-center mt-1 text-xs text-n-slate-10"><Spinner :size="12" /> {{ $t('TOLZAR_WORKFLOWS_UI.TEST.SEARCHING') }}</div>
          <ul v-else-if="search.hits.length" class="overflow-hidden p-0 m-0 mt-1 list-none rounded-lg border border-n-weak bg-n-solid-1">
            <li v-for="c in search.hits" :key="c.id">
              <button type="button" class="block px-3 py-1.5 w-full text-sm text-start hover:bg-n-alpha-1 text-n-slate-12" @click="pickContact(c)">
                {{ c.name || `#${c.id}` }} <span class="text-xs text-n-slate-10">{{ c.email || c.phone_number || '' }}</span>
              </button>
            </li>
          </ul>
          <p v-else-if="search.done" class="mt-1 text-xs text-n-slate-10">{{ $t('TOLZAR_WORKFLOWS_UI.TEST.NO_MATCH') }}</p>
        </div>
        <label :class="LABEL" for="tz-wf-conv">{{ $t('TOLZAR_WORKFLOWS.CONVERSATION_ID') }}</label>
        <div class="flex flex-wrap gap-2 items-center">
          <input id="tz-wf-conv" v-model="test.conversationId" class="!w-[220px]" :class="INPUT" inputmode="numeric" :placeholder="$t('TOLZAR_WORKFLOWS.CONVERSATION_ID')" />
          <label class="flex gap-1.5 items-center text-sm text-n-slate-12">
            <input v-model="test.replied" type="checkbox" class="accent-n-brand" /> {{ $t('TOLZAR_WORKFLOWS.PRETEND_REPLY') }}
          </label>
          <button type="button" class="!mt-0 gap-2" :class="BTN" :disabled="test.busy" @click="runTest">
            <Spinner v-if="test.busy" :size="16" />
            {{ $t('TOLZAR_WORKFLOWS.RUN_TEST') }}
          </button>
        </div>
        <p class="mt-1 text-xs text-n-slate-10">{{ $t('TOLZAR_WORKFLOWS_UI.TEST.OR_CONVERSATION') }}</p>
        <BrainNotice :result="testResult" />
        <ol v-if="test.result && test.result.trace" class="mt-4 text-sm">
          <li v-for="(s, i) in test.result.trace" :key="i" class="mb-1.5">
            <b>{{ $t(stepMeta(s.type).label) }}</b>: <span class="text-n-slate-11">{{ s.result }}</span>
          </li>
        </ol>
        <div v-if="test.result && test.result.ok === false && (test.result.errors || []).length" class="p-2 mt-3 text-sm rounded-lg" :class="TONE_BAD">
          <div v-for="e in test.result.errors" :key="e">{{ e }}</div>
        </div>
      </div>

      <div class="px-[18px] py-2.5 border-t bg-n-solid-1 border-n-weak">
        <button v-if="!isNew" type="button" class="inline-flex gap-1 items-center text-xs text-n-slate-10 hover:text-n-ruby-11" @click="remove">
          <span class="i-lucide-trash-2 size-3.5" /> {{ $t('TOLZAR_WORKFLOWS.DELETE') }}
        </button>
        <div class="max-w-[640px]"><BrainNotice :result="removeResult" /></div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.tz-canvas {
  background-image: radial-gradient(rgba(100, 116, 139, 0.18) 1px, transparent 1px);
  background-size: 22px 22px;
}
</style>
