<script setup>
import { ref, computed, onMounted, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import CredentialInput from 'dashboard/components-next/Tolzar/settings/CredentialInput.vue';
import BrainNotice from 'dashboard/components-next/Tolzar/settings/BrainNotice.vue';
import PriceSourcePanel from 'dashboard/components-next/Tolzar/settings/PriceSourcePanel.vue';
import PriceUploadPanel from 'dashboard/components-next/Tolzar/settings/PriceUploadPanel.vue';
import SkillsPanel from 'dashboard/components-next/Tolzar/settings/SkillsPanel.vue';
import UnsavedDialog from 'dashboard/components-next/Tolzar/UnsavedDialog.vue';
import ConfirmDialog from 'dashboard/components-next/Tolzar/ConfirmDialog.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import {
  useUnsavedGuard,
  snapshot,
} from 'dashboard/components-next/Tolzar/useUnsavedGuard';
import {
  skillsFromAgent,
  skillsToAgent,
  blocksSave,
} from 'dashboard/components-next/Tolzar/tolzarSkills';
import { agentPrices } from 'dashboard/components-next/Tolzar/tolzarWorkspace';
import {
  BTN,
  BTN_GHOST,
  INPUT,
  TONE_WARN,
} from 'dashboard/components-next/Tolzar/settings/tzClasses';
import {
  getPriceKey,
  savePriceKey,
  clearPriceKey,
  credentialStatus,
} from 'dashboard/components-next/Tolzar/tolzarCredentials';
import {
  parseAgentTest,
  reasonLabels,
} from 'dashboard/components-next/Tolzar/tolzarAgentTest';

const accountId = useMapGetter('getCurrentAccountId');
const route = useRoute();
const router = useRouter();
const { t } = useI18n();

// --- AI Agents pillar. Configs are stored SERVER-SIDE by the brain
// (CRUD proxied through Chatwoot at /tolzar/agents); the brain reads the active agent and
// uses its instructions when it replies. No localStorage — shared across users + devices.
const EMOJIS = ['😇', '😎', '🤖', '✨', '💬', '📅', '🧭', '🛍️'];
const apiBase = computed(() => `/api/v1/accounts/${accountId.value}/tolzar`);
// Small secondary action (section headers); the primary and ghost buttons come from tzClasses.
const BTN_SOFT =
  'inline-flex gap-1 items-center px-3 py-1.5 text-[13px] font-semibold rounded-lg text-n-slate-11 bg-n-alpha-2 hover:bg-n-alpha-3 border-0 cursor-pointer disabled:opacity-50';
// The feed source type in the brain's shape (tolzarWorkspace.agentPrices); only it needs a key.
const FEED_TYPE = 'departures';

const agents = ref([]);
const selectedId = ref(null); // null = list view, else builder
const draft = ref(null); // editable copy while in builder
const loaded = ref(false);
const loadFailed = ref(false);

// Skills are proposals only (the brain writes "would do" notes, nothing is executed). The editor is
// usable; the badge says "Preview: proposals only" until the owner has reviewed it live.
const SKILLS_LIVE = true;
const skillsForm = ref(skillsFromAgent({}));
const skillsError = ref(false);
const defaultId = ref(null);
const unsavedRef = ref(null);
const confirmRef = ref(null);

// test chat (preview only — brain not connected yet)
const testMsgs = ref([]);
const testInput = ref('');

const uid = () => `a${crypto.randomUUID()}`;

// What the brain (or the proxy) answered: a refusal comes back as data ({ok: false, error}), so the
// page can say why (Owner-only, brain unreachable) instead of looking saved.
const listResult = ref(null);
const saveResult = ref(null);
const answer = request =>
  request
    .then(r => r.data || {})
    .catch(e => e?.response?.data || { ok: false, error: 'brain_unreachable' });
const brainPost = (path, body) => answer(window.axios.post(`${apiBase.value}/${path}`, body));
const refused = r => !r || r.ok === false || r.detail !== undefined;
const unreachable = r => !!r && r.error === 'brain_unreachable';
// The sidebar's AI Agents tree reloads when the stored list changes.
const announce = () => window.dispatchEvent(new Event('tolzar:agents-changed'));

async function load() {
  loaded.value = false;
  loadFailed.value = false;
  listResult.value = null;
  const data = await answer(window.axios.get(`${apiBase.value}/agents`));
  if (refused(data)) {
    agents.value = [];
    loadFailed.value = true;
    listResult.value = unreachable(data) ? null : data;
  } else {
    agents.value = Array.isArray(data.agents) ? data.agents : [];
    defaultId.value =
      data.default_id || (agents.value[0] && agents.value[0].id) || null;
  }
  loaded.value = true;
}

// id/name/description/instructions/knowledge/skills/status/emoji/generic, stored as-is.
const saveToServer = agent => brainPost('agents', { agent });

const busyId = ref(null); // the card whose Active / Default switch is in flight
async function setDefault(id) {
  if (busyId.value) return;
  const before = defaultId.value;
  defaultId.value = id;
  busyId.value = id;
  const r = await brainPost('agents/default', { id });
  busyId.value = null;
  listResult.value = refused(r) ? r : null;
  if (refused(r)) defaultId.value = before;
}
async function setStatus(a, on) {
  if (busyId.value) return;
  const before = a.status;
  a.status = on ? 'active' : 'inactive';
  busyId.value = a.id;
  const r = await saveToServer(a);
  busyId.value = null;
  listResult.value = refused(r) ? r : null;
  if (refused(r)) a.status = before;
}

const stored = computed(() => agents.value.find(a => a.id === selectedId.value) || null);

// Never lose edits: Back, Cancel, the sidebar tree (?agent=) and leaving the route all ask first.
// The skills editor keeps its own form, so it is compared against the stored agent's skills too.
const dirty = computed(() => {
  if (!draft.value || !stored.value) return false;
  if (snapshot(draft.value) !== snapshot(stored.value)) return true;
  return snapshot(skillsForm.value) !== snapshot(skillsFromAgent(stored.value));
});
const { guard } = useUnsavedGuard({
  isDirty: () => dirty.value,
  confirm: () => unsavedRef.value?.ask(),
});


