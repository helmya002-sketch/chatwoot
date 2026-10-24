<script setup>
import { ref, computed, onMounted } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';

const accountId = useMapGetter('getCurrentAccountId');

// --- AI Agents pillar (respond.io clone). Shell UI; persists to localStorage for now.
// Data model maps 1:1 to the future brain API (agents CRUD + test-chat).
const STORE_KEY = 'tolzar_ai_agents_v1';
const EMOJIS = ['😇', '😎', '🤖', '🐬', '💬', '⚓', '🧭', '🌊'];

// Skill catalog — mirrors respond.io AI Skills; each maps to a Chatwoot action we already script.
const SKILL_CATALOG = [
  { type: 'assign', label: 'Assign to agent or team', hint: 'Route the conversation to a human agent, a team, or another AI Agent.' },
  { type: 'update_fields', label: 'Update Contact fields', hint: 'Save data from the conversation to contact fields (hotel, location, country…).' },
  { type: 'update_lifecycle', label: 'Update Lifecycle Stage', hint: 'Move the contact along the funnel (New Lead → Active → Offer Sent → Won/Lost).' },
  { type: 'close', label: 'Close conversation', hint: 'Resolve the conversation when the task is complete.' },
  { type: 'comment', label: 'Add comments', hint: 'Leave a private note for the human team.' },
  { type: 'tags', label: 'Update tags', hint: 'Add or remove labels on the conversation.' },
  { type: 'workflow', label: 'Trigger Workflows', hint: 'Start an existing workflow to automate the rest.' },
];

const agents = ref([]);
const selectedId = ref(null); // null = list view, else builder
const draft = ref(null); // editable copy while in builder
const loaded = ref(false);
const DEFAULT_KEY = 'tolzar_default_agent_v1';
const defaultId = ref(null);

// test chat (preview only — brain not connected yet)
const testMsgs = ref([]);
const testInput = ref('');

function uid() {
  return 'a' + Math.random().toString(36).slice(2, 9);
}

function seed() {
  return [
    {
      id: uid(),
      name: 'Alex 2',
      emoji: '🐬',
      status: 'active',
      description:
        'Greets customers, answers from the team price templates, drives to the free pre-booking voucher, hands over at confirmation.',
      instructions:
        '# CONTEXT\nYou are Alex, the friendly sales coordinator at Aquarius Diving Club. Understand each contact’s intent, answer from the approved price templates, and drive toward the free, no-obligation pre-booking voucher. Hand over to a specialist at confirmation.\n\n# STYLE\n- Warm, second person, contractions. Reply in the contact’s language.\n- Never mention AI or automation. At most one 😊 per message. 2–4 sentences.\n- Greet once, in the first reply, combined with the next step.\n\n# ROUTING\n- Sharm El Sheikh → Francesca.\n- Hurghada / Makadi / Makadi Bay / Sahl Hasheesh / Soma Bay / El Gouna → Hurghada Team (round robin).\n- Jobs / spam / booking.com / submarine → Ahmed.',
      knowledge: [
        { type: 'url', label: 'Aquarius', value: 'https://www.aquariusredsea.com/' },
        { type: 'file', label: 'Hotels', value: 'hotels.csv' },
        { type: 'url', label: 'Live prices', value: 'prices.yaml (read-only endpoint)' },
      ],
      skills: [
        { type: 'assign', config: 'Fire in the SAME turn as any handover. Sharm→Francesca; Hurghada area→Hurghada Team round robin; jobs/spam/booking.com/submarine or +972/Hebrew→Ahmed.' },
        { type: 'update_fields', config: 'Save location to one of the 4 centers (El Gouna/Soma Bay→Hurghada); set country from the phone number.' },
        { type: 'update_lifecycle', config: 'Move to Offer Sent when a price/voucher is offered; Customer Won at confirmation.' },
      ],
    },
    {
      id: uid(),
      name: 'Booking Value Extractor',
      emoji: '🤖',
      status: 'inactive',
      description: 'Reads a won conversation and saves the booking value to the contact.',
      instructions: 'When a booking is confirmed, extract the total booking value (EUR) and save it to the booking_value_eur field.',
      knowledge: [],
      skills: [{ type: 'update_fields', config: 'Save the confirmed total to booking_value_eur.' }],
    },
  ];
}

function load() {
  try {
    const raw = localStorage.getItem(STORE_KEY);
    agents.value = raw ? JSON.parse(raw) : seed();
    if (!raw) persist();
  } catch (e) {
    agents.value = seed();
  }
  try {
    defaultId.value = localStorage.getItem(DEFAULT_KEY);
  } catch (e) {
    /* storage unavailable */
  }
  if (!defaultId.value && agents.value.length) defaultId.value = agents.value[0].id;
  loaded.value = true;
}

function persist() {
  try {
    localStorage.setItem(STORE_KEY, JSON.stringify(agents.value));
  } catch (e) {
    /* storage unavailable — shell still works in-memory */
  }
}

