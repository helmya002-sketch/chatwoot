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
  { type: 'send_message', label: 'Send a Message', icon: 'i-lucide-message-circle', accent: '#12a594' },
  { type: 'ask_question', label: 'Ask a Question', icon: 'i-lucide-circle-help', accent: '#6366f1' },
  { type: 'branch', label: 'Branch', icon: 'i-lucide-git-branch', accent: '#f59e0b' },
  { type: 'assign', label: 'Assign To', icon: 'i-lucide-user-round', accent: '#0ea5e9' },
  { type: 'update_field', label: 'Update Contact Field', icon: 'i-lucide-square-pen', accent: '#8b5cf6' },
  { type: 'update_lifecycle', label: 'Update Lifecycle Stage', icon: 'i-lucide-target', accent: '#ec4899' },
  { type: 'add_tag', label: 'Add Tag', icon: 'i-lucide-tag', accent: '#10b981' },
  { type: 'comment', label: 'Add Comment', icon: 'i-lucide-message-square', accent: '#64748b' },
  { type: 'close', label: 'Close Conversation', icon: 'i-lucide-circle-check', accent: '#22c55e' },
  { type: 'trigger_workflow', label: 'Trigger Workflow', icon: 'i-lucide-workflow', accent: '#0e8f84' },
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

onMounted(load);
</script>