// Price-feed key (brain plugins/price_credentials.py): write-only, stored encrypted per agent,
// never part of the agent's settings. Only its status ("Saved ••••1234") comes back.
const priceKey = ref('');
const priceStatus = ref({});
const priceResult = ref(null);
const priceSaved = ref('');
const priceBusy = ref(false);
const priceSource = computed(() => (draft.value?.generic || {}).prices || null);
const needsFeedKey = computed(() => priceSource.value?.type === FEED_TYPE);
async function loadPriceKey(id) {
  priceKey.value = '';
  priceStatus.value = {};
  priceResult.value = null;
  priceSaved.value = '';
  try {
    const r = await getPriceKey(accountId.value, id);
    if (r && r.ok && r.agent_id === id) priceStatus.value = credentialStatus(r, 'api_key');
  } catch (e) {
    /* non-fatal: the section shows "Not set" */
  }
}
async function priceKeyAction(fn, okText) {
  priceBusy.value = true;
  priceSaved.value = '';
  try {
    const r = await fn();
    priceResult.value = r;
    if (r && r.ok) {
      priceStatus.value = credentialStatus(r, 'api_key');
      priceKey.value = '';
      priceSaved.value = okText;
    }
  } catch (e) {
    priceResult.value = { ok: false, error: 'brain_unreachable' };
  } finally {
    priceBusy.value = false;
  }
}
// The price source was saved by the brain (Price source section): keep this editor's copy and the
// list's copy in step, so "Save" on the agent does not write the old source back.
function onPriceSourceSaved(source) {
  const prices = agentPrices(source, (draft.value?.generic || {}).prices);
  const put = a => {
    if (a) a.generic = { ...(a.generic || {}), prices };
  };
  put(draft.value);
  put(agents.value.find(a => a.id === draft.value?.id));
}
const savePrice = () =>
  priceKeyAction(
    () => savePriceKey(accountId.value, draft.value.id, priceKey.value),
    t('TOLZAR_SETTINGS.CHANNELS.CRED.KEY_SAVED')
  );
const removePrice = () =>
  priceKeyAction(
    () => clearPriceKey(accountId.value, draft.value.id),
    t('TOLZAR_SETTINGS.CHANNELS.CRED.REMOVED')
  );

const knowledgeResult = ref(null);
const knowledgeBusy = ref(false);

function openAgent(id) {
  saveResult.value = null;
  knowledgeResult.value = null;
  selectedId.value = id;
  draft.value = JSON.parse(JSON.stringify(agents.value.find(a => a.id === id)));
  skillsForm.value = skillsFromAgent(draft.value);
  skillsError.value = false;
  testMsgs.value = [];
  loadPriceKey(id);
}

// Ready-made, editable prompt templates from the brain (owner, 28 Oct: agents are configurable;
// behaviour comes from the instructions). A new agent starts inactive.
const templates = ref([]);
const BLANK_GENERIC = Object.freeze({
  enabled: true,
  answer_from_knowledge: true,
  quote_prices: false,
});

// The agent's behaviour switches (brain generic.py). An agent saved before these existed has no
// `generic`: switching one on gives it the workspace agent path.
const BEHAVIOUR_KEYS = ['enabled', 'answer_from_knowledge', 'quote_prices'];
const behaviour = computed(() => draft.value?.generic || {});
function setBehaviour(key, on) {
  draft.value.generic = {
    ...(draft.value.generic || { ...BLANK_GENERIC, teams: {} }),
    [key]: on,
  };
}
async function loadTemplates() {
  const data = await answer(window.axios.get(`${apiBase.value}/brain/agent_templates`));
  templates.value = refused(data) ? [] : data.templates || [];
}
// A new agent is listed only once the brain has stored it.
// One create or save at a time: a double click must not create two agents or send two saves.
const saving = ref(false);
async function addAgent(a) {
  if (saving.value) return;
  saving.value = true;
  const r = await saveToServer(a).finally(() => {
    saving.value = false;
  });
  listResult.value = refused(r) ? r : null;
  if (refused(r)) return;
  agents.value.push(a);
  announce();
  openAgent(a.id);
}

async function createFromTemplate(tpl, ev) {
  // Close the <details> menu after a pick.
  const d = ev?.target?.closest?.('details');
  if (d) d.open = false;
  const a = {
    id: uid(),
    name: tpl.name,
    emoji: '🤖',
    status: 'inactive',
    description: tpl.description,
    instructions: tpl.generic.instructions,
    knowledge: [],
    skills: [],
    template: tpl.id,
    generic: { enabled: true, ...JSON.parse(JSON.stringify(tpl.generic)), teams: {} },
  };
  await addAgent(a);
}


async function createAgent() {
  const a = {
    id: uid(),
    name: t('TOLZAR_AGENTS_UI.NEW_NAME'),
    emoji: '🤖',
    status: 'inactive',
    description: '',
    instructions: '',
    knowledge: [],
    skills: [],
    // The workspace agent path: answers from its knowledge; quotes prices once a source is saved.
    generic: { ...BLANK_GENERIC, teams: {} },
  };
  await addAgent(a);
}

function closeBuilder() {
  selectedId.value = null;
  draft.value = null;
  if (route.query?.agent) router.replace({ query: {} });
}
async function cancelEdit() {
  if (!(await guard())) return;
  closeBuilder();
}