function setDefault(id, ev) {
  if (ev) ev.stopPropagation();
  defaultId.value = id;
  try {
    localStorage.setItem(DEFAULT_KEY, id);
  } catch (e) {
    /* storage unavailable */
  }
}
function toggleStatus(a, ev) {
  if (ev) ev.stopPropagation();
  a.status = a.status === 'active' ? 'inactive' : 'active';
  persist();
}

const selected = computed(() => agents.value.find(a => a.id === selectedId.value));

function openAgent(id) {
  selectedId.value = id;
  draft.value = JSON.parse(JSON.stringify(agents.value.find(a => a.id === id)));
  testMsgs.value = [];
}

function createAgent() {
  const a = {
    id: uid(),
    name: 'New AI Agent',
    emoji: '🤖',
    status: 'inactive',
    description: '',
    instructions: '',
    knowledge: [],
    skills: [],
  };
  agents.value.push(a);
  persist();
  openAgent(a.id);
}

function cancelEdit() {
  selectedId.value = null;
  draft.value = null;
}

function saveAgent() {
  const i = agents.value.findIndex(a => a.id === draft.value.id);
  if (i >= 0) agents.value[i] = JSON.parse(JSON.stringify(draft.value));
  persist();
  selectedId.value = null;
  draft.value = null;
}

function deleteAgent(id) {
  // eslint-disable-next-line no-alert
  if (!window.confirm('Delete this AI Agent?')) return;
  agents.value = agents.value.filter(a => a.id !== id);
  persist();
  if (selectedId.value === id) cancelEdit();
}

function addKnowledge() {
  draft.value.knowledge.push({ type: 'url', label: '', value: '' });
}
function removeKnowledge(i) {
  draft.value.knowledge.splice(i, 1);
}

const addSkillOpen = ref(false);
function addSkill(type) {
  draft.value.skills.push({ type, config: '' });
  addSkillOpen.value = false;
}
function removeSkill(i) {
  draft.value.skills.splice(i, 1);
}
function skillLabel(type) {
  return (SKILL_CATALOG.find(s => s.type === type) || {}).label || type;
}
const availableSkills = computed(() =>
  SKILL_CATALOG.filter(s => !draft.value.skills.some(x => x.type === s.type))
);

const testBusy = ref(false);
async function sendTest() {
  const t = testInput.value.trim();
  if (!t || testBusy.value) return;
  testMsgs.value.push({ who: 'user', text: t });
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
      { message: t, instructions: draft.value?.instructions || '', history }
    );
    drop();
    testMsgs.value.push({
      who: 'agent',
      text: data.reply || 'No reply.',
      meta: data.ok && data.model
        ? `${data.model}${data.latency_ms ? ' · ' + (Math.round(data.latency_ms / 100) / 10) + 's' : ''}`
        : '',
    });
  } catch (e) {
    drop();
    testMsgs.value.push({ who: 'agent', text: 'The model did not answer (network error). Try again.' });
  } finally {
    testBusy.value = false;
  }
}

const skillAccent = { assign: '#0ea5e9', update_fields: '#8b5cf6', update_lifecycle: '#ec4899', close: '#22c55e', comment: '#64748b', tags: '#10b981', workflow: '#4f46e5' };
function tint(hex) {
  return { color: hex, background: `${hex}1f` };
}

onMounted(load);
</script>