<template>
  <div class="flex-1 overflow-auto" data-tz-build="workflows-2" style="background: #f5f8fc">
    <!-- ===================== LIST VIEW ===================== -->
    <div v-if="!selectedId" style="max-width: 1120px; margin: 0 auto; padding: 32px 24px 64px">
      <div style="display: flex; align-items: center; justify-content: space-between">
        <div>
          <h1 style="font-size: 24px; font-weight: 800; color: #0b1f3a; margin: 0 0 2px">Workflows</h1>
          <p style="color: #64748b; margin: 0">Automate conversations — triggers, branches and steps.</p>
        </div>
        <button type="button" style="background: linear-gradient(180deg,#14b8a6,#0e8f84); color: #fff; border: 0; border-radius: 10px; padding: 10px 16px; font-weight: 700; cursor: pointer" @click="createFlow">+ Add Workflow</button>
      </div>

      <div style="margin-top: 22px; background: #fff; border: 1px solid #e3e9f2; border-radius: 14px; overflow: hidden">
        <div style="display: grid; grid-template-columns: 110px 1fr 180px 130px 90px; gap: 12px; padding: 12px 18px; font-size: 12px; font-weight: 700; color: #64748b; background: #f8fafc; border-bottom: 1px solid #eef2f7">
          <div>Status</div><div>Name</div><div>Trigger</div><div>Steps</div><div></div>
        </div>
        <div v-for="f in flows" :key="f.id" style="display: grid; grid-template-columns: 110px 1fr 180px 130px 90px; gap: 12px; padding: 14px 18px; align-items: center; border-bottom: 1px solid #f1f5f9; cursor: pointer" @click="openFlow(f.id)">
          <div>
            <span :style="{ fontSize: '11px', fontWeight: '700', padding: '2px 9px', borderRadius: '999px', color: f.status === 'published' ? '#0e8f84' : '#9a6b00', background: f.status === 'published' ? '#d8f5f0' : '#fef3c7' }">{{ f.status === 'published' ? 'Published' : 'Draft' }}</span>
          </div>
          <div style="font-weight: 600; color: #0b1f3a">{{ f.name }}</div>
          <div style="color: #475569; font-size: 13px">{{ triggerLabel(f.trigger.type) }}</div>
          <div style="color: #64748b; font-size: 13px">{{ f.steps.length }} top-level</div>
          <div style="font-weight: 700; color: #12a594; font-size: 13px">Edit →</div>
        </div>
        <div v-if="!flows.length" style="padding: 24px; text-align: center; color: #94a3b8">No workflows yet.</div>
      </div>
    </div>

    <!-- ===================== BUILDER VIEW ===================== -->
    <div v-else-if="draft" style="height: 100%; display: flex; flex-direction: column">
      <!-- header -->
      <div style="display: flex; align-items: center; gap: 12px; padding: 12px 18px; background: #fff; border-bottom: 1px solid #e3e9f2">
        <button type="button" style="background: #fff; border: 1px solid #e3e9f2; border-radius: 8px; padding: 6px 12px; cursor: pointer; color: #475569; font-weight: 600" @click="backToList">‹ Back</button>
        <input v-model="draft.name" style="font-size: 16px; font-weight: 800; color: #0b1f3a; border: 1px solid transparent; border-radius: 8px; padding: 4px 8px; flex: 1 1 200px; min-width: 160px; width: auto" @focus="$event.target.style.borderColor = '#e3e9f2'" @blur="$event.target.style.borderColor = 'transparent'" />
        <span style="font-size: 12px; color: #94a3b8; flex: 0 0 auto; white-space: nowrap">Steps: {{ stepCount }} / 100</span>
        <select v-model="draft.status" style="border: 1px solid #e3e9f2; border-radius: 8px; padding: 6px 10px; font-size: 13px; background: #fff; flex: 0 0 auto; width: 130px">
          <option value="draft">Draft</option>
          <option value="published">Published</option>
        </select>
        <button type="button" style="background: #fff; border: 1px solid #e3e9f2; border-radius: 8px; padding: 8px 16px; cursor: pointer; color: #475569; font-weight: 600" @click="backToList">Cancel</button>
        <button type="button" style="background: linear-gradient(180deg,#14b8a6,#0e8f84); color: #fff; border: 0; border-radius: 8px; padding: 8px 18px; font-weight: 700; cursor: pointer" @click="saveFlow">Save</button>
      </div>

      <div style="flex: 1; display: flex; min-height: 0">
        <!-- canvas -->
        <div style="flex: 1; overflow: auto; position: relative; background-color: #f5f8fc; background-image: radial-gradient(#d7e0ec 1px, transparent 1px); background-size: 22px 22px">
          <!-- zoom controls -->
          <div style="position: absolute; top: 14px; left: 14px; z-index: 2; background: #fff; border: 1px solid #e3e9f2; border-radius: 10px; display: flex; flex-direction: column; overflow: hidden">
            <button type="button" style="border: 0; background: #fff; padding: 8px 10px; cursor: pointer; border-bottom: 1px solid #eef2f7" @click="zoom = Math.min(1.4, zoom + 0.1)">+</button>
            <button type="button" style="border: 0; background: #fff; padding: 8px 10px; cursor: pointer; border-bottom: 1px solid #eef2f7" @click="zoom = Math.max(0.6, zoom - 0.1)">−</button>
            <button type="button" style="border: 0; background: #fff; padding: 8px 10px; cursor: pointer; font-size: 12px" @click="zoom = 1">⊙</button>
          </div>

          <div :style="{ transform: `scale(${zoom})`, transformOrigin: 'top center', padding: '40px 20px 80px', display: 'flex', flexDirection: 'column', alignItems: 'center' }">
            <!-- Trigger -->
            <div
              style="width: 230px; background: #fff; border: 1px solid #f3c6c6; border-top: 3px solid #e11d48; border-radius: 12px; box-shadow: 0 3px 10px rgba(15,31,58,.06); cursor: pointer"
              @click="selectTrigger"
            >
              <div style="padding: 10px 14px; border-bottom: 1px solid #f6e4e4; font-weight: 700; color: #0b1f3a; display: flex; align-items: center; gap: 8px">
                <span class="i-lucide-zap" style="color: #e11d48; font-size: 15px"></span> Trigger
              </div>
              <div style="padding: 10px 14px; color: #475569; font-size: 13px">{{ triggerLabel(draft.trigger.type) }}</div>
            </div>

            <!-- linear steps -->
            <template v-for="(node, i) in linearSteps" :key="node.id">
              <div style="width: 2px; height: 14px; background: #c6d2e3"></div>
              <button type="button" style="border: 1px dashed #c6d2e3; background: #fff; color: #12a594; border-radius: 50%; width: 22px; height: 22px; cursor: pointer; font-weight: 700; line-height: 1" @click="openPalette(null)">+</button>
              <div style="width: 2px; height: 14px; background: #c6d2e3"></div>
              <div
                :style="{ width: '240px', background: '#fff', border: '1px solid #e3e9f2', borderTop: '3px solid ' + stepMeta(node.type).accent, borderRadius: '12px', boxShadow: '0 3px 10px rgba(15,31,58,.06)', cursor: 'pointer' }"
                @click="selectNode(node)"
              >
                <div style="padding: 10px 14px; border-bottom: 1px solid #f1f5f9; display: flex; align-items: center; gap: 8px">
                  <span :class="stepMeta(node.type).icon" :style="{ color: stepMeta(node.type).accent, fontSize: '16px' }"></span>
                  <span style="font-weight: 700; color: #0b1f3a; flex: 1; font-size: 13px">{{ node.title || stepMeta(node.type).label }}</span>
                  <button type="button" style="border: 0; background: transparent; color: #cbd5e1; cursor: pointer; font-size: 14px" @click.stop="removeStep(node, null)">×</button>
                </div>
                <div v-if="node.config" style="padding: 8px 14px; color: #64748b; font-size: 12px">{{ node.config }}</div>
              </div>
            </template>

            <!-- branch node (one level) -->
            <template v-if="branchNode">
              <div style="width: 2px; height: 14px; background: #c6d2e3"></div>
              <button v-if="!linearSteps.length" type="button" style="border: 1px dashed #c6d2e3; background: #fff; color: #12a594; border-radius: 50%; width: 22px; height: 22px; cursor: pointer; font-weight: 700; line-height: 1" @click="openPalette(null)">+</button>
              <div v-if="!linearSteps.length" style="width: 2px; height: 14px; background: #c6d2e3"></div>
              <div style="width: 240px; background: #fff; border: 1px solid #fde4b8; border-top: 3px solid #f59e0b; border-radius: 12px; box-shadow: 0 3px 10px rgba(15,31,58,.06); cursor: pointer" @click="selectNode(branchNode)">
                <div style="padding: 10px 14px; border-bottom: 1px solid #fdf0d8; display: flex; align-items: center; gap: 8px">
                  <span class="i-lucide-git-branch" style="color: #f59e0b; font-size: 15px"></span><span style="font-weight: 700; color: #0b1f3a; flex: 1; font-size: 13px">{{ branchNode.title }}</span>
                  <button type="button" style="border: 0; background: transparent; color: #cbd5e1; cursor: pointer; font-size: 14px" @click.stop="removeStep(branchNode, null)">×</button>
                </div>
                <div style="padding: 8px 14px; color: #64748b; font-size: 12px">{{ branchNode.branches.length }} paths</div>
              </div>

              <!-- branch paths as columns -->
              <div style="width: 2px; height: 16px; background: #f59e0b"></div>
              <div style="display: flex; gap: 20px; align-items: flex-start; flex-wrap: wrap; justify-content: center">
                <div v-for="(b, bi) in branchNode.branches" :key="bi" style="display: flex; flex-direction: column; align-items: center; min-width: 200px">
                  <span style="font-size: 11px; font-weight: 700; color: #b45309; background: #fef3c7; padding: 2px 10px; border-radius: 999px">{{ b.label }}</span>
                  <template v-for="snode in b.steps" :key="snode.id">
                    <div style="width: 2px; height: 12px; background: #c6d2e3"></div>
                    <div :style="{ width: '200px', background: '#fff', border: '1px solid #e3e9f2', borderTop: '3px solid ' + stepMeta(snode.type).accent, borderRadius: '12px', boxShadow: '0 2px 8px rgba(15,31,58,.05)', cursor: 'pointer' }" @click="selectNode(snode)">
                      <div style="padding: 9px 12px; display: flex; align-items: center; gap: 7px">
                        <span :class="stepMeta(snode.type).icon" :style="{ color: stepMeta(snode.type).accent, fontSize: '14px' }"></span>
                        <span style="font-weight: 600; color: #0b1f3a; flex: 1; font-size: 12.5px">{{ snode.title }}</span>
                        <button type="button" style="border: 0; background: transparent; color: #cbd5e1; cursor: pointer; font-size: 13px" @click.stop="removeStep(snode, bi)">×</button>
                      </div>
                    </div>
                  </template>
                  <div style="width: 2px; height: 10px; background: #c6d2e3"></div>
                  <button type="button" style="border: 1px dashed #c6d2e3; background: #fff; color: #12a594; border-radius: 8px; padding: 4px 10px; cursor: pointer; font-size: 12px" @click="openPalette(bi)">+ Add</button>
                </div>
                <button type="button" style="border: 1px dashed #c6d2e3; background: #fff; color: #64748b; border-radius: 8px; padding: 6px 12px; cursor: pointer; font-size: 12px; align-self: center" @click="addPath">+ Path</button>
              </div>
            </template>

            <!-- add first / next step when no branch -->
            <template v-if="!branchNode">
              <div style="width: 2px; height: 14px; background: #c6d2e3"></div>
              <button type="button" style="border: 1px dashed #c6d2e3; background: #fff; color: #12a594; border-radius: 10px; padding: 8px 16px; cursor: pointer; font-weight: 600; font-size: 13px" @click="openPalette(null)">+ Add step</button>
            </template>
          </div>
        </div>

        <!-- right panel: config OR palette -->
        <div v-if="panel || paletteFor" style="width: 340px; flex-shrink: 0; background: #fff; border-left: 1px solid #e3e9f2; overflow: auto; padding: 18px">
          <!-- palette -->
          <template v-if="paletteFor">
            <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 12px">
              <h3 style="margin: 0; font-size: 15px; color: #0b1f3a">Add a step</h3>
              <button type="button" style="border: 0; background: transparent; color: #94a3b8; cursor: pointer; font-size: 18px" @click="paletteFor = null">×</button>
            </div>
            <button
              v-for="s in STEP_TYPES"
              :key="s.type"
              type="button"
              :disabled="s.type === 'branch' && (paletteFor.branch !== null || !!branchNode)"
              style="display: flex; align-items: center; gap: 10px; width: 100%; text-align: left; background: #fff; border: 1px solid #eef2f7; border-radius: 10px; padding: 10px 12px; margin-bottom: 8px; cursor: pointer"
              @click="addStep(s.type, paletteFor.branch)"
            >
              <span :style="{ width: '26px', height: '26px', borderRadius: '7px', display: 'grid', placeContent: 'center', background: s.accent + '1a' }"><span :class="s.icon" :style="{ color: s.accent, fontSize: '15px' }"></span></span>
              <span style="font-weight: 600; color: #0b1f3a; font-size: 13px">{{ s.label }}</span>
            </button>
          </template>

          <!-- node / trigger config -->
          <template v-else-if="panel && panel.kind === 'trigger'">
            <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 12px">
              <h3 style="margin: 0; font-size: 15px; color: #0b1f3a">Trigger</h3>
              <button type="button" style="border: 0; background: transparent; color: #94a3b8; cursor: pointer; font-size: 18px" @click="panel = null">×</button>
            </div>
            <label style="display: block; font-size: 12px; color: #64748b; margin-bottom: 4px">When this happens</label>
            <select v-model="draft.trigger.type" style="width: 100%; border: 1px solid #e3e9f2; border-radius: 8px; padding: 9px; font-size: 13px; margin-bottom: 12px; background: #fff">
              <option v-for="t in TRIGGERS" :key="t.type" :value="t.type">{{ t.label }}</option>
            </select>
            <label style="display: block; font-size: 12px; color: #64748b; margin-bottom: 4px">Condition (optional)</label>
            <input v-model="draft.trigger.config" style="width: 100%; box-sizing: border-box; border: 1px solid #e3e9f2; border-radius: 8px; padding: 9px; font-size: 13px" placeholder="e.g. On Customer Won" />
          </template>

          <template v-else-if="panel && panel.kind === 'node'">
            <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 12px">
              <h3 style="margin: 0; font-size: 15px; color: #0b1f3a; display: flex; align-items: center; gap: 8px">
                <span :class="stepMeta(panel.node.type).icon" :style="{ color: stepMeta(panel.node.type).accent, fontSize: '16px' }"></span>{{ stepMeta(panel.node.type).label }}
              </h3>
              <button type="button" style="border: 0; background: transparent; color: #94a3b8; cursor: pointer; font-size: 18px" @click="panel = null">×</button>
            </div>
            <label style="display: block; font-size: 12px; color: #64748b; margin-bottom: 4px">Title</label>
            <input v-model="panel.node.title" style="width: 100%; box-sizing: border-box; border: 1px solid #e3e9f2; border-radius: 8px; padding: 9px; font-size: 13px; margin-bottom: 12px" />
            <label style="display: block; font-size: 12px; color: #64748b; margin-bottom: 4px">Configuration</label>
            <textarea v-model="panel.node.config" rows="5" style="width: 100%; box-sizing: border-box; border: 1px solid #e3e9f2; border-radius: 8px; padding: 9px; font-size: 13px; resize: vertical" placeholder="Describe what this step does…"></textarea>
            <template v-if="panel.node.type === 'branch'">
              <label style="display: block; font-size: 12px; color: #64748b; margin: 12px 0 4px">Paths</label>
              <div v-for="(b, bi) in panel.node.branches" :key="bi" style="display: flex; gap: 6px; margin-bottom: 6px">
                <input v-model="b.label" style="flex: 1; border: 1px solid #e3e9f2; border-radius: 8px; padding: 7px; font-size: 12px" />
                <button type="button" style="border: 0; background: transparent; color: #cbd5e1; cursor: pointer" @click="panel.node.branches.splice(bi, 1)">×</button>
              </div>
            </template>
          </template>
        </div>
      </div>

      <div style="padding: 10px 18px; background: #fff; border-top: 1px solid #e3e9f2">
        <button type="button" style="background: transparent; border: 0; color: #ef4444; font-size: 12px; cursor: pointer" @click="deleteFlow(draft.id)">Delete this workflow</button>
      </div>
    </div>
  </div>
</template>