async function saveAgent() {
  if (saving.value) return;
  // Skills switched on must be complete (the brain would skip a half-filled one silently).
  if (SKILLS_LIVE && blocksSave(skillsForm.value)) {
    skillsError.value = true;
    return;
  }
  // Skills in the brain's shape (agent_skills.py); an older draft is saved in the new shape.
  if (SKILLS_LIVE) Object.assign(draft.value, skillsToAgent(skillsForm.value));
  saveResult.value = null;
  const payload = JSON.parse(JSON.stringify(draft.value));
  // The instructions edited here are the generic agent's instructions too.
  if (payload.generic) payload.generic.instructions = payload.instructions;
  saving.value = true;
  const r = await saveToServer(payload).finally(() => {
    saving.value = false;
  });
  if (refused(r)) {
    // Keep the builder open with the edits; the list keeps what the brain has.
    saveResult.value = r;
    return;
  }
  const i = agents.value.findIndex(a => a.id === draft.value.id);
  if (i >= 0) agents.value[i] = JSON.parse(JSON.stringify(draft.value));
  announce();
  closeBuilder();
}

async function deleteAgent(id) {
  const a = agents.value.find(x => x.id === id);
  const ok = await confirmRef.value?.ask({
    title: t('TOLZAR_AGENTS_UI.DELETE_TITLE'),
    description: t('TOLZAR_AGENTS_UI.DELETE_BODY', { name: a?.name || '' }),
    confirmLabel: t('TOLZAR_AGENTS_UI.DELETE_CONFIRM'),
    cancelLabel: t('TOLZAR_UI.CANCEL'),
    danger: true,
  });
  if (!ok) return;
  const r = await brainPost('agents/delete', { id });
  if (refused(r)) {
    if (selectedId.value === id) saveResult.value = r;
    else listResult.value = r;
    return;
  }
  agents.value = agents.value.filter(x => x.id !== id);
  announce();
  if (selectedId.value === id) closeBuilder();
}

// Index the agent's links and texts now (the brain also does it daily). Uses the saved agent,
// so unsaved rows are saved first.
async function refreshKnowledge() {
  knowledgeBusy.value = true;
  knowledgeResult.value = null;
  const payload = JSON.parse(JSON.stringify(draft.value));
  if (payload.generic) payload.generic.instructions = payload.instructions;
  const saved = await saveToServer(payload);
  const r = refused(saved)
    ? saved
    : await brainPost('brain/knowledge_refresh', { id: draft.value.id });
  if (!refused(saved)) {
    // The brain has these rows now: the list copy follows, so the page is not "dirty" for them.
    const i = agents.value.findIndex(a => a.id === draft.value.id);
    if (i >= 0) agents.value[i] = JSON.parse(JSON.stringify(draft.value));
  }
  knowledgeResult.value = r;
  knowledgeBusy.value = false;
}
const knowledgeSaved = computed(() => {
  const r = knowledgeResult.value;
  if (r && !refused(r) && r.uploaded) {
    return t('TOLZAR_AGENTS_UI.DOC_INDEXED', {
      name: r.uploaded,
      total: r.total ?? 0,
    });
  }
  return knowledgeResult.value && !refused(knowledgeResult.value)
    ? t(
        'TOLZAR_AGENTS.KNOWLEDGE_INDEXED',
        { total: knowledgeResult.value.total ?? 0 },
        knowledgeResult.value.total ?? 0
      )
    : '';
});

function addKnowledge() {
  draft.value.knowledge.push({ type: 'url', label: '', value: '' });
}

// A knowledge document (PDF, DOCX, TXT/MD, HTML; Owner-only): the agent is saved first, the brain keeps
// only the extracted text as a source and indexes it, then the page takes the brain's copy of the agent.
const docInput = ref(null);
async function uploadDocument(event) {
  const file = event.target.files && event.target.files[0];
  event.target.value = '';
  if (!file || !draft.value) return;
  knowledgeBusy.value = true;
  knowledgeResult.value = null;
  const payload = JSON.parse(JSON.stringify(draft.value));
  if (payload.generic) payload.generic.instructions = payload.instructions;
  const saved = await saveToServer(payload);
  let r = saved;
  if (!refused(saved)) {
    const form = new FormData();
    form.append('file', file);
    r = await answer(
      window.axios.post(
        `${apiBase.value}/agents/${encodeURIComponent(draft.value.id)}/knowledge_upload`,
        form
      )
    );
    const data = await answer(window.axios.get(`${apiBase.value}/agents`));
    const fresh =
      !refused(data) && (data.agents || []).find(a => a.id === draft.value.id);
    if (fresh) {
      const i = agents.value.findIndex(a => a.id === fresh.id);
      if (i >= 0) agents.value[i] = JSON.parse(JSON.stringify(fresh));
      draft.value.knowledge = JSON.parse(JSON.stringify(fresh.knowledge || []));
    }
  }
  knowledgeResult.value = refused(r)
    ? r
    : { ok: true, total: r.chunks ?? 0, uploaded: r.source };
  knowledgeBusy.value = false;
}
function removeKnowledge(i) {
  draft.value.knowledge.splice(i, 1);
}

// Active / Default as one kind of control: a switch, a label and a one-line hint.
const activeOn = computed({
  get: () => draft.value?.status === 'active',
  set: on => {
    if (draft.value) draft.value.status = on ? 'active' : 'inactive';
  },
});
const isDefault = computed(() => !!draft.value && defaultId.value === draft.value.id);
const builderToggles = computed(() => [
  {
    key: 'active',
    label: t('TOLZAR_AGENTS_UI.ACTIVE'),
    hint: t('TOLZAR_AGENTS_UI.ACTIVE_HINT'),
    on: activeOn.value,
    disabled: false,
    set: v => {
      activeOn.value = v;
    },
  },
  {
    key: 'default',
    label: t('TOLZAR_AGENTS_UI.DEFAULT'),
    hint: isDefault.value ? t('TOLZAR_AGENTS_UI.IS_DEFAULT') : t('TOLZAR_AGENTS_UI.DEFAULT_HINT'),
    on: isDefault.value,
    disabled: isDefault.value || busyId.value !== null,
    set: v => {
      if (v) setDefault(draft.value.id);
    },
  },
]);

