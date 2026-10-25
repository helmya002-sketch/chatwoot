<script setup>
import { ref, computed, onMounted } from 'vue';

// --- Workflows pillar (respond.io clone): list + visual node canvas.
// Shell UI; persists to localStorage. Data model maps to a future backend.
const STORE_KEY = 'tolzar_workflows_v1';

const TRIGGERS = [
  { type: 'conversation_opened', label: 'Conversation Opened' },
  { type: 'contact_created', label: 'Contact Created' },
  { type: 'contact_replied', label: 'Contact Replied' },
  { type: 'conversation_closed', label: 'Conversation Closed' },
  { type: 'webhook', label: 'Webhook' },
];
const STEP_TYPES = [
  { type: 'send_message', label: 'Send a Message', icon: 'i-lucide-message-circle', accent: '#3e63dd' },
  { type: 'ask_question', label: 'Ask a Question', icon: 'i-lucide-circle-help', accent: '#5472e4' },
  { type: 'branch', label: 'Branch', icon: 'i-lucide-git-branch', accent: '#f59e0b' },
  { type: 'assign', label: 'Assign To', icon: 'i-lucide-user-round', accent: '#0ea5e9' },
  { type: 'update_field', label: 'Update Contact Field', icon: 'i-lucide-square-pen', accent: '#8b5cf6' },
  { type: 'update_lifecycle', label: 'Update Lifecycle Stage', icon: 'i-lucide-target', accent: '#ec4899' },
  { type: 'add_tag', label: 'Add Tag', icon: 'i-lucide-tag', accent: '#10b981' },
  { type: 'comment', label: 'Add Comment', icon: 'i-lucide-message-square', accent: '#64748b' },
  { type: 'close', label: 'Close Conversation', icon: 'i-lucide-circle-check', accent: '#22c55e' },
  { type: 'trigger_workflow', label: 'Trigger Workflow', icon: 'i-lucide-workflow', accent: '#3e63dd' },
  { type: 'http', label: 'HTTP Request', icon: 'i-lucide-globe', accent: '#3b82f6' },
  { type: 'wait', label: 'Wait / Delay', icon: 'i-lucide-clock', accent: '#94a3b8' },
];
function stepMeta(type) {
  return STEP_TYPES.find(s => s.type === type) || { label: type, icon: 'i-lucide-circle-dot', accent: '#64748b' };
}
function triggerLabel(type) {
  return (TRIGGERS.find(t => t.type === type) || {}).label || type;
}

const flows = ref([]);
const selectedId = ref(null);
const draft = ref(null);
const loaded = ref(false);
const zoom = ref(1);

// config panel + palette state
const panel = ref(null); // { kind:'trigger' } | { kind:'node', ref } | null
const paletteFor = ref(null); // insert target: null | {branch:idx} for a branch path

function uid() {
  return 'w' + Math.random().toString(36).slice(2, 9);
}

function seed() {
  return [
    {
      id: uid(),
      name: 'Alex — welcome & route new contacts',
      status: 'published',
      trigger: { type: 'conversation_opened', config: '' },
      steps: [
        {
          id: uid(),
          type: 'branch',
          title: 'New or Returning Contact',
          config: '2 conditions provided',
          branches: [
            { label: 'New Contact', steps: [{ id: uid(), type: 'send_message', title: 'Send greeting', config: 'Hello $contact.name, greetings from Aquarius Diving Club!' }, { id: uid(), type: 'assign', title: 'Assign by location', config: 'Sharm → Francesca; Hurghada area → Hurghada Team' }] },
            { label: 'Returning Contact', steps: [{ id: uid(), type: 'assign', title: 'Assign to last agent', config: 'Route to previous assignee' }] },
            { label: 'Else', steps: [{ id: uid(), type: 'comment', title: 'Flag for review', config: 'Private note to team' }] },
          ],
        },
      ],
    },
    {
      id: uid(),
      name: 'Booking Won → Google Ads conversion',
      status: 'published',
      trigger: { type: 'contact_created', config: 'On Customer Won' },
      steps: [
        { id: uid(), type: 'http', title: 'Add row to Won-Bookings sheet', config: 'POST gclid, value, time' },
        { id: uid(), type: 'update_field', title: 'Mark exported', config: 'exported = true' },
      ],
    },
    {
      id: uid(),
      name: 'Fill User Field',
      status: 'draft',
      trigger: { type: 'webhook', config: '' },
      steps: [{ id: uid(), type: 'update_field', title: 'Save field', config: '' }],
    },
  ];
}

