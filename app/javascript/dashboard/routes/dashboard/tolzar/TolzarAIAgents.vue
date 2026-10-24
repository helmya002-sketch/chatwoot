<script setup>
import { ref, computed, onMounted } from 'vue';

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
  loaded.value = true;
}

function persist() {
  try {
    localStorage.setItem(STORE_KEY, JSON.stringify(agents.value));
  } catch (e) {
    /* storage unavailable — shell still works in-memory */
  }
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

function sendTest() {
  const t = testInput.value.trim();
  if (!t) return;
  testMsgs.value.push({ who: 'user', text: t });
  testInput.value = '';
  // Preview only — the brain is wired in a later increment.
  setTimeout(() => {
    testMsgs.value.push({
      who: 'agent',
      text: 'Preview mode — the brain isn’t connected yet. Once wired, your agent will reply here using these instructions, knowledge and skills.',
    });
  }, 250);
}

onMounted(load);
</script>

<template>
  <div
    class="flex-1 overflow-auto"
    data-tz-build="ai-agents-1"
    style="background: #f5f8fc"
  >
    <!-- ===================== LIST VIEW ===================== -->
    <div v-if="!selectedId" style="max-width: 1120px; margin: 0 auto; padding: 32px 24px 64px">
      <div style="display: flex; align-items: flex-start; justify-content: space-between; gap: 16px">
        <div>
          <h1 style="font-size: 24px; font-weight: 800; color: #0b1f3a; margin: 0 0 2px">AI Agents</h1>
          <p style="color: #64748b; margin: 0">Handle more conversations with less effort using AI Agents.</p>
        </div>
        <button
          type="button"
          style="background: linear-gradient(180deg,#14b8a6,#0e8f84); color: #fff; border: 0; border-radius: 10px; padding: 10px 16px; font-weight: 700; cursor: pointer; white-space: nowrap"
          @click="createAgent"
        >
          + Create AI Agent
        </button>
      </div>

      <div
        style="display: grid; grid-template-columns: repeat(auto-fill,minmax(320px,1fr)); gap: 16px; margin-top: 24px"
      >
        <div
          v-for="a in agents"
          :key="a.id"
          style="background: #fff; border: 1px solid #e3e9f2; border-radius: 14px; padding: 18px; cursor: pointer; transition: box-shadow .12s"
          @click="openAgent(a.id)"
        >
          <div style="display: flex; align-items: center; gap: 10px">
            <div style="font-size: 26px; line-height: 1">{{ a.emoji }}</div>
            <div style="flex: 1; min-width: 0">
              <div style="font-weight: 700; color: #0b1f3a">{{ a.name }}</div>
              <span
                :style="{
                  display: 'inline-block',
                  marginTop: '3px',
                  fontSize: '11px',
                  fontWeight: '700',
                  padding: '1px 8px',
                  borderRadius: '999px',
                  color: a.status === 'active' ? '#0e8f84' : '#64748b',
                  background: a.status === 'active' ? '#d8f5f0' : '#eef2f7',
                }"
              >{{ a.status === 'active' ? 'Active' : 'Inactive' }}</span>
            </div>
          </div>
          <p style="color: #64748b; font-size: 13px; margin: 12px 0 0; min-height: 34px">
            {{ a.description || 'No description yet.' }}
          </p>
          <div style="margin-top: 12px; font-size: 13px; font-weight: 700; color: #12a594">Edit →</div>
        </div>

        <div
          style="border: 1px dashed #c6d2e3; border-radius: 14px; padding: 18px; display: flex; flex-direction: column; justify-content: center; align-items: center; text-align: center; color: #64748b; cursor: pointer; min-height: 120px"
          @click="createAgent"
        >
          <div style="font-size: 22px; color: #12a594">+</div>
          <div style="font-weight: 700; color: #0b1f3a; margin-top: 4px">Create new AI Agent</div>
          <div style="font-size: 12px">Add a new AI Agent to your team.</div>
        </div>
      </div>
    </div>

    <!-- ===================== BUILDER VIEW ===================== -->
    <div v-else-if="draft" style="max-width: 1240px; margin: 0 auto; padding: 20px 24px 64px">
      <!-- header -->
      <div style="display: flex; align-items: center; gap: 12px; margin-bottom: 16px">
        <button
          type="button"
          style="background: #fff; border: 1px solid #e3e9f2; border-radius: 8px; padding: 6px 12px; cursor: pointer; color: #475569; font-weight: 600"
          @click="cancelEdit"
        >‹ Back</button>
        <select
          v-model="draft.emoji"
          style="font-size: 22px; border: 1px solid #e3e9f2; border-radius: 8px; padding: 2px 6px; background: #fff"
        >
          <option v-for="e in EMOJIS" :key="e" :value="e">{{ e }}</option>
        </select>
        <input
          v-model="draft.name"
          style="font-size: 18px; font-weight: 800; color: #0b1f3a; border: 1px solid transparent; border-radius: 8px; padding: 4px 8px; flex: 1; min-width: 0"
          @focus="$event.target.style.borderColor = '#e3e9f2'"
          @blur="$event.target.style.borderColor = 'transparent'"
        />
        <label style="display: flex; align-items: center; gap: 6px; font-size: 13px; color: #475569">
          <input type="checkbox" :checked="draft.status === 'active'" @change="draft.status = $event.target.checked ? 'active' : 'inactive'" />
          Active
        </label>
        <button type="button" style="background: #fff; border: 1px solid #e3e9f2; border-radius: 8px; padding: 8px 16px; cursor: pointer; color: #475569; font-weight: 600" @click="cancelEdit">Cancel</button>
        <button type="button" style="background: linear-gradient(180deg,#14b8a6,#0e8f84); color: #fff; border: 0; border-radius: 8px; padding: 8px 18px; font-weight: 700; cursor: pointer" @click="saveAgent">Save</button>
      </div>

      <div style="display: grid; grid-template-columns: 1fr 380px; gap: 18px; align-items: start">
        <!-- left: config -->
        <div style="display: grid; gap: 16px">
          <!-- Instructions -->
          <section style="background: #fff; border: 1px solid #e3e9f2; border-radius: 14px; padding: 18px">
            <h3 style="margin: 0 0 4px; font-size: 15px; color: #0b1f3a">Instructions</h3>
            <p style="margin: 0 0 10px; color: #64748b; font-size: 12px">Describe the agent’s role, communication style and the skills it should perform. Use clear, step-by-step language.</p>
            <textarea
              v-model="draft.instructions"
              rows="12"
              style="width: 100%; box-sizing: border-box; border: 1px solid #e3e9f2; border-radius: 10px; padding: 12px; font-family: ui-monospace,Menlo,Consolas,monospace; font-size: 12.5px; line-height: 1.5; color: #1e293b; resize: vertical"
              placeholder="# CONTEXT&#10;You are..."
            ></textarea>
          </section>

          <!-- Description -->
          <section style="background: #fff; border: 1px solid #e3e9f2; border-radius: 14px; padding: 18px">
            <h3 style="margin: 0 0 10px; font-size: 15px; color: #0b1f3a">Description</h3>
            <input v-model="draft.description" style="width: 100%; box-sizing: border-box; border: 1px solid #e3e9f2; border-radius: 10px; padding: 10px; font-size: 13px" placeholder="One line shown on the agent card" />
          </section>

          <!-- Knowledge sources -->
          <section style="background: #fff; border: 1px solid #e3e9f2; border-radius: 14px; padding: 18px">
            <div style="display: flex; justify-content: space-between; align-items: center">
              <h3 style="margin: 0; font-size: 15px; color: #0b1f3a">Knowledge sources</h3>
              <button type="button" style="background: #eef2f7; border: 0; border-radius: 8px; padding: 6px 12px; cursor: pointer; font-weight: 600; color: #334155" @click="addKnowledge">+ Add</button>
            </div>
            <p style="margin: 6px 0 12px; color: #64748b; font-size: 12px">Documents, FAQs and links the agent can use to answer.</p>
            <div v-if="!draft.knowledge.length" style="color: #94a3b8; font-size: 13px">No sources yet.</div>
            <div v-for="(k, i) in draft.knowledge" :key="i" style="display: flex; gap: 8px; margin-bottom: 8px; align-items: center">
              <select v-model="k.type" style="border: 1px solid #e3e9f2; border-radius: 8px; padding: 7px; font-size: 12px; background: #fff">
                <option value="url">Link</option>
                <option value="file">File</option>
                <option value="text">Text</option>
              </select>
              <input v-model="k.label" placeholder="Label" style="width: 120px; border: 1px solid #e3e9f2; border-radius: 8px; padding: 7px; font-size: 12px" />
              <input v-model="k.value" placeholder="URL / file / text" style="flex: 1; border: 1px solid #e3e9f2; border-radius: 8px; padding: 7px; font-size: 12px" />
              <button type="button" style="border: 0; background: transparent; color: #94a3b8; cursor: pointer; font-size: 16px" @click="removeKnowledge(i)">×</button>
            </div>
          </section>

          <!-- AI skills -->
          <section style="background: #fff; border: 1px solid #e3e9f2; border-radius: 14px; padding: 18px">
            <div style="display: flex; justify-content: space-between; align-items: center; position: relative">
              <h3 style="margin: 0; font-size: 15px; color: #0b1f3a">AI skills</h3>
              <button type="button" style="background: #eef2f7; border: 0; border-radius: 8px; padding: 6px 12px; cursor: pointer; font-weight: 600; color: #334155" @click="addSkillOpen = !addSkillOpen">+ Add skill</button>
              <div v-if="addSkillOpen" style="position: absolute; top: 34px; right: 0; background: #fff; border: 1px solid #e3e9f2; border-radius: 10px; box-shadow: 0 8px 24px rgba(15,31,58,.12); z-index: 5; width: 300px; overflow: hidden">
                <div v-if="!availableSkills.length" style="padding: 12px; color: #94a3b8; font-size: 13px">All skills added.</div>
                <button v-for="s in availableSkills" :key="s.type" type="button" style="display: block; width: 100%; text-align: left; background: #fff; border: 0; border-bottom: 1px solid #f1f5f9; padding: 10px 12px; cursor: pointer" @click="addSkill(s.type)">
                  <div style="font-weight: 600; color: #0b1f3a; font-size: 13px">{{ s.label }}</div>
                  <div style="color: #64748b; font-size: 11px">{{ s.hint }}</div>
                </button>
              </div>
            </div>
            <p style="margin: 6px 0 12px; color: #64748b; font-size: 12px">Set clear rules so your agent behaves as expected.</p>
            <div v-if="!draft.skills.length" style="color: #94a3b8; font-size: 13px">No skills yet — add one.</div>
            <div v-for="(sk, i) in draft.skills" :key="i" style="border: 1px solid #eef2f7; border-radius: 10px; padding: 12px; margin-bottom: 10px">
              <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 6px">
                <div style="font-weight: 700; color: #0e8f84; font-size: 13px">{{ skillLabel(sk.type) }}</div>
                <button type="button" style="border: 0; background: transparent; color: #94a3b8; cursor: pointer; font-size: 16px" @click="removeSkill(i)">×</button>
              </div>
              <textarea v-model="sk.config" rows="2" placeholder="When and how should this skill be performed?" style="width: 100%; box-sizing: border-box; border: 1px solid #e3e9f2; border-radius: 8px; padding: 8px; font-size: 12.5px; resize: vertical"></textarea>
            </div>
          </section>
        </div>

        <!-- right: test -->
        <section style="background: #fff; border: 1px solid #e3e9f2; border-radius: 14px; padding: 16px; position: sticky; top: 16px">
          <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 8px">
            <h3 style="margin: 0; font-size: 15px; color: #0b1f3a">Test</h3>
            <button type="button" style="background: transparent; border: 0; color: #64748b; font-size: 12px; cursor: pointer" @click="testMsgs = []">Reset chat</button>
          </div>
          <div style="background: #fff3cd; border: 1px solid #ffe69c; color: #7a5b00; font-size: 11.5px; border-radius: 8px; padding: 8px 10px; margin-bottom: 10px">
            Preview only — the brain isn’t connected yet. This won’t affect live conversations.
          </div>
          <div style="height: 300px; overflow: auto; border: 1px solid #eef2f7; border-radius: 10px; padding: 10px; display: flex; flex-direction: column; gap: 8px; background: #fafcff">
            <div v-if="!testMsgs.length" style="color: #94a3b8; font-size: 12.5px; margin: auto; text-align: center">Send a message to preview how your agent responds.</div>
            <div
              v-for="(m, i) in testMsgs"
              :key="i"
              :style="{
                alignSelf: m.who === 'user' ? 'flex-end' : 'flex-start',
                maxWidth: '85%',
                background: m.who === 'user' ? '#0e8f84' : '#eef2f7',
                color: m.who === 'user' ? '#fff' : '#1e293b',
                borderRadius: '10px',
                padding: '8px 10px',
                fontSize: '12.5px',
                lineHeight: '1.4',
              }"
            >{{ m.text }}</div>
          </div>
          <div style="display: flex; gap: 8px; margin-top: 10px">
            <input v-model="testInput" placeholder="Type a message…" style="flex: 1; border: 1px solid #e3e9f2; border-radius: 8px; padding: 9px; font-size: 13px" @keyup.enter="sendTest" />
            <button type="button" style="background: linear-gradient(180deg,#14b8a6,#0e8f84); color: #fff; border: 0; border-radius: 8px; padding: 9px 14px; font-weight: 700; cursor: pointer" @click="sendTest">Send</button>
          </div>
        </section>
      </div>

      <button
        type="button"
        style="margin-top: 20px; background: transparent; border: 0; color: #ef4444; font-size: 12px; cursor: pointer"
        @click="deleteAgent(draft.id)"
      >Delete this agent</button>
    </div>
  </div>
</template>