const testBusy = ref(false);
const copied = ref(false);
async function sendTest() {
  const text = testInput.value.trim();
  if (!text || testBusy.value) return;
  testMsgs.value.push({ who: 'user', text });
  testInput.value = '';
  testBusy.value = true;
  const thinking = { who: 'agent', text: t('TOLZAR_AGENTS_UI.THINKING'), pending: true };
  testMsgs.value.push(thinking);
  const history = testMsgs.value
    .filter(m => !m.pending)
    .slice(-9, -1)
    .map(m => ({ role: m.who === 'user' ? 'user' : 'assistant', content: m.text }));
  const drop = () => {
    const i = testMsgs.value.indexOf(thinking);
    if (i >= 0) testMsgs.value.splice(i, 1);
  };
  try {
    const { data } = await window.axios.post(
      `/api/v1/accounts/${accountId.value}/tolzar/agent_test`,
      {
        message: text,
        instructions: draft.value?.instructions || '',
        agent_id: draft.value?.id || '',
        history,
      }
    );
    drop();
    // The bubble is the final reply (what Shadow would send); a replaced draft rides along.
    const msg = parseAgentTest(data);
    testMsgs.value.push({ ...msg, text: msg.text || t('TOLZAR_AGENTS_UI.NO_REPLY') });
  } catch (e) {
    drop();
    testMsgs.value.push({ who: 'agent', text: t('TOLZAR_AGENTS_UI.NETWORK_ERROR') });
  } finally {
    testBusy.value = false;
  }
}
function onTestKey(ev) {
  // Enter sends; Enter while an IME is composing (Japanese, Chinese, ...) only commits the text.
  if (ev.isComposing) return;
  sendTest();
}
async function copyTranscript() {
  const lines = testMsgs.value
    .filter(m => !m.pending)
    .map(m => `${m.who === 'user' ? t('TOLZAR_AGENTS_UI.YOU') : t('TOLZAR_AGENTS_UI.AGENT')}: ${m.text}`);
  try {
    await navigator.clipboard.writeText(lines.join('\n'));
    copied.value = true;
    setTimeout(() => {
      copied.value = false;
    }, 1500);
  } catch (e) {
    /* clipboard blocked: nothing to say, the text stays on screen */
  }
}

// ?agent=<id> (the sidebar tree) opens that agent's builder. With unsaved edits it asks first and,
// on "Stay", puts the URL back on the open agent.
const openFromRoute = async () => {
  const id = route.query?.agent ? String(route.query.agent) : '';
  if (!id || id === selectedId.value || !agents.value.some(a => a.id === id)) return;
  if (draft.value && !(await guard())) {
    router.replace({ query: { agent: selectedId.value } });
    return;
  }
  openAgent(id);
};
watch(() => route.query?.agent, openFromRoute);

const defaultName = computed(
  () => (agents.value.find(x => x.id === defaultId.value) || {}).name || t('TOLZAR_AGENTS_UI.NONE')
);

onMounted(async () => {
  loadTemplates();
  await load();
  openFromRoute();
});
</script>

