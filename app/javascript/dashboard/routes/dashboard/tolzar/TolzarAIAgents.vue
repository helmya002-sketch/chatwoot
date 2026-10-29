<script setup>
import { ref, computed, onMounted, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import CredentialInput from 'dashboard/components-next/Tolzar/settings/CredentialInput.vue';
import BrainNotice from 'dashboard/components-next/Tolzar/settings/BrainNotice.vue';
import PriceSourcePanel from 'dashboard/components-next/Tolzar/settings/PriceSourcePanel.vue';
import PriceUploadPanel from 'dashboard/components-next/Tolzar/settings/PriceUploadPanel.vue';
import SkillsPanel from 'dashboard/components-next/Tolzar/settings/SkillsPanel.vue';
import {
  skillsFromAgent,
  skillsToAgent,
  blocksSave,
} from 'dashboard/components-next/Tolzar/tolzarSkills';
import { agentPrices } from 'dashboard/components-next/Tolzar/tolzarWorkspace';
import { BTN } from 'dashboard/components-next/Tolzar/settings/tzClasses';
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
const { t } = useI18n();

// --- AI Agents pillar. Configs are stored SERVER-SIDE by the brain
// (CRUD proxied through Chatwoot at /tolzar/agents); the brain reads the active agent and
// uses its instructions when it replies. No localStorage — shared across users + devices.
const EMOJIS = ['😇', '😎', '🤖', '✨', '💬', '📅', '🧭', '🛍️'];
const apiBase = computed(() => `/api/v1/accounts/${accountId.value}/tolzar`);

const agents = ref([]);
const selectedId = ref(null); // null = list view, else builder
const draft = ref(null); // editable copy while in builder
const loaded = ref(false);

// Skills are proposals only (the brain writes "would do" notes, nothing is executed). The editor is
// usable; the badge says "Preview: proposals only" until the owner has reviewed it live.
const SKILLS_LIVE = true;
const skillsForm = ref(skillsFromAgent({}));
const skillsError = ref(false);
const defaultId = ref(null);

// test chat (preview only — brain not connected yet)
const testMsgs = ref([]);
const testInput = ref('');

function uid() {
  return 'a' + Math.random().toString(36).slice(2, 9);
}

async function load() {
  try {
    const { data } = await window.axios.get(`${apiBase.value}/agents`);
    agents.value = Array.isArray(data.agents) ? data.agents : [];
    defaultId.value =
      data.default_id || (agents.value[0] && agents.value[0].id) || null;
  } catch (e) {
    agents.value = [];
  }
  loaded.value = true;
}

// What the brain (or the proxy) answered: a refusal comes back as data ({ok: false, error}), so the
// page can say why (Owner-only, brain unreachable) instead of looking saved.
const listResult = ref(null);
const saveResult = ref(null);
async function brainPost(path, body) {
  try {
    const { data } = await window.axios.post(`${apiBase.value}/${path}`, body);
    return data || {};
  } catch (e) {
    return e?.response?.data || { ok: false, error: 'brain_unreachable' };
  }
}
const refused = r => !r || r.ok === false || r.detail !== undefined;
// The sidebar's AI Agents tree reloads when the stored list changes.
const announce = () => window.dispatchEvent(new Event('tolzar:agents-changed'));

// id/name/description/instructions/knowledge/skills/status/emoji/generic, stored as-is.
const saveToServer = agent => brainPost('agents', { agent });

async function setDefault(id, ev) {
  if (ev) ev.stopPropagation();
  const before = defaultId.value;
  defaultId.value = id;
  const r = await brainPost('agents/default', { id });
  listResult.value = refused(r) ? r : null;
  if (refused(r)) defaultId.value = before;
}
async function toggleStatus(a, ev) {
  if (ev) ev.stopPropagation();
  const before = a.status;
  a.status = a.status === 'active' ? 'inactive' : 'active';
  const r = await saveToServer(a);
  listResult.value = refused(r) ? r : null;
  if (refused(r)) a.status = before;
}

const selected = computed(() => agents.value.find(a => a.id === selectedId.value));

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

// Price-feed key (brain plugins/price_credentials.py): write-only, stored encrypted per agent,
// never part of the agent's settings. Only its status ("Saved ••••1234") comes back.
const priceKey = ref('');
const priceStatus = ref({});
const priceResult = ref(null);
const priceSaved = ref('');
const priceBusy = ref(false);
const priceSource = computed(() => (draft.value?.generic || {}).prices || null);
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
const behaviour = computed(() => draft.value?.generic || {});
function setBehaviour(key, on) {
  draft.value.generic = {
    ...(draft.value.generic || { ...BLANK_GENERIC, teams: {} }),
    [key]: on,
  };
}
async function loadTemplates() {
  try {
    const { data } = await window.axios.get(`${apiBase.value}/brain/agent_templates`);
    templates.value = data.templates || [];
  } catch (e) {
    templates.value = [];
  }
}
async function createFromTemplate(t) {
  const a = {
    id: uid(),
    name: t.name,
    emoji: '🤖',
    status: 'inactive',
    description: t.description,
    instructions: t.generic.instructions,
    knowledge: [],
    skills: [],
    template: t.id,
    generic: { enabled: true, ...JSON.parse(JSON.stringify(t.generic)), teams: {} },
  };
  await addAgent(a);
}

// A new agent is listed only once the brain has stored it.
async function addAgent(a) {
  const r = await saveToServer(a);
  listResult.value = refused(r) ? r : null;
  if (refused(r)) return;
  agents.value.push(a);
  announce();
  openAgent(a.id);
}

async function createAgent() {
  const a = {
    id: uid(),
    name: 'New AI Agent',
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

function cancelEdit() {
  selectedId.value = null;
  draft.value = null;
}

async function saveAgent() {
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
  const r = await saveToServer(payload);
  if (refused(r)) {
    // Keep the builder open with the edits; the list keeps what the brain has.
    saveResult.value = r;
    return;
  }
  const i = agents.value.findIndex(a => a.id === draft.value.id);
  if (i >= 0) agents.value[i] = JSON.parse(JSON.stringify(draft.value));
  announce();
  selectedId.value = null;
  draft.value = null;
}

async function deleteAgent(id) {
  // eslint-disable-next-line no-alert
  if (!window.confirm('Delete this AI Agent?')) return;
  const r = await brainPost('agents/delete', { id });
  if (refused(r)) {
    if (selectedId.value === id) saveResult.value = r;
    else listResult.value = r;
    return;
  }
  agents.value = agents.value.filter(a => a.id !== id);
  announce();
  if (selectedId.value === id) cancelEdit();
}

// Index the agent's links and texts now (the brain also does it daily). Uses the saved agent,
// so unsaved rows are saved first.
const knowledgeResult = ref(null);
const knowledgeBusy = ref(false);
async function refreshKnowledge() {
  knowledgeBusy.value = true;
  knowledgeResult.value = null;
  const payload = JSON.parse(JSON.stringify(draft.value));
  if (payload.generic) payload.generic.instructions = payload.instructions;
  const saved = await saveToServer(payload);
  const r = refused(saved)
    ? saved
    : await brainPost('brain/knowledge_refresh', { id: draft.value.id });
  knowledgeResult.value = r;
  knowledgeBusy.value = false;
}
const knowledgeSaved = computed(() =>
  knowledgeResult.value && !refused(knowledgeResult.value)
    ? t('TOLZAR_AGENTS.KNOWLEDGE_INDEXED', {
        total: knowledgeResult.value.total ?? 0,
      })
    : ''
);

function addKnowledge() {
  draft.value.knowledge.push({ type: 'url', label: '', value: '' });
}
function removeKnowledge(i) {
  draft.value.knowledge.splice(i, 1);
}

const testBusy = ref(false);
async function sendTest() {
  const text = testInput.value.trim();
  if (!text || testBusy.value) return;
  testMsgs.value.push({ who: 'user', text });
  testInput.value = '';
  testBusy.value = true;
  const thinking = { who: 'agent', text: 'Thinking…', pending: true };
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
    testMsgs.value.push({ ...msg, text: msg.text || 'No reply.' });
  } catch (e) {
    drop();
    testMsgs.value.push({ who: 'agent', text: 'The model did not answer (network error). Try again.' });
  } finally {
    testBusy.value = false;
  }
}

// ?agent=<id> (the sidebar tree) opens that agent's builder.
const openFromRoute = () => {
  const id = route.query?.agent;
  if (id && agents.value.some(a => a.id === id)) openAgent(String(id));
};
watch(() => route.query?.agent, openFromRoute);

onMounted(async () => {
  loadTemplates();
  await load();
  openFromRoute();
});
</script>

<template>
  <div class="overflow-auto flex-1 bg-n-background" data-tz-build="ai-agents-6-skills">
    <!-- ===================== LIST VIEW ===================== -->
    <div v-if="!selectedId" class="mx-auto max-w-[1120px] px-5 pb-16 pt-7 md:px-6">
      <div class="flex gap-4 justify-between items-start tz-rise">
        <div class="flex gap-3 items-center">
          <span class="tz-mark grid flex-shrink-0 place-content-center rounded-2xl size-11">
            <span class="i-lucide-bot size-6 text-white" />
          </span>
          <div>
            <h1 class="m-0 text-[22px] font-extrabold tracking-tight text-n-slate-12">AI Agents</h1>
            <p class="m-0 text-sm text-n-slate-11">Handle more conversations with less effort — your AI team.</p>
          </div>
        </div>
        <div class="flex gap-2">
          <details class="relative">
            <summary class="tz-btn-ghost list-none"><span class="i-lucide-layout-template size-4" /> From a template</summary>
            <div class="absolute right-0 z-20 p-1.5 mt-1 w-[340px] rounded-xl border shadow-lg bg-n-solid-1 border-n-weak">
              <button
                v-for="t in templates"
                :key="t.id"
                type="button"
                class="block px-3 py-2 w-full text-left rounded-lg hover:bg-n-alpha-1"
                @click="createFromTemplate(t)"
              >
                <div class="text-[13px] font-semibold text-n-slate-12">{{ t.name }}</div>
                <div class="text-xs text-n-slate-10">{{ t.description }}</div>
              </button>
            </div>
          </details>
          <button type="button" class="tz-btn-primary" @click="createAgent">
            <span class="i-lucide-plus size-4" /> Create AI Agent
          </button>
        </div>
      </div>
      <div class="max-w-[640px]">
        <BrainNotice :result="listResult" />
      </div>

      <div class="tz-rise flex gap-2.5 items-center mt-4 px-3.5 py-2.5 text-xs rounded-xl border border-n-weak bg-n-alpha-1 text-n-slate-11" style="animation-delay: 60ms">
        <span class="i-lucide-sparkles size-4 text-n-brand" />
        <span><strong class="text-n-slate-12">Default agent:</strong> {{ (agents.find(x => x.id === defaultId) || {}).name || 'none' }} — new open conversations are assigned to it automatically.</span>
      </div>

      <div class="grid gap-4 mt-6 grid-cols-[repeat(auto-fill,minmax(320px,1fr))]">
        <div
          v-for="(a, i) in agents"
          :key="a.id"
          class="tz-rise tz-card tz-hover p-[18px] rounded-2xl border shadow-sm cursor-pointer bg-n-solid-1 border-n-weak"
          :style="{ animationDelay: 100 + i * 50 + 'ms' }"
          @click="openAgent(a.id)"
        >
          <div class="flex gap-2.5 items-center">
            <div class="grid place-content-center text-2xl rounded-xl size-11 bg-n-alpha-2">{{ a.emoji }}</div>
            <div class="flex-1 min-w-0">
              <div class="flex gap-1.5 items-center">
                <span class="font-bold truncate text-n-slate-12">{{ a.name }}</span>
                <span v-if="defaultId === a.id" class="px-1.5 py-px text-[10px] font-bold rounded-full text-amber-700 bg-amber-100 dark:text-amber-300 dark:bg-amber-500/15">DEFAULT</span>
              </div>
              <span
                title="Click to toggle"
                class="inline-block px-2 py-px mt-1 text-[11px] font-bold rounded-full cursor-pointer"
                :class="a.status === 'active' ? '' : 'text-n-slate-11 bg-n-alpha-2'"
                :style="a.status === 'active' ? { color: '#3e63dd', background: 'rgba(62,99,221,.15)' } : {}"
                @click="toggleStatus(a, $event)"
              >{{ a.status === 'active' ? '● Active' : 'Inactive' }}</span>
            </div>
          </div>
          <p class="mt-3 mb-0 text-[13px] text-n-slate-11 min-h-[34px]">{{ a.description || 'No description yet.' }}</p>
          <div class="flex justify-between items-center pt-3 mt-3 border-t border-n-weak">
            <span class="inline-flex gap-1 items-center text-[13px] font-bold text-n-brand">Edit <span class="i-lucide-arrow-right size-3.5 rtl:rotate-180" /></span>
            <button v-if="defaultId !== a.id" type="button" class="text-xs font-medium transition-colors text-n-slate-10 hover:text-n-brand" @click="setDefault(a.id, $event)">Set as default</button>
            <span v-else class="inline-flex gap-1 items-center text-xs font-semibold text-emerald-600 dark:text-emerald-400"><span class="i-lucide-check size-3.5" /> Default</span>
          </div>
        </div>

        <button
          type="button"
          class="tz-rise flex flex-col gap-1 justify-center items-center text-center rounded-2xl border border-dashed transition-colors cursor-pointer border-n-strong min-h-[128px] text-n-slate-11 hover:border-n-brand hover:bg-n-alpha-1"
          @click="createAgent"
        >
          <span class="grid place-content-center mb-1 rounded-xl size-9 bg-n-alpha-2"><span class="i-lucide-plus size-5 text-n-brand" /></span>
          <span class="font-bold text-n-slate-12">Create new AI Agent</span>
          <span class="text-xs">Add a new AI Agent to your team.</span>
        </button>
      </div>
    </div>

    <!-- ===================== BUILDER VIEW ===================== -->
    <div v-else-if="draft" class="mx-auto max-w-[1240px] px-5 pb-16 pt-5 md:px-6">
      <!-- header -->
      <div class="flex flex-wrap gap-3 items-center mb-4">
        <button type="button" class="tz-btn-ghost" @click="cancelEdit">‹ Back</button>
        <div class="flex flex-wrap gap-1 max-w-[230px]">
          <button
            v-for="e in EMOJIS"
            :key="e"
            type="button"
            class="px-1.5 py-1 text-lg leading-none rounded-lg border transition-colors bg-n-solid-1"
            :class="draft.emoji === e ? 'border-n-brand ring-1 ring-n-brand' : 'border-n-weak'"
            @click="draft.emoji = e"
          >{{ e }}</button>
        </div>
        <input
          v-model="draft.name"
          class="flex-1 px-2 py-1 min-w-0 text-lg font-extrabold rounded-lg border border-transparent outline-none text-n-slate-12 bg-n-background focus:border-n-weak"
        />
        <label class="flex gap-1.5 items-center text-[13px] text-n-slate-11">
          <input type="checkbox" class="accent-[#3e63dd]" :checked="draft.status === 'active'" @change="draft.status = $event.target.checked ? 'active' : 'inactive'" />
          Active
        </label>
        <button type="button" class="tz-btn-ghost" @click="cancelEdit">Cancel</button>
        <button type="button" class="tz-btn-primary" @click="saveAgent"><span class="i-lucide-check size-4" /> Save</button>
      </div>
      <div class="max-w-[640px] -mt-2 mb-3">
        <BrainNotice :result="saveResult" />
      </div>

      <div class="grid gap-[18px] items-start grid-cols-1 lg:grid-cols-[1fr_380px]">
        <!-- left: config -->
        <div class="grid gap-4">
          <!-- Instructions -->
          <section class="p-[18px] rounded-2xl border shadow-sm bg-n-solid-1 border-n-weak">
            <h3 class="mb-1 text-[15px] font-semibold text-n-slate-12">Instructions</h3>
            <p class="mt-0 mb-2.5 text-xs text-n-slate-11">Describe the agent’s role, communication style and the skills it should perform. Use clear, step-by-step language.</p>
            <textarea
              v-model="draft.instructions"
              rows="12"
              class="box-border p-3 w-full font-mono text-[12.5px] leading-relaxed rounded-xl border outline-none resize-y border-n-weak bg-n-background text-n-slate-12 focus:border-n-brand"
              placeholder="# CONTEXT&#10;You are..."
            ></textarea>
          </section>

          <!-- Behaviour switches (brain generic.py) -->
          <section class="p-[18px] rounded-2xl border shadow-sm bg-n-solid-1 border-n-weak" data-tz-behaviour>
            <h3 class="mb-1 text-[15px] font-semibold text-n-slate-12">{{ t('TOLZAR_AGENTS.BEHAVIOUR') }}</h3>
            <p class="mt-0 mb-2.5 text-xs text-n-slate-11">{{ t('TOLZAR_AGENTS.BEHAVIOUR_HINT') }}</p>
            <label v-for="k in ['enabled', 'answer_from_knowledge', 'quote_prices']" :key="k" class="flex gap-2 items-start mb-2 text-[13px] text-n-slate-12">
              <input type="checkbox" class="mt-0.5 accent-[#3e63dd]" :checked="!!behaviour[k]" @change="setBehaviour(k, $event.target.checked)" />
              <span>
                {{ t(`TOLZAR_AGENTS.SWITCH.${k}`) }}
                <span class="block text-xs text-n-slate-10">{{ t(`TOLZAR_AGENTS.SWITCH_HINT.${k}`) }}</span>
              </span>
            </label>
          </section>

          <!-- Description -->
          <section class="p-[18px] rounded-2xl border shadow-sm bg-n-solid-1 border-n-weak">
            <h3 class="mb-2.5 text-[15px] font-semibold text-n-slate-12">Description</h3>
            <input v-model="draft.description" class="tz-in" placeholder="One line shown on the agent card" />
          </section>

          <!-- Knowledge sources -->
          <section class="p-[18px] rounded-2xl border shadow-sm bg-n-solid-1 border-n-weak">
            <div class="flex justify-between items-center">
              <h3 class="m-0 text-[15px] font-semibold text-n-slate-12">Knowledge sources</h3>
              <div class="flex gap-2">
                <button type="button" class="tz-btn-soft" :disabled="knowledgeBusy || !draft.knowledge.length" @click="refreshKnowledge">
                  <span class="i-lucide-refresh-cw size-3.5" /> {{ knowledgeBusy ? t('TOLZAR_AGENTS.INDEXING') : t('TOLZAR_AGENTS.INDEX_NOW') }}
                </button>
                <button type="button" class="tz-btn-soft" @click="addKnowledge"><span class="i-lucide-plus size-3.5" /> Add</button>
              </div>
            </div>
            <p class="mt-1.5 mb-3 text-xs text-n-slate-11">Documents, FAQs and links the agent can use to answer.</p>
            <div v-if="!draft.knowledge.length" class="text-[13px] text-n-slate-10">No sources yet.</div>
            <p v-if="draft.knowledge.length && !behaviour.answer_from_knowledge" class="mt-0 mb-2 text-xs text-n-amber-11">{{ t('TOLZAR_AGENTS.KNOWLEDGE_OFF') }}</p>
            <div v-for="(k, i) in draft.knowledge" :key="i" class="flex gap-2 items-center mb-2">
              <select v-model="k.type" class="tz-in !w-auto">
                <option value="url">Link</option>
                <option value="text">Text</option>
                <!-- File sources are not read by the brain yet; an old row stays visible to remove. -->
                <option v-if="k.type === 'file'" value="file" disabled>File (not read yet)</option>
              </select>
              <input v-model="k.label" placeholder="Label" class="tz-in !w-[120px]" />
              <input v-model="k.value" :placeholder="k.type === 'text' ? 'Text the agent may use' : 'https://…'" class="flex-1 tz-in" />
              <button type="button" class="grid place-content-center rounded-lg transition-colors size-7 text-n-slate-10 hover:text-rose-500 hover:bg-n-alpha-2" @click="removeKnowledge(i)"><span class="i-lucide-x size-4" /></button>
            </div>
            <BrainNotice :result="knowledgeResult" :saved="knowledgeSaved" />
          </section>

          <!-- Price source (type, address, refresh; test fetch; Owner saves) -->
          <PriceSourcePanel :agent-id="draft.id" @saved="onPriceSourceSaved" />
          <PriceUploadPanel :agent-id="draft.id" @saved="onPriceSourceSaved" />

          <!-- Price feed key -->
          <section class="p-[18px] rounded-2xl border shadow-sm bg-n-solid-1 border-n-weak" data-tz-price-key>
            <h3 class="m-0 text-[15px] font-semibold text-n-slate-12">{{ t('TOLZAR_SETTINGS.CHANNELS.CRED.PRICES_TITLE') }}</h3>
            <p class="mt-1.5 mb-0 text-xs text-n-slate-11">{{ t('TOLZAR_SETTINGS.CHANNELS.CRED.PRICES_HINT') }}</p>
            <p class="mt-1.5 mb-0 text-xs break-all text-n-slate-10">
              {{ priceSource && (priceSource.type || priceSource.value)
                ? t('TOLZAR_SETTINGS.CHANNELS.CRED.PRICES_SOURCE', { type: priceSource.type || '', value: priceSource.value || '' })
                : t('TOLZAR_SETTINGS.CHANNELS.CRED.PRICES_NO_SOURCE') }}
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

          <!-- AI skills: proposals only ("would do" notes); nothing is executed -->
          <SkillsPanel
            :key="draft.id"
            v-model="skillsForm"
            :live="SKILLS_LIVE"
          />
          <p v-if="skillsError" class="m-0 text-xs text-rose-600" role="alert">
            {{ t('TOLZAR_SKILLS.SAVE_BLOCKED') }}
          </p>
        </div>

        <!-- right: test -->
        <section class="sticky top-4 p-4 rounded-2xl border shadow-sm bg-n-solid-1 border-n-weak">
          <div class="flex justify-between items-center mb-2">
            <h3 class="inline-flex gap-1.5 items-center m-0 text-[15px] font-semibold text-n-slate-12"><span class="i-lucide-message-circle size-4 text-n-brand" /> Test</h3>
            <button type="button" class="text-xs transition-colors text-n-slate-10 hover:text-n-slate-12" @click="testMsgs = []">Reset chat</button>
          </div>
          <div class="flex gap-2 items-start px-2.5 py-2 mb-2.5 text-[11.5px] rounded-lg" style="color: #3a5bc7; background: rgba(62,99,221,.1); border: 1px solid rgba(62,99,221,.22)">
            <span class="flex-shrink-0 mt-0.5 i-lucide-circle-check size-3.5" />
            <span class="dark:text-n-iris-11">Replies come from your self-hosted model using this agent’s instructions, knowledge and prices (saved ones; instructions as typed). This won’t touch any real conversation.</span>
          </div>
          <div class="flex overflow-auto flex-col gap-2 p-2.5 h-[300px] rounded-xl border border-n-weak bg-n-background">
            <div v-if="!testMsgs.length" class="m-auto text-[12.5px] text-center text-n-slate-10">Send a message to see how your agent replies.</div>
            <div
              v-for="(m, i) in testMsgs"
              :key="i"
              :style="{ alignSelf: m.who === 'user' ? 'flex-end' : 'flex-start', maxWidth: '85%' }"
            >
              <div
                class="px-2.5 py-2 text-[12.5px] leading-snug rounded-xl"
                :class="m.who === 'user' ? 'bg-n-brand text-white' : 'bg-n-alpha-2 text-n-slate-12'"
                :style="{ opacity: m.pending ? 0.7 : 1, fontStyle: m.pending ? 'italic' : 'normal' }"
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
            <input v-model="testInput" :disabled="testBusy" placeholder="Type a message…" class="flex-1 tz-in" @keyup.enter="sendTest" />
            <button type="button" :disabled="testBusy" class="tz-btn-primary !px-3.5 disabled:opacity-60" @click="sendTest">{{ testBusy ? '…' : 'Send' }}</button>
          </div>
        </section>
      </div>

      <button type="button" class="inline-flex gap-1 items-center mt-5 text-xs transition-colors text-n-slate-10 hover:text-rose-500" @click="deleteAgent(draft.id)">
        <span class="i-lucide-trash-2 size-3.5" /> Delete this agent
      </button>
    </div>
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
  white-space: nowrap;
  box-shadow: 0 1px 2px rgba(15, 23, 42, 0.08);
  transition: opacity 0.15s, box-shadow 0.15s, background 0.15s;
}
.tz-btn-primary:hover {
  background: #3358d4;
  box-shadow: 0 6px 16px -8px rgba(62, 99, 221, 0.6);
}
.tz-btn-ghost {
  display: inline-flex;
  gap: 0.375rem;
  align-items: center;
  height: 2.25rem;
  padding: 0 0.875rem;
  font-size: 0.875rem;
  font-weight: 600;
  color: rgb(var(--slate-11));
  background: rgb(var(--solid-1));
  border: 1px solid rgb(var(--border-weak));
  border-radius: 0.75rem;
  cursor: pointer;
  transition: background 0.15s;
}
.tz-btn-ghost:hover {
  background: rgba(var(--alpha-1));
}
.tz-btn-soft {
  display: inline-flex;
  gap: 0.25rem;
  align-items: center;
  padding: 0.375rem 0.75rem;
  font-size: 0.8125rem;
  font-weight: 600;
  color: rgb(var(--slate-11));
  background: rgba(var(--alpha-2));
  border: 0;
  border-radius: 0.5rem;
  cursor: pointer;
  transition: background 0.15s;
}
.tz-btn-soft:hover {
  background: rgba(var(--alpha-3));
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
  transition: border-color 0.15s;
}
.tz-in:focus {
  border-color: #3e63dd;
}
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