function load() {
  try {
    const raw = localStorage.getItem(STORE_KEY);
    flows.value = raw ? JSON.parse(raw) : seed();
    if (!raw) persist();
  } catch (e) {
    flows.value = seed();
  }
  loaded.value = true;
}
function persist() {
  try {
    localStorage.setItem(STORE_KEY, JSON.stringify(flows.value));
  } catch (e) {
    /* storage unavailable */
  }
}

function openFlow(id) {
  selectedId.value = id;
  draft.value = JSON.parse(JSON.stringify(flows.value.find(f => f.id === id)));
  panel.value = null;
  zoom.value = 1;
}
function createFlow() {
  const f = { id: uid(), name: 'New Workflow', status: 'draft', trigger: { type: 'conversation_opened', config: '' }, steps: [] };
  flows.value.push(f);
  persist();
  openFlow(f.id);
}
function backToList() {
  selectedId.value = null;
  draft.value = null;
  panel.value = null;
}
function saveFlow() {
  const i = flows.value.findIndex(f => f.id === draft.value.id);
  if (i >= 0) flows.value[i] = JSON.parse(JSON.stringify(draft.value));
  persist();
  backToList();
}
function deleteFlow(id) {
  // eslint-disable-next-line no-alert
  if (!window.confirm('Delete this workflow?')) return;
  flows.value = flows.value.filter(f => f.id !== id);
  persist();
  if (selectedId.value === id) backToList();
}

// ---- builder edits ----
function addStep(type, branchIdx) {
  const meta = stepMeta(type);
  const node = { id: uid(), type, title: meta.label, config: '' };
  if (type === 'branch') {
    node.branches = [
      { label: 'Path 1', steps: [] },
      { label: 'Else', steps: [] },
    ];
  }
  if (branchIdx == null) draft.value.steps.push(node);
  else draft.value.steps.find(s => s.type === 'branch')?.branches[branchIdx].steps.push(node);
  paletteFor.value = null;
  selectNode(node);
}
function removeStep(node, branchIdx) {
  if (branchIdx == null) {
    draft.value.steps = draft.value.steps.filter(s => s.id !== node.id);
  } else {
    const br = draft.value.steps.find(s => s.type === 'branch');
    br.branches[branchIdx].steps = br.branches[branchIdx].steps.filter(s => s.id !== node.id);
  }
  if (panel.value && panel.value.node && panel.value.node.id === node.id) panel.value = null;
}
function addPath() {
  const br = draft.value.steps.find(s => s.type === 'branch');
  if (br) br.branches.push({ label: 'New path', steps: [] });
}
function selectNode(node) {
  panel.value = { kind: 'node', node };
}
function selectTrigger() {
  panel.value = { kind: 'trigger' };
}
function openPalette(branchIdx) {
  paletteFor.value = branchIdx == null ? { branch: null } : { branch: branchIdx };
}

const stepCount = computed(() => {
  if (!draft.value) return 0;
  let n = 0;
  for (const s of draft.value.steps) {
    n += 1;
    if (s.branches) for (const b of s.branches) n += b.steps.length;
  }
  return n;
});
const branchNode = computed(() => draft.value && draft.value.steps.find(s => s.type === 'branch'));
const linearSteps = computed(() => (draft.value ? draft.value.steps.filter(s => s.type !== 'branch') : []));

function nodeStyle(accent) {
  return { borderTop: `3px solid ${accent}` };
}

onMounted(load);
</script>