<template>
  <div class="overflow-auto flex-1 bg-n-background" data-tz-build="ai-agents-4">
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
        <button type="button" class="tz-btn-primary" @click="createAgent">
          <span class="i-lucide-plus size-4" /> Create AI Agent
        </button>
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
                :style="a.status === 'active' ? { color: '#4f46e5', background: 'rgba(91,91,214,.15)' } : {}"
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
          <input type="checkbox" class="accent-[#4f46e5]" :checked="draft.status === 'active'" @change="draft.status = $event.target.checked ? 'active' : 'inactive'" />
          Active
        </label>
        <button type="button" class="tz-btn-ghost" @click="cancelEdit">Cancel</button>
        <button type="button" class="tz-btn-primary" @click="saveAgent"><span class="i-lucide-check size-4" /> Save</button>
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

          <!-- Description -->
          <section class="p-[18px] rounded-2xl border shadow-sm bg-n-solid-1 border-n-weak">
            <h3 class="mb-2.5 text-[15px] font-semibold text-n-slate-12">Description</h3>
            <input v-model="draft.description" class="tz-in" placeholder="One line shown on the agent card" />
          </section>

          <!-- Knowledge sources -->
          <section class="p-[18px] rounded-2xl border shadow-sm bg-n-solid-1 border-n-weak">
            <div class="flex justify-between items-center">
              <h3 class="m-0 text-[15px] font-semibold text-n-slate-12">Knowledge sources</h3>
              <button type="button" class="tz-btn-soft" @click="addKnowledge"><span class="i-lucide-plus size-3.5" /> Add</button>
            </div>
            <p class="mt-1.5 mb-3 text-xs text-n-slate-11">Documents, FAQs and links the agent can use to answer.</p>
            <div v-if="!draft.knowledge.length" class="text-[13px] text-n-slate-10">No sources yet.</div>
            <div v-for="(k, i) in draft.knowledge" :key="i" class="flex gap-2 items-center mb-2">
              <select v-model="k.type" class="tz-in !w-auto">
                <option value="url">Link</option>
                <option value="file">File</option>
                <option value="text">Text</option>
              </select>
              <input v-model="k.label" placeholder="Label" class="tz-in !w-[120px]" />
              <input v-model="k.value" placeholder="URL / file / text" class="flex-1 tz-in" />
              <button type="button" class="grid place-content-center rounded-lg transition-colors size-7 text-n-slate-10 hover:text-rose-500 hover:bg-n-alpha-2" @click="removeKnowledge(i)"><span class="i-lucide-x size-4" /></button>
            </div>
          </section>

          <!-- AI skills -->
          <section class="p-[18px] rounded-2xl border shadow-sm bg-n-solid-1 border-n-weak">
            <div class="flex relative justify-between items-center">
              <h3 class="m-0 text-[15px] font-semibold text-n-slate-12">AI skills</h3>
              <button type="button" class="tz-btn-soft" @click="addSkillOpen = !addSkillOpen"><span class="i-lucide-plus size-3.5" /> Add skill</button>
              <div v-if="addSkillOpen" class="overflow-hidden absolute top-9 z-10 w-[300px] rounded-xl border shadow-lg ltr:right-0 rtl:left-0 bg-n-solid-1 border-n-weak">
                <div v-if="!availableSkills.length" class="p-3 text-[13px] text-n-slate-10">All skills added.</div>
                <button v-for="s in availableSkills" :key="s.type" type="button" class="block px-3 py-2.5 w-full text-left border-b transition-colors border-n-weak last:border-0 hover:bg-n-alpha-1" @click="addSkill(s.type)">
                  <div class="text-[13px] font-semibold text-n-slate-12">{{ s.label }}</div>
                  <div class="text-[11px] text-n-slate-10">{{ s.hint }}</div>
                </button>
              </div>
            </div>
            <p class="mt-1.5 mb-3 text-xs text-n-slate-11">Set clear rules so your agent behaves as expected.</p>
            <div v-if="!draft.skills.length" class="text-[13px] text-n-slate-10">No skills yet — add one.</div>
            <div v-for="(sk, i) in draft.skills" :key="i" class="p-3 mb-2.5 rounded-xl border border-n-weak bg-n-alpha-1">
              <div class="flex justify-between items-center mb-1.5">
                <div class="inline-flex gap-1.5 items-center text-[13px] font-bold">
                  <span class="inline-block rounded-full size-2" :style="{ background: skillAccent[sk.type] || '#64748b' }" />
                  <span class="text-n-slate-12">{{ skillLabel(sk.type) }}</span>
                </div>
                <button type="button" class="grid place-content-center rounded-lg transition-colors size-6 text-n-slate-10 hover:text-rose-500 hover:bg-n-alpha-2" @click="removeSkill(i)"><span class="i-lucide-x size-4" /></button>
              </div>
              <textarea v-model="sk.config" rows="2" placeholder="When and how should this skill be performed?" class="box-border p-2 w-full text-[12.5px] rounded-lg border outline-none resize-y border-n-weak bg-n-solid-1 text-n-slate-12 focus:border-n-brand"></textarea>
            </div>
          </section>
        </div>

        <!-- right: test -->
        <section class="sticky top-4 p-4 rounded-2xl border shadow-sm bg-n-solid-1 border-n-weak">
          <div class="flex justify-between items-center mb-2">
            <h3 class="inline-flex gap-1.5 items-center m-0 text-[15px] font-semibold text-n-slate-12"><span class="i-lucide-message-circle size-4 text-n-brand" /> Test</h3>
            <button type="button" class="text-xs transition-colors text-n-slate-10 hover:text-n-slate-12" @click="testMsgs = []">Reset chat</button>
          </div>
          <div class="flex gap-2 items-start px-2.5 py-2 mb-2.5 text-[11.5px] rounded-lg" style="color: #4338ca; background: rgba(91,91,214,.1); border: 1px solid rgba(91,91,214,.22)">
            <span class="flex-shrink-0 mt-0.5 i-lucide-circle-check size-3.5" />
            <span class="dark:text-n-iris-11">Live — replies come from your self-hosted model using the instructions above. This won’t touch any real conversation.</span>
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
  background: linear-gradient(140deg, #6366f1, #4f46e5);
  box-shadow: 0 8px 20px -6px rgba(79, 70, 229, 0.5);
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
  background: #5753c6;
  border: 0;
  border-radius: 0.75rem;
  cursor: pointer;
  white-space: nowrap;
  box-shadow: 0 1px 2px rgba(15, 23, 42, 0.08);
  transition: opacity 0.15s, box-shadow 0.15s, background 0.15s;
}
.tz-btn-primary:hover {
  background: #4a46ad;
  box-shadow: 0 6px 16px -8px rgba(79, 70, 229, 0.6);
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
  border-color: #5b5bd6;
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