<template>
  <div class="overflow-auto flex-1 bg-n-background" data-tz-build="ai-agents-ux-r2">
    <UnsavedDialog ref="unsavedRef" />
    <ConfirmDialog ref="confirmRef" />

    <!-- ===================== LIST VIEW ===================== -->
    <div v-if="!selectedId" class="mx-auto max-w-[1120px] px-5 pb-16 pt-7 md:px-6">
      <div class="flex gap-4 justify-between items-start tz-rise">
        <div class="flex gap-3 items-center">
          <span class="grid flex-shrink-0 place-content-center rounded-2xl shadow-md size-11 bg-n-brand">
            <span class="i-lucide-bot size-6 text-white" />
          </span>
          <div>
            <h1 class="m-0 text-[22px] font-extrabold tracking-tight text-n-slate-12">{{ t('TOLZAR_AGENTS_UI.TITLE') }}</h1>
            <p class="m-0 text-sm text-n-slate-11">{{ t('TOLZAR_AGENTS_UI.LEAD') }}</p>
          </div>
        </div>
        <div class="flex gap-2 items-center">
          <details class="relative">
            <summary class="!mt-0 gap-1.5 list-none" :class="BTN_GHOST">
              <span class="i-lucide-layout-template size-4" /> {{ t('TOLZAR_AGENTS_UI.FROM_TEMPLATE') }}
            </summary>
            <div class="absolute z-20 p-1.5 mt-1 w-[340px] rounded-xl border shadow-lg ltr:right-0 rtl:left-0 bg-n-solid-1 border-n-weak">
              <button
                v-for="tpl in templates"
                :key="tpl.id"
                type="button"
                class="block px-3 py-2 w-full rounded-lg text-start hover:bg-n-alpha-1 disabled:opacity-50"
                :disabled="saving"
                @click="createFromTemplate(tpl, $event)"
              >
                <div class="text-[13px] font-semibold text-n-slate-12">{{ tpl.name }}</div>
                <div class="text-xs text-n-slate-10">{{ tpl.description }}</div>
              </button>
              <p v-if="!templates.length" class="px-3 py-2 m-0 text-xs text-n-slate-10">{{ t('TOLZAR_AGENTS_UI.NO_TEMPLATES') }}</p>
            </div>
          </details>
          <button type="button" class="!mt-0 gap-2" :class="BTN" :disabled="saving || !loaded" @click="createAgent">
            <Spinner v-if="saving" :size="16" />
            <span v-else class="i-lucide-plus size-4" />
            {{ t('TOLZAR_AGENTS_UI.CREATE') }}
          </button>
        </div>
      </div>
      <div class="max-w-[640px]">
        <BrainNotice :result="listResult" />
        <div v-if="loadFailed" class="flex flex-wrap gap-3 items-center p-2 mt-3 text-[13px] rounded-lg text-n-ruby-11 bg-n-ruby-9/10" role="alert">
          <span class="flex-1">{{ t('TOLZAR_UI.LOAD_FAILED') }}</span>
          <button type="button" class="!mt-0 h-8" :class="BTN_GHOST" @click="load">{{ t('TOLZAR_UI.RETRY') }}</button>
        </div>
      </div>

      <div v-if="loaded && !loadFailed" class="tz-rise [animation-delay:60ms] flex gap-2.5 items-center mt-4 px-3.5 py-2.5 text-xs rounded-xl border border-n-weak bg-n-alpha-1 text-n-slate-11">
        <span class="i-lucide-sparkles size-4 text-n-brand" />
        <span>{{ t('TOLZAR_AGENTS_UI.DEFAULT_LINE', { name: defaultName }) }}</span>
      </div>

      <!-- skeleton while the brain answers: the list is never mistaken for "no agents" -->
      <div v-if="!loaded" class="grid gap-4 mt-6 grid-cols-[repeat(auto-fill,minmax(320px,1fr))]" role="status" :aria-label="t('TOLZAR_AGENTS_UI.LOADING')">
        <div v-for="n in 3" :key="n" class="p-[18px] rounded-2xl border animate-pulse bg-n-solid-1 border-n-weak">
          <div class="flex gap-2.5 items-center">
            <div class="rounded-xl size-11 bg-n-alpha-2" />
            <div class="flex-1">
              <div class="h-3.5 rounded w-2/3 bg-n-alpha-2" />
              <div class="mt-2 h-3 rounded w-1/3 bg-n-alpha-2" />
            </div>
          </div>
          <div class="mt-4 h-3 rounded bg-n-alpha-2" />
          <div class="mt-2 h-3 rounded w-4/5 bg-n-alpha-2" />
        </div>
      </div>

      <div v-else class="grid gap-4 mt-6 grid-cols-[repeat(auto-fill,minmax(320px,1fr))]">
        <div
          v-for="(a, i) in agents"
          :key="a.id"
          role="button"
          tabindex="0"
          class="tz-rise tz-hover p-[18px] rounded-2xl border shadow-sm cursor-pointer bg-n-solid-1 border-n-weak outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
          :style="{ animationDelay: 100 + i * 50 + 'ms' }"
          @click="openAgent(a.id)"
          @keydown.enter.prevent="openAgent(a.id)"
        >
          <div class="flex gap-2.5 items-center">
            <div class="grid place-content-center text-2xl rounded-xl size-11 bg-n-alpha-2">{{ a.emoji }}</div>
            <div class="flex-1 min-w-0">
              <div class="flex gap-1.5 items-center">
                <span class="font-bold truncate text-n-slate-12">{{ a.name }}</span>
                <span v-if="defaultId === a.id" class="px-1.5 py-px text-[10px] font-bold uppercase rounded-full" :class="TONE_WARN">{{ t('TOLZAR_AGENTS_UI.DEFAULT') }}</span>
              </div>
              <span class="inline-block mt-1 text-[11px] font-bold" :class="a.status === 'active' ? 'text-n-brand' : 'text-n-slate-11'">
                {{ a.status === 'active' ? t('TOLZAR_AGENTS_UI.ACTIVE') : t('TOLZAR_AGENTS_UI.INACTIVE') }}
              </span>
            </div>
          </div>
          <p class="mt-3 mb-0 text-[13px] text-n-slate-11 min-h-[34px]">{{ a.description || t('TOLZAR_AGENTS_UI.NO_DESCRIPTION') }}</p>
          <div class="flex flex-wrap gap-3 justify-between items-center pt-3 mt-3 border-t border-n-weak" @click.stop @keydown.enter.stop>
            <!-- the same switch + label + hint as the builder header -->
            <label class="flex gap-2 items-center text-xs text-n-slate-11" :title="t('TOLZAR_AGENTS_UI.ACTIVE_HINT')">
              <Switch
                :model-value="a.status === 'active'"
                :disabled="busyId !== null"
                :aria-label="t('TOLZAR_AGENTS_UI.TOGGLE_ACTIVE', { name: a.name, state: a.status === 'active' ? t('TOLZAR_AGENTS_UI.STATE_OFF') : t('TOLZAR_AGENTS_UI.STATE_ON') })"
                @update:model-value="v => setStatus(a, v)"
              />
              {{ t('TOLZAR_AGENTS_UI.ACTIVE') }}
            </label>
            <label class="flex gap-2 items-center text-xs text-n-slate-11" :title="defaultId === a.id ? t('TOLZAR_AGENTS_UI.IS_DEFAULT') : t('TOLZAR_AGENTS_UI.DEFAULT_HINT')">
              <Switch
                :model-value="defaultId === a.id"
                :disabled="defaultId === a.id || busyId !== null"
                @update:model-value="v => v && setDefault(a.id)"
              />
              {{ t('TOLZAR_AGENTS_UI.DEFAULT') }}
            </label>
            <span class="inline-flex gap-1 items-center text-[13px] font-bold text-n-brand">{{ t('TOLZAR_AGENTS_UI.EDIT') }} <span class="i-lucide-arrow-right size-3.5 rtl:rotate-180" /></span>
          </div>
        </div>

        <button
          type="button"
          class="tz-rise flex flex-col gap-1 justify-center items-center text-center rounded-2xl border border-dashed transition-colors cursor-pointer border-n-strong min-h-[128px] text-n-slate-11 hover:border-n-brand hover:bg-n-alpha-1 disabled:opacity-50"
          :disabled="saving"
          @click="createAgent"
        >
          <span class="grid place-content-center mb-1 rounded-xl size-9 bg-n-alpha-2"><span class="i-lucide-plus size-5 text-n-brand" /></span>
          <span class="font-bold text-n-slate-12">{{ t('TOLZAR_AGENTS_UI.CREATE_CARD') }}</span>
          <span class="text-xs">{{ t('TOLZAR_AGENTS_UI.CREATE_CARD_HINT') }}</span>
        </button>
      </div>
    </div>

    <!-- ===================== BUILDER VIEW ===================== -->
    <div v-else-if="draft" class="mx-auto max-w-[1240px] px-5 pb-16 pt-5 md:px-6">
      <!-- header -->
      <div class="flex flex-wrap gap-3 items-center mb-4">
        <button type="button" class="!mt-0" :class="BTN_GHOST" @click="cancelEdit"><span class="i-lucide-chevron-left size-4 rtl:rotate-180" /> {{ t('TOLZAR_AGENTS_UI.BACK') }}</button>
        <div class="flex flex-wrap gap-1 max-w-[230px]" role="radiogroup" :aria-label="t('TOLZAR_AGENTS_UI.AVATAR', { emoji: draft.emoji })">
          <button
            v-for="e in EMOJIS"
            :key="e"
            type="button"
            role="radio"
            class="px-1.5 py-1 text-lg leading-none rounded-lg border transition-colors bg-n-solid-1"
            :class="draft.emoji === e ? 'border-n-brand ring-1 ring-n-brand' : 'border-n-weak'"
            :aria-checked="draft.emoji === e"
            :aria-label="t('TOLZAR_AGENTS_UI.AVATAR', { emoji: e })"
            @click="draft.emoji = e"
          >{{ e }}</button>
        </div>
        <input
          v-model="draft.name"
          :aria-label="t('TOLZAR_AGENTS_UI.NAME_LABEL')"
          class="flex-1 px-2 py-1 min-w-0 text-lg font-extrabold rounded-lg border border-transparent outline-none text-n-slate-12 bg-n-background focus:border-n-weak"
        />
        <label
          v-for="tg in builderToggles"
          :key="tg.key"
          class="flex gap-2 items-center text-[13px] text-n-slate-12"
          :title="tg.hint"
        >
          <Switch :model-value="tg.on" :disabled="tg.disabled" @update:model-value="tg.set" />
          <span>
            {{ tg.label }}
            <span class="block text-[11px] leading-tight text-n-slate-10">{{ tg.hint }}</span>
          </span>
        </label>
        <button type="button" class="!mt-0" :class="BTN_GHOST" @click="cancelEdit">{{ t('TOLZAR_AGENTS_UI.CANCEL') }}</button>
        <button type="button" class="!mt-0 gap-2" :class="BTN" :disabled="saving" @click="saveAgent">
          <Spinner v-if="saving" :size="16" />
          <span v-else class="i-lucide-check size-4" />
          {{ saving ? t('TOLZAR_AGENTS_UI.SAVING') : t('TOLZAR_AGENTS_UI.SAVE') }}
        </button>
      </div>
      <div class="max-w-[640px] -mt-2 mb-3">
        <BrainNotice :result="saveResult" />
      </div>

      <div class="grid gap-[18px] items-start grid-cols-1 lg:grid-cols-[1fr_380px]">
        <!-- left: config -->
        <div class="grid gap-4">
          <!-- Instructions -->
          <section class="p-[18px] rounded-2xl border shadow-sm bg-n-solid-1 border-n-weak">
            <h3 class="mb-1 text-[15px] font-semibold text-n-slate-12"><label for="tz-agent-instructions">{{ t('TOLZAR_AGENTS_UI.INSTRUCTIONS') }}</label></h3>
            <p class="mt-0 mb-2.5 text-xs text-n-slate-11">{{ t('TOLZAR_AGENTS_UI.INSTRUCTIONS_HINT') }}</p>
            <textarea
              id="tz-agent-instructions"
              v-model="draft.instructions"
              rows="12"
              class="box-border p-3 w-full font-mono text-[12.5px] leading-relaxed rounded-xl border outline-none resize-y border-n-weak bg-n-background text-n-slate-12 focus:border-n-brand"
              :placeholder="t('TOLZAR_AGENTS_UI.INSTRUCTIONS_PLACEHOLDER')"
            />
          </section>

          <!-- Behaviour switches (brain generic.py) -->
          <section class="p-[18px] rounded-2xl border shadow-sm bg-n-solid-1 border-n-weak" data-tz-behaviour>
            <h3 class="mb-1 text-[15px] font-semibold text-n-slate-12">{{ t('TOLZAR_AGENTS.BEHAVIOUR') }}</h3>
            <p class="mt-0 mb-2.5 text-xs text-n-slate-11">{{ t('TOLZAR_AGENTS.BEHAVIOUR_HINT') }}</p>
            <label
              v-for="k in BEHAVIOUR_KEYS"
              :key="k"
              class="flex gap-2 items-start mb-2 text-[13px] text-n-slate-12"
              :class="k !== 'enabled' && !behaviour.enabled ? 'opacity-60' : ''"
            >
              <input
                type="checkbox"
                class="mt-0.5 accent-n-brand"
                :checked="!!behaviour[k]"
                :disabled="k !== 'enabled' && !behaviour.enabled"
                @change="setBehaviour(k, $event.target.checked)"
              />
              <span>
                {{ t(`TOLZAR_AGENTS.SWITCH.${k}`) }}
                <span class="block text-xs text-n-slate-10">{{ t(`TOLZAR_AGENTS.SWITCH_HINT.${k}`) }}</span>
              </span>
            </label>
          </section>

          <!-- Description -->
          <section class="p-[18px] rounded-2xl border shadow-sm bg-n-solid-1 border-n-weak">
            <h3 class="mb-2.5 text-[15px] font-semibold text-n-slate-12"><label for="tz-agent-description">{{ t('TOLZAR_AGENTS_UI.DESCRIPTION') }}</label></h3>
            <input id="tz-agent-description" v-model="draft.description" :class="INPUT" :placeholder="t('TOLZAR_AGENTS_UI.DESCRIPTION_PLACEHOLDER')" />
          </section>

          <!-- Knowledge sources -->
          <section class="p-[18px] rounded-2xl border shadow-sm bg-n-solid-1 border-n-weak">
            <div class="flex flex-wrap gap-2 justify-between items-center">
              <h3 class="m-0 text-[15px] font-semibold text-n-slate-12">{{ t('TOLZAR_AGENTS_UI.KNOWLEDGE') }}</h3>
              <div class="flex gap-2">
                <button type="button" :class="BTN_SOFT" :disabled="knowledgeBusy || !draft.knowledge.length" @click="refreshKnowledge">
                  <Spinner v-if="knowledgeBusy" :size="14" />
                  <span v-else class="i-lucide-refresh-cw size-3.5" />
                  {{ knowledgeBusy ? t('TOLZAR_AGENTS.INDEXING') : t('TOLZAR_AGENTS.INDEX_NOW') }}
                </button>
                <button type="button" :class="BTN_SOFT" :disabled="knowledgeBusy" @click="docInput && docInput.click()"><span class="i-lucide-file-up size-3.5" /> {{ t('TOLZAR_AGENTS_UI.UPLOAD_DOC') }}</button>
                <input ref="docInput" type="file" class="hidden" accept=".pdf,.docx,.txt,.md,.html,.htm" @change="uploadDocument" />
                <button type="button" :class="BTN_SOFT" @click="addKnowledge"><span class="i-lucide-plus size-3.5" /> {{ t('TOLZAR_AGENTS_UI.ADD') }}</button>
              </div>
            </div>
            <p class="mt-1.5 mb-3 text-xs text-n-slate-11">{{ t('TOLZAR_AGENTS_UI.KNOWLEDGE_HINT') }}</p>
            <div v-if="!draft.knowledge.length" class="text-[13px] text-n-slate-10">{{ t('TOLZAR_AGENTS_UI.KNOWLEDGE_EMPTY') }}</div>
            <p v-if="draft.knowledge.length && !behaviour.answer_from_knowledge" class="mt-0 mb-2 text-xs text-n-amber-11">{{ t('TOLZAR_AGENTS.KNOWLEDGE_OFF') }}</p>
            <div v-for="(k, i) in draft.knowledge" :key="i" class="flex flex-wrap gap-2 items-center mb-2">
              <template v-if="k.file">
                <span class="i-lucide-file-text size-4 text-n-slate-10" />
                <span class="flex-1 text-[13px] text-n-slate-12 truncate">{{ k.file.name }}</span>
                <span class="text-xs text-n-slate-10">{{ t('TOLZAR_AGENTS_UI.DOC_META', { chars: k.file.chars || 0 }) }}</span>
              </template>
              <select v-if="!k.file" v-model="k.type" class="!w-auto" :class="INPUT" :aria-label="t('TOLZAR_AGENTS_UI.SOURCE_TYPE')">
                <option value="url">{{ t('TOLZAR_AGENTS_UI.TYPE_URL') }}</option>
                <option value="text">{{ t('TOLZAR_AGENTS_UI.TYPE_TEXT') }}</option>
                <!-- File sources are not read by the brain yet; an old row stays visible to remove. -->
                <option v-if="k.type === 'file'" value="file" disabled>{{ t('TOLZAR_AGENTS_UI.TYPE_FILE') }}</option>
              </select>
              <input v-if="!k.file" v-model="k.label" :placeholder="t('TOLZAR_AGENTS_UI.LABEL')" :aria-label="t('TOLZAR_AGENTS_UI.LABEL')" class="!w-[120px]" :class="INPUT" />
              <input
                v-if="!k.file"
                v-model="k.value"
                :placeholder="k.type === 'text' ? t('TOLZAR_AGENTS_UI.TEXT_PLACEHOLDER') : t('TOLZAR_AGENTS_UI.URL_PLACEHOLDER')"
                :aria-label="k.type === 'text' ? t('TOLZAR_AGENTS_UI.TYPE_TEXT') : t('TOLZAR_AGENTS_UI.TYPE_URL')"
                class="flex-1 !w-auto min-w-[160px]"
                :class="INPUT"
              />
              <button
                type="button"
                class="grid place-content-center rounded-lg transition-colors size-7 text-n-slate-10 hover:text-n-ruby-11 hover:bg-n-alpha-2"
                :aria-label="t('TOLZAR_AGENTS_UI.REMOVE_SOURCE')"
                :title="t('TOLZAR_AGENTS_UI.REMOVE_SOURCE')"
                @click="removeKnowledge(i)"
              >
                <span class="i-lucide-x size-4" />
              </button>
            </div>
            <BrainNotice :result="knowledgeResult" :saved="knowledgeSaved" />
          </section>

          <!-- Prices: only when the agent quotes them; the feed key only for a feed source -->
          <template v-if="behaviour.quote_prices">
            <PriceSourcePanel :agent-id="draft.id" @saved="onPriceSourceSaved" />
            <PriceUploadPanel :agent-id="draft.id" @saved="onPriceSourceSaved" />
            <section v-if="needsFeedKey" class="p-[18px] rounded-2xl border shadow-sm bg-n-solid-1 border-n-weak" data-tz-price-key>
              <h3 class="m-0 text-[15px] font-semibold text-n-slate-12">{{ t('TOLZAR_SETTINGS.CHANNELS.CRED.PRICES_TITLE') }}</h3>
              <p class="mt-1.5 mb-0 text-xs text-n-slate-11">{{ t('TOLZAR_SETTINGS.CHANNELS.CRED.PRICES_HINT') }}</p>
              <p class="mt-1.5 mb-0 text-xs break-all text-n-slate-10">
                {{ t('TOLZAR_SETTINGS.CHANNELS.CRED.PRICES_SOURCE', { type: priceSource.type || '', value: priceSource.value || '' }) }}
              </p>
              <div class="max-w-[420px]">
                <CredentialInput
                  v-model="priceKey"
                  :label="t('TOLZAR_SETTINGS.CHANNELS.CRED.prices_api_key')"
                  :status="priceStatus"
                  :busy="priceBusy"
                  @remove="removePrice"
                />
                <button type="button" :class="BTN" :disabled="priceBusy || !priceKey.trim()" @click="savePrice">
                  {{ t('TOLZAR_SETTINGS.CHANNELS.CRED.SAVE_KEY') }}
                </button>
              </div>
              <BrainNotice :result="priceResult" :saved="priceSaved" />
            </section>
          </template>
          <p v-else class="px-3.5 py-2.5 m-0 text-xs rounded-xl border border-n-weak bg-n-alpha-1 text-n-slate-11">
            {{ t('TOLZAR_AGENTS_UI.PRICES_OFF', { switch: t('TOLZAR_AGENTS.SWITCH.quote_prices') }) }}
          </p>

          <!-- AI skills: proposals only ("would do" notes); nothing is executed -->
          <SkillsPanel
            :key="draft.id"
            v-model="skillsForm"
            :live="SKILLS_LIVE"
          />
          <p v-if="skillsError" class="m-0 text-xs text-n-ruby-11" role="alert">
            {{ t('TOLZAR_SKILLS.SAVE_BLOCKED') }}
          </p>
        </div>

        <!-- right: test -->
        <section class="sticky top-4 p-4 rounded-2xl border shadow-sm bg-n-solid-1 border-n-weak">
          <div class="flex flex-wrap gap-2 justify-between items-center mb-2">
            <h3 class="inline-flex gap-1.5 items-center m-0 text-[15px] font-semibold text-n-slate-12"><span class="i-lucide-message-circle size-4 text-n-brand" /> {{ t('TOLZAR_AGENTS_UI.TEST') }}</h3>
            <div class="flex gap-3 items-center">
              <button
                v-if="testMsgs.length"
                type="button"
                class="inline-flex gap-1 items-center text-xs transition-colors text-n-slate-10 hover:text-n-slate-12"
                @click="copyTranscript"
              >
                <span class="i-lucide-copy size-3.5" /> {{ copied ? t('TOLZAR_AGENTS_UI.COPIED') : t('TOLZAR_AGENTS_UI.COPY_TRANSCRIPT') }}
              </button>
              <button type="button" class="text-xs transition-colors text-n-slate-10 hover:text-n-slate-12" @click="testMsgs = []">{{ t('TOLZAR_AGENTS_UI.RESET_CHAT') }}</button>
            </div>
          </div>
          <div class="flex gap-2 items-start px-2.5 py-2 mb-2.5 text-[11.5px] rounded-lg border text-n-brand bg-n-brand/10 border-n-brand/20">
            <span class="flex-shrink-0 mt-0.5 i-lucide-circle-check size-3.5" />
            <span>{{ t('TOLZAR_AGENTS_UI.TEST_NOTE') }}</span>
          </div>
          <div class="flex overflow-auto flex-col gap-2 p-2.5 h-[300px] rounded-xl border border-n-weak bg-n-background" aria-live="polite">
            <div v-if="!testMsgs.length" class="m-auto text-[12.5px] text-center text-n-slate-10">{{ t('TOLZAR_AGENTS_UI.TEST_EMPTY') }}</div>
            <div
              v-for="(m, i) in testMsgs"
              :key="i"
              class="max-w-[85%]"
              :class="m.who === 'user' ? 'self-end' : 'self-start'"
            >
              <div
                class="px-2.5 py-2 text-[12.5px] leading-snug rounded-xl"
                :class="[
                  m.who === 'user' ? 'bg-n-brand text-white' : 'bg-n-alpha-2 text-n-slate-12',
                  m.pending ? 'italic opacity-70' : '',
                ]"
              >{{ m.text }}</div>
              <div v-if="m.replaced" class="mt-1 text-[11px] text-n-slate-11">
                <p class="m-0">{{ t('TOLZAR_AGENT_TEST.REPLACED') }}</p>
                <details class="mt-0.5">
                  <summary class="cursor-pointer text-n-slate-10">{{ t('TOLZAR_AGENT_TEST.MODEL_DRAFT') }}</summary>
                  <div class="px-2 py-1.5 mt-1 whitespace-pre-wrap rounded-lg bg-n-alpha-1 text-n-slate-11">{{ m.draft }}</div>
                  <ul v-if="m.reasons.length" class="pl-4 mt-1 mb-0 list-disc text-n-slate-10">
                    <li v-for="r in reasonLabels(m.reasons, t)" :key="r">{{ r }}</li>
                  </ul>
                </details>
              </div>
              <div v-if="m.meta" class="mt-0.5 text-[10px] text-n-slate-10">{{ m.meta }}</div>
            </div>
          </div>
          <div class="flex gap-2 mt-2.5">
            <input
              v-model="testInput"
              :disabled="testBusy"
              :placeholder="t('TOLZAR_AGENTS_UI.TEST_PLACEHOLDER')"
              :aria-label="t('TOLZAR_AGENTS_UI.TEST_PLACEHOLDER')"
              class="flex-1 !w-auto"
              :class="INPUT"
              @keyup.enter.exact="onTestKey"
            />
            <button type="button" :disabled="testBusy || !testInput.trim()" class="!mt-0 !px-3.5 gap-1.5" :class="BTN" @click="sendTest">
              <Spinner v-if="testBusy" :size="14" />
              {{ testBusy ? t('TOLZAR_AGENTS_UI.SENDING') : t('TOLZAR_AGENTS_UI.SEND') }}
            </button>
          </div>
        </section>
      </div>

      <button type="button" class="inline-flex gap-1 items-center mt-5 text-xs transition-colors text-n-slate-10 hover:text-n-ruby-11" @click="deleteAgent(draft.id)">
        <span class="i-lucide-trash-2 size-3.5" /> {{ t('TOLZAR_AGENTS_UI.DELETE') }}
      </button>
    </div>
  </div>
</template>

<style scoped>
.tz-hover {
  transition: transform 0.18s ease, box-shadow 0.18s ease;
}
.tz-hover:hover {
  transform: translateY(-2px);
  box-shadow: 0 12px 26px -14px rgba(15, 23, 42, 0.28);
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