<template>
  <div class="overflow-auto flex-1 bg-n-background" data-tz-build="workflows-3">
    <!-- ===================== LIST VIEW ===================== -->
    <div v-if="!selectedId" class="mx-auto max-w-[1120px] px-5 pb-16 pt-7 md:px-6">
      <div class="flex gap-4 justify-between items-center tz-rise">
        <div class="flex gap-3 items-center">
          <span class="tz-mark grid flex-shrink-0 place-content-center rounded-2xl size-11">
            <span class="i-lucide-workflow size-6 text-white" />
          </span>
          <div>
            <div class="flex gap-2 items-center">
              <h1 class="m-0 text-[22px] font-extrabold tracking-tight text-n-slate-12">Workflows</h1>
              <span class="inline-flex gap-1 items-center px-2 py-0.5 text-[11px] font-semibold rounded-full text-amber-600 bg-amber-500/10 dark:text-amber-400">
                <span class="inline-block rounded-full size-1.5 bg-amber-500" /> Preview
              </span>
            </div>
            <p class="m-0 text-sm text-n-slate-11">Design automations visually. Saved as drafts — they don't run yet.</p>
          </div>
        </div>
        <button type="button" class="tz-btn-primary" @click="createFlow"><span class="i-lucide-plus size-4" /> Add Workflow</button>
      </div>

      <div class="tz-rise overflow-hidden mt-5 rounded-2xl border shadow-sm bg-n-solid-1 border-n-weak" style="animation-delay: 60ms">
        <div class="grid gap-3 px-[18px] py-3 text-xs font-bold uppercase tracking-wide border-b grid-cols-[110px_1fr_180px_130px_80px] text-n-slate-10 bg-n-alpha-1 border-n-weak">
          <div>Status</div><div>Name</div><div>Trigger</div><div>Steps</div><div></div>
        </div>
        <div
          v-for="f in flows"
          :key="f.id"
          class="grid gap-3 items-center px-[18px] py-3.5 border-b transition-colors cursor-pointer grid-cols-[110px_1fr_180px_130px_80px] border-n-weak last:border-0 hover:bg-n-alpha-1"
          @click="openFlow(f.id)"
        >
          <div>
            <span
              class="inline-flex gap-1 items-center px-2.5 py-0.5 text-[11px] font-bold rounded-full"
              :class="f.status === 'published' ? 'text-sky-600 bg-sky-500/10 dark:text-sky-400' : 'text-n-slate-11 bg-n-alpha-2'"
            >
              <span class="inline-block rounded-full size-1.5" :class="f.status === 'published' ? 'bg-sky-500' : 'bg-n-slate-9'" />
              {{ f.status === 'published' ? 'Preview' : 'Draft' }}
            </span>
          </div>
          <div class="font-semibold truncate text-n-slate-12">{{ f.name }}</div>
          <div class="text-[13px] text-n-slate-11">{{ triggerLabel(f.trigger.type) }}</div>
          <div class="text-[13px] text-n-slate-10">{{ f.steps.length }} top-level</div>
          <div class="inline-flex gap-1 items-center text-[13px] font-bold text-n-brand">Edit <span class="i-lucide-arrow-right size-3.5 rtl:rotate-180" /></div>
        </div>
        <div v-if="!flows.length" class="p-6 text-center text-n-slate-10">No workflows yet.</div>
      </div>
    </div>

    <!-- ===================== BUILDER VIEW ===================== -->
    <div v-else-if="draft" class="flex flex-col h-full">
      <!-- header -->
      <div class="flex flex-wrap gap-3 items-center px-[18px] py-3 border-b bg-n-solid-1 border-n-weak">
        <button type="button" class="tz-btn-ghost" @click="backToList">‹ Back</button>
        <input v-model="draft.name" class="flex-1 px-2 py-1 min-w-[160px] w-auto text-base font-extrabold rounded-lg border border-transparent outline-none text-n-slate-12 bg-n-background focus:border-n-weak" />
        <span class="flex-shrink-0 text-xs whitespace-nowrap text-n-slate-10">Steps: {{ stepCount }} / 100</span>
        <select v-model="draft.status" class="tz-in flex-shrink-0 !w-[130px]">
          <option value="draft">Draft</option>
          <option value="published">Published</option>
        </select>
        <button type="button" class="tz-btn-ghost" @click="backToList">Cancel</button>
        <button type="button" class="tz-btn-primary" @click="saveFlow"><span class="i-lucide-check size-4" /> Save</button>
      </div>

      <div class="flex flex-1 min-h-0">
        <!-- canvas -->
        <div class="tz-canvas overflow-auto relative flex-1 bg-n-background">
          <!-- zoom controls -->
          <div class="flex overflow-hidden absolute top-3.5 left-3.5 z-10 flex-col rounded-xl border shadow-sm bg-n-solid-1 border-n-weak">
            <button type="button" class="px-2.5 py-2 border-b transition-colors border-n-weak text-n-slate-11 hover:bg-n-alpha-1" @click="zoom = Math.min(1.4, zoom + 0.1)"><span class="i-lucide-plus size-4" /></button>
            <button type="button" class="px-2.5 py-2 border-b transition-colors border-n-weak text-n-slate-11 hover:bg-n-alpha-1" @click="zoom = Math.max(0.6, zoom - 0.1)"><span class="i-lucide-minus size-4" /></button>
            <button type="button" class="px-2.5 py-2 transition-colors text-n-slate-11 hover:bg-n-alpha-1" @click="zoom = 1"><span class="i-lucide-locate-fixed size-4" /></button>
          </div>

          <div class="flex flex-col items-center px-5 pt-10 pb-20" :style="{ transform: `scale(${zoom})`, transformOrigin: 'top center' }">
            <!-- Trigger -->
            <div class="overflow-hidden w-[230px] rounded-xl border shadow-sm cursor-pointer bg-n-solid-1 border-n-weak" style="border-top: 3px solid #e11d48" @click="selectTrigger">
              <div class="flex gap-2 items-center px-3.5 py-2.5 font-bold border-b border-n-weak text-n-slate-12">
                <span class="i-lucide-zap size-4" style="color: #e11d48" /> Trigger
              </div>
              <div class="px-3.5 py-2.5 text-[13px] text-n-slate-11">{{ triggerLabel(draft.trigger.type) }}</div>
            </div>

            <!-- linear steps -->
            <template v-for="node in linearSteps" :key="node.id">
              <span class="tz-wire" />
              <button type="button" class="tz-add-dot" @click="openPalette(null)"><span class="i-lucide-plus size-3" /></button>
              <span class="tz-wire" />
              <div class="overflow-hidden w-[240px] rounded-xl border shadow-sm cursor-pointer bg-n-solid-1 border-n-weak" :style="nodeStyle(stepMeta(node.type).accent)" @click="selectNode(node)">
                <div class="flex gap-2 items-center px-3.5 py-2.5 border-b border-n-weak">
                  <span :class="stepMeta(node.type).icon" class="size-4" :style="{ color: stepMeta(node.type).accent }" />
                  <span class="flex-1 text-[13px] font-bold text-n-slate-12">{{ node.title || stepMeta(node.type).label }}</span>
                  <button type="button" class="grid place-content-center rounded transition-colors size-5 text-n-slate-9 hover:text-rose-500 hover:bg-n-alpha-2" @click.stop="removeStep(node, null)"><span class="i-lucide-x size-3.5" /></button>
                </div>
                <div v-if="node.config" class="px-3.5 py-2 text-xs text-n-slate-10">{{ node.config }}</div>
              </div>
            </template>

            <!-- branch node (one level) -->
            <template v-if="branchNode">
              <span class="tz-wire" />
              <button v-if="!linearSteps.length" type="button" class="tz-add-dot" @click="openPalette(null)"><span class="i-lucide-plus size-3" /></button>
              <span v-if="!linearSteps.length" class="tz-wire" />
              <div class="w-[240px] overflow-hidden rounded-xl border shadow-sm cursor-pointer bg-n-solid-1 border-n-weak" style="border-top: 3px solid #f59e0b" @click="selectNode(branchNode)">
                <div class="flex gap-2 items-center px-3.5 py-2.5 border-b border-n-weak">
                  <span class="i-lucide-git-branch size-4" style="color: #f59e0b" /><span class="flex-1 text-[13px] font-bold text-n-slate-12">{{ branchNode.title }}</span>
                  <button type="button" class="grid place-content-center rounded transition-colors size-5 text-n-slate-9 hover:text-rose-500 hover:bg-n-alpha-2" @click.stop="removeStep(branchNode, null)"><span class="i-lucide-x size-3.5" /></button>
                </div>
                <div class="px-3.5 py-2 text-xs text-n-slate-10">{{ branchNode.branches.length }} paths</div>
              </div>

              <!-- branch paths as columns -->
              <span class="w-0.5 h-4" style="background: #f59e0b" />
              <div class="flex flex-wrap gap-5 justify-center items-start">
                <div v-for="(b, bi) in branchNode.branches" :key="bi" class="flex flex-col items-center min-w-[200px]">
                  <span class="px-2.5 py-0.5 text-[11px] font-bold rounded-full text-amber-700 bg-amber-100 dark:text-amber-300 dark:bg-amber-500/15">{{ b.label }}</span>
                  <template v-for="snode in b.steps" :key="snode.id">
                    <span class="tz-wire !h-3" />
                    <div class="w-[200px] overflow-hidden rounded-xl border shadow-sm cursor-pointer bg-n-solid-1 border-n-weak" :style="nodeStyle(stepMeta(snode.type).accent)" @click="selectNode(snode)">
                      <div class="flex gap-1.5 items-center px-3 py-2">
                        <span :class="stepMeta(snode.type).icon" class="size-3.5" :style="{ color: stepMeta(snode.type).accent }" />
                        <span class="flex-1 text-[12.5px] font-semibold text-n-slate-12">{{ snode.title }}</span>
                        <button type="button" class="grid place-content-center rounded transition-colors size-5 text-n-slate-9 hover:text-rose-500 hover:bg-n-alpha-2" @click.stop="removeStep(snode, bi)"><span class="i-lucide-x size-3" /></button>
                      </div>
                    </div>
                  </template>
                  <span class="tz-wire !h-2.5" />
                  <button type="button" class="inline-flex gap-1 items-center px-2.5 py-1 text-xs rounded-lg border border-dashed transition-colors cursor-pointer border-n-strong text-n-brand bg-n-solid-1 hover:bg-n-alpha-1" @click="openPalette(bi)"><span class="i-lucide-plus size-3" /> Add</button>
                </div>
                <button type="button" class="self-center px-3 py-1.5 text-xs rounded-lg border border-dashed transition-colors cursor-pointer border-n-strong text-n-slate-11 bg-n-solid-1 hover:bg-n-alpha-1" @click="addPath">+ Path</button>
              </div>
            </template>

            <!-- add first / next step when no branch -->
            <template v-if="!branchNode">
              <span class="tz-wire" />
              <button type="button" class="inline-flex gap-1.5 items-center px-4 py-2 text-[13px] font-semibold rounded-xl border border-dashed transition-colors cursor-pointer border-n-strong text-n-brand bg-n-solid-1 hover:bg-n-alpha-1" @click="openPalette(null)"><span class="i-lucide-plus size-3.5" /> Add step</button>
            </template>
          </div>
        </div>

        <!-- right panel: config OR palette -->
        <div v-if="panel || paletteFor" class="overflow-auto flex-shrink-0 p-[18px] w-[340px] border-l bg-n-solid-1 border-n-weak">
          <!-- palette -->
          <template v-if="paletteFor">
            <div class="flex justify-between items-center mb-3">
              <h3 class="m-0 text-[15px] font-semibold text-n-slate-12">Add a step</h3>
              <button type="button" class="grid place-content-center rounded-lg transition-colors size-7 text-n-slate-10 hover:bg-n-alpha-2" @click="paletteFor = null"><span class="i-lucide-x size-4" /></button>
            </div>
            <button
              v-for="s in STEP_TYPES"
              :key="s.type"
              type="button"
              :disabled="s.type === 'branch' && (paletteFor.branch !== null || !!branchNode)"
              class="flex gap-2.5 items-center px-3 py-2.5 mb-2 w-full text-left rounded-xl border transition-colors cursor-pointer border-n-weak hover:bg-n-alpha-1 disabled:opacity-40 disabled:cursor-not-allowed"
              @click="addStep(s.type, paletteFor.branch)"
            >
              <span class="grid place-content-center rounded-lg size-[26px]" :style="{ background: s.accent + '1f' }"><span :class="s.icon" class="size-4" :style="{ color: s.accent }" /></span>
              <span class="text-[13px] font-semibold text-n-slate-12">{{ s.label }}</span>
            </button>
          </template>

          <!-- node / trigger config -->
          <template v-else-if="panel && panel.kind === 'trigger'">
            <div class="flex justify-between items-center mb-3">
              <h3 class="inline-flex gap-1.5 items-center m-0 text-[15px] font-semibold text-n-slate-12"><span class="i-lucide-zap size-4" style="color: #e11d48" /> Trigger</h3>
              <button type="button" class="grid place-content-center rounded-lg transition-colors size-7 text-n-slate-10 hover:bg-n-alpha-2" @click="panel = null"><span class="i-lucide-x size-4" /></button>
            </div>
            <label class="block mb-1 text-xs text-n-slate-11">When this happens</label>
            <select v-model="draft.trigger.type" class="tz-in mb-3">
              <option v-for="t in TRIGGERS" :key="t.type" :value="t.type">{{ t.label }}</option>
            </select>
            <label class="block mb-1 text-xs text-n-slate-11">Condition (optional)</label>
            <input v-model="draft.trigger.config" class="tz-in" placeholder="e.g. On Customer Won" />
          </template>

          <template v-else-if="panel && panel.kind === 'node'">
            <div class="flex justify-between items-center mb-3">
              <h3 class="inline-flex gap-2 items-center m-0 text-[15px] font-semibold text-n-slate-12">
                <span :class="stepMeta(panel.node.type).icon" class="size-4" :style="{ color: stepMeta(panel.node.type).accent }" />{{ stepMeta(panel.node.type).label }}
              </h3>
              <button type="button" class="grid place-content-center rounded-lg transition-colors size-7 text-n-slate-10 hover:bg-n-alpha-2" @click="panel = null"><span class="i-lucide-x size-4" /></button>
            </div>
            <label class="block mb-1 text-xs text-n-slate-11">Title</label>
            <input v-model="panel.node.title" class="tz-in mb-3" />
            <label class="block mb-1 text-xs text-n-slate-11">Configuration</label>
            <textarea v-model="panel.node.config" rows="5" class="tz-in resize-y" placeholder="Describe what this step does…"></textarea>
            <template v-if="panel.node.type === 'branch'">
              <label class="block mt-3 mb-1 text-xs text-n-slate-11">Paths</label>
              <div v-for="(b, bi) in panel.node.branches" :key="bi" class="flex gap-1.5 mb-1.5">
                <input v-model="b.label" class="flex-1 tz-in" />
                <button type="button" class="grid place-content-center rounded-lg transition-colors size-8 text-n-slate-10 hover:text-rose-500 hover:bg-n-alpha-2" @click="panel.node.branches.splice(bi, 1)"><span class="i-lucide-x size-4" /></button>
              </div>
            </template>
          </template>
        </div>
      </div>

      <div class="px-[18px] py-2.5 border-t bg-n-solid-1 border-n-weak">
        <button type="button" class="inline-flex gap-1 items-center text-xs transition-colors text-n-slate-10 hover:text-rose-500" @click="deleteFlow(draft.id)"><span class="i-lucide-trash-2 size-3.5" /> Delete this workflow</button>
      </div>
    </div>
  </div>
</template>

<style scoped>
.tz-mark {
  background: linear-gradient(140deg, #5472e4, #3e63dd);
  box-shadow: 0 8px 20px -6px rgba(62, 99, 221, 0.5);
}
.tz-canvas {
  background-image: radial-gradient(rgba(100, 116, 139, 0.18) 1px, transparent 1px);
  background-size: 22px 22px;
}
.tz-wire {
  width: 2px;
  height: 0.875rem;
  background: rgb(var(--border-strong));
}
.tz-add-dot {
  display: grid;
  place-content: center;
  width: 22px;
  height: 22px;
  color: #3e63dd;
  background: rgb(var(--solid-1));
  border: 1px dashed rgb(var(--border-strong));
  border-radius: 9999px;
  cursor: pointer;
}
.tz-add-dot:hover {
  background: rgba(var(--alpha-1));
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
  transition: background 0.15s, box-shadow 0.15s;
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
