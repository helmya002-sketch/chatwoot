<script setup>
import { ref, computed, onMounted } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import WorkflowSteps from 'dashboard/components-next/Tolzar/WorkflowSteps.vue';
import { normaliseBranches,
  STEP_TYPES,
  TRIGGERS,
  CONDITIONS,
  stepMeta,
  newStep,
  uid,
} from 'dashboard/components-next/Tolzar/tolzarWorkflows';

// --- Workflows (roadmap B1): real, server-side. The brain stores, validates and runs them;
// everything runs in Shadow (a send is a private "would send" note). Approved mock: workflows-v1.
const accountId = useMapGetter('getCurrentAccountId');
const api = computed(() => `/api/v1/accounts/${accountId.value}/tolzar/workflows`);

const flows = ref([]);
const stats = ref({});
const templates = ref([]);
const loading = ref(true);
const draft = ref(null);
const isNew = ref(false);
const selected = ref(null); // a step object, or 'trigger' / 'settings'
const palette = ref(null); // { list, at } where a new step goes
const tab = ref('flow');
const errors = ref([]);
const saving = ref(false);
const runs = ref([]);
const test = ref({ conversationId: '', replied: true, result: null, busy: false });
const lang = ref('en');

const clone = o => JSON.parse(JSON.stringify(o));

async function load() {
  loading.value = true;
  try {
    const { data } = await window.axios.get(api.value);
    flows.value = data.workflows || [];
    stats.value = data.stats || {};
    const t = await window.axios.get(`${api.value}/templates`);
    templates.value = t.data.templates || [];
  } finally {
    loading.value = false;
  }
}

function open(f, fresh = false) {
  draft.value = clone(f);
  normaliseBranches(draft.value.steps);
  draft.value.settings = draft.value.settings || {};
  isNew.value = fresh;
  selected.value = 'trigger';
  palette.value = null;
  errors.value = [];
  tab.value = 'flow';
  runs.value = [];
  test.value = { conversationId: '', replied: true, result: null, busy: false };
}
function createBlank() {
  open(
    {
      id: uid(),
      name: 'New workflow',
      status: 'draft',
      trigger: { type: 'guest_message' },
      steps: [],
      settings: {},
    },
    true
  );
}
function fromTemplate(t) {
  open({ ...clone(t), id: `${t.id}-${uid()}`, status: 'draft' }, true);
}
function back() {
  draft.value = null;
  load();
}

async function save() {
  saving.value = true;
  errors.value = [];
  try {
    const { data } = await window.axios.post(api.value, { workflow: draft.value });
    if (data.ok === false) errors.value = data.errors || [data.error || 'error'];
    else {
      draft.value = data.workflow;
      normaliseBranches(draft.value?.steps);
      isNew.value = false;
    }
  } catch (e) {
    errors.value = [String(e)];
  } finally {
    saving.value = false;
  }
}
async function remove() {
  // eslint-disable-next-line no-alert
  if (!window.confirm('Delete this workflow? Its runs stop.')) return;
  await window.axios.post(`${api.value}/delete`, { id: draft.value.id });
  back();
}
async function loadRuns() {
  tab.value = 'runs';
  const { data } = await window.axios.get(`${api.value}/runs`, {
    params: { workflow_id: draft.value.id, limit: 100 },
  });
  runs.value = data.runs || [];
}
async function runTest() {
  test.value.busy = true;
  try {
    const { data } = await window.axios.post(`${api.value}/test`, {
      workflow: draft.value,
      conversation_id: test.value.conversationId || null,
      replied: test.value.replied,
    });
    test.value.result = data;
  } finally {
    test.value.busy = false;
  }
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
const langs = computed(() => {
  const t = sel.value?.config?.text;
  return t && typeof t === 'object' ? Object.keys(t) : [];
});
function addLang() {
  // eslint-disable-next-line no-alert
  const code = (window.prompt('Language code (e.g. de, fr, ar)') || '').trim().slice(0, 5);
  if (code && sel.value) {
    sel.value.config.text[code] = '';
    lang.value = code;
  }
}
const waitValue = computed({
  get: () => {
    const m = sel.value?.config?.minutes || 0;
    if (m % 1440 === 0) return { n: m / 1440, unit: 1440 };
    if (m % 60 === 0) return { n: m / 60, unit: 60 };
    return { n: m, unit: 1 };
  },
  set: v => {
    sel.value.config.minutes = Math.max(1, Number(v.n || 0) * v.unit);
  },
});
const settingsRows = computed(() =>
  Object.entries(draft.value?.settings || {}).filter(([k]) => k !== 'by_team' && k !== 'by_place')
);
function addSetting() {
  // eslint-disable-next-line no-alert
  const key = (window.prompt('Setting name, used as {name} in messages') || '').trim();
  if (key) draft.value.settings[key] = '';
}
const runCounts = f => {
  const s = stats.value[f.id] || {};
  return {
    running: (s.waiting || 0) + (s.waiting_reply || 0) + (s.running || 0),
    done: s.done || 0,
  };
};

onMounted(load);
</script>

<template>
  <div class="overflow-auto flex-1 bg-n-background" data-tz-build="workflows-real-1">
    <!-- ===================== LIST ===================== -->
    <div v-if="!draft" class="mx-auto max-w-[1120px] px-5 pb-16 pt-7 md:px-6">
      <div class="flex flex-wrap gap-4 justify-between items-center">
        <div class="flex gap-3 items-center">
          <span class="tz-mark grid flex-shrink-0 place-content-center rounded-2xl size-11">
            <span class="i-lucide-workflow size-6 text-white" />
          </span>
          <div>
            <h1 class="m-0 text-[22px] font-extrabold tracking-tight text-n-slate-12">
              {{ $t('TOLZAR_WORKFLOWS.TITLE') }}
            </h1>
            <p class="m-0 text-sm text-n-slate-11">{{ $t('TOLZAR_WORKFLOWS.LEAD') }}</p>
          </div>
        </div>
        <div class="flex gap-2">
          <details class="relative">
            <summary class="tz-btn-ghost list-none">
              <span class="i-lucide-layout-template size-4" /> {{ $t('TOLZAR_WORKFLOWS.FROM_TEMPLATE') }}
            </summary>
            <div class="absolute right-0 z-20 p-1.5 mt-1 w-[320px] rounded-xl border shadow-lg bg-n-solid-1 border-n-weak">
              <button
                v-for="t in templates"
                :key="t.id"
                type="button"
                class="block px-3 py-2 w-full text-left rounded-lg text-[13px] text-n-slate-12 hover:bg-n-alpha-1"
                @click="fromTemplate(t)"
              >
                {{ t.name }}
              </button>
            </div>
          </details>
          <button type="button" class="tz-btn-primary" @click="createBlank">
            <span class="i-lucide-plus size-4" /> {{ $t('TOLZAR_WORKFLOWS.NEW') }}
          </button>
        </div>
      </div>

      <div class="overflow-hidden mt-5 rounded-2xl border shadow-sm bg-n-solid-1 border-n-weak">
        <div v-if="loading" class="p-6 text-center text-n-slate-10">…</div>
        <div
          v-for="f in flows"
          :key="f.id"
          class="flex flex-wrap gap-3 items-center px-[18px] py-3.5 border-b transition-colors cursor-pointer border-n-weak last:border-0 hover:bg-n-alpha-1"
          @click="open(f)"
        >
          <span
            class="inline-flex gap-1 items-center px-2.5 py-0.5 text-[11px] font-bold rounded-full"
            :class="f.status === 'shadow' ? 'text-n-brand bg-n-brand/10' : 'text-n-slate-11 bg-n-alpha-2'"
            >{{ $t(`TOLZAR_WORKFLOWS.STATUS.${f.status}`) }}</span
          >
          <span class="flex-1 font-semibold truncate text-n-slate-12">{{ f.name }}</span>
          <span class="text-[13px] text-n-slate-11">{{ $t(`TOLZAR_WORKFLOWS.TRIGGER.${f.trigger.type}`) }}</span>
          <span class="text-[13px] text-n-slate-10 w-[180px] text-right">{{
            $t('TOLZAR_WORKFLOWS.RUN_COUNTS', runCounts(f))
          }}</span>
        </div>
        <div v-if="!loading && !flows.length" class="p-6 text-center text-n-slate-10">
          {{ $t('TOLZAR_WORKFLOWS.EMPTY') }}
        </div>
      </div>
    </div>

    <!-- ===================== BUILDER ===================== -->
    <div v-else class="flex flex-col h-full">
      <div class="flex flex-wrap gap-3 items-center px-[18px] py-3 border-b bg-n-solid-1 border-n-weak">
        <button type="button" class="tz-btn-ghost" @click="back">‹ {{ $t('TOLZAR_WORKFLOWS.BACK') }}</button>
        <input
          v-model="draft.name"
          class="flex-1 px-2 py-1 min-w-[160px] text-base font-extrabold rounded-lg border border-transparent outline-none text-n-slate-12 bg-n-background focus:border-n-weak"
        />
        <select v-model="draft.status" class="tz-in !w-[170px]">
          <option value="draft">{{ $t('TOLZAR_WORKFLOWS.STATUS.draft') }}</option>
          <option value="shadow">{{ $t('TOLZAR_WORKFLOWS.STATUS.shadow') }}</option>
          <!-- Shadow only (owner rule): live is not offered; a workflow that is live already still shows it. -->
          <option v-if="draft.status === 'live'" value="live" disabled>{{ $t('TOLZAR_WORKFLOWS.STATUS.live') }}</option>
        </select>
        <button type="button" class="tz-btn-primary" :disabled="saving" @click="save">
          <span class="i-lucide-check size-4" /> {{ $t('TOLZAR_WORKFLOWS.SAVE') }}
        </button>
      </div>
      <div v-if="errors.length" class="px-[18px] py-2 text-sm text-rose-600 bg-rose-500/10">
        <div v-for="e in errors" :key="e">{{ e }}</div>
      </div>
      <div class="flex gap-1 px-[18px] border-b bg-n-solid-1 border-n-weak">
        <button
          v-for="t in ['flow', 'runs', 'test']"
          :key="t"
          type="button"
          class="px-3 py-2.5 text-sm border-b-2"
          :class="tab === t ? 'font-semibold border-n-brand text-n-slate-12' : 'border-transparent text-n-slate-10'"
          :disabled="t !== 'flow' && isNew"
          :title="t !== 'flow' && isNew ? $t('TOLZAR_WORKFLOWS.SAVE_FIRST') : ''"
          @click="t === 'runs' ? loadRuns() : (tab = t)"
        >
          {{ $t(`TOLZAR_WORKFLOWS.TAB.${t}`) }}
        </button>
      </div>

      <!-- flow -->
      <div v-if="tab === 'flow'" class="flex flex-1 min-h-0">
        <div class="tz-canvas overflow-auto flex-1 px-5 pt-8 pb-20">
          <div class="flex flex-col items-center">
            <div
              class="overflow-hidden w-[250px] rounded-xl border shadow-sm cursor-pointer bg-n-solid-1"
              :class="selected === 'trigger' ? 'border-n-brand ring-2 ring-n-brand/20' : 'border-n-weak'"
              style="border-top: 3px solid #e11d48"
              @click="selected = 'trigger'; palette = null"
            >
              <div class="flex gap-2 items-center px-3 py-2 font-bold border-b border-n-weak text-n-slate-12">
                <span class="i-lucide-zap size-4" style="color: #e11d48" /> {{ $t('TOLZAR_WORKFLOWS.TRIGGER_TITLE') }}
              </div>
              <div class="px-3 py-1.5 text-xs text-n-slate-11">
                {{ $t(`TOLZAR_WORKFLOWS.TRIGGER.${draft.trigger.type}`) }}
                <span v-if="draft.trigger.field"> · {{ draft.trigger.field }}{{ draft.trigger.value ? ` = ${draft.trigger.value}` : '' }}</span>
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

        <!-- side panel -->
        <div class="overflow-auto flex-shrink-0 p-[18px] w-[340px] border-l bg-n-solid-1 border-n-weak">
          <template v-if="palette">
            <h3 class="mt-0 mb-3 text-[15px] font-semibold text-n-slate-12">{{ $t('TOLZAR_WORKFLOWS.ADD_STEP') }}</h3>
            <button
              v-for="s in STEP_TYPES"
              :key="s.type"
              type="button"
              class="flex gap-2.5 items-center px-3 py-2 mb-1.5 w-full text-left rounded-xl border transition-colors border-n-weak hover:bg-n-alpha-1"
              @click="pick(s.type)"
            >
              <span :class="s.icon" class="size-4" :style="{ color: s.accent }" />
              <span class="text-[13px] font-semibold text-n-slate-12">{{ $t(stepMeta(s.type).label) }}</span>
            </button>
          </template>

          <template v-else-if="selected === 'trigger'">
            <h3 class="mt-0 mb-1 text-[15px] font-semibold text-n-slate-12">{{ $t('TOLZAR_WORKFLOWS.TRIGGER_TITLE') }}</h3>
            <p class="mt-0 text-xs text-n-slate-10">{{ $t('TOLZAR_WORKFLOWS.TRIGGER_HINT') }}</p>
            <label class="tz-lab">{{ $t('TOLZAR_WORKFLOWS.STARTS_WHEN') }}</label>
            <select v-model="draft.trigger.type" class="tz-in">
              <option v-for="t in TRIGGERS" :key="t" :value="t">{{ $t(`TOLZAR_WORKFLOWS.TRIGGER.${t}`) }}</option>
            </select>
            <template v-if="draft.trigger.type === 'field_equals' || draft.trigger.type === 'field_date'">
              <label class="tz-lab">{{ $t('TOLZAR_WORKFLOWS.FIELD') }}</label>
              <input v-model="draft.trigger.field" class="tz-in" placeholder="lifecycle_stage" />
            </template>
            <template v-if="draft.trigger.type === 'field_equals'">
              <label class="tz-lab">{{ $t('TOLZAR_WORKFLOWS.VALUE') }}</label>
              <input v-model="draft.trigger.value" class="tz-in" placeholder="Customer Won" />
              <label class="tz-lab">{{ $t('TOLZAR_WORKFLOWS.DELAY_MIN') }}</label>
              <input v-model.number="draft.trigger.delay_minutes" type="number" min="0" class="tz-in" />
            </template>
            <template v-if="draft.trigger.type === 'field_date'">
              <label class="tz-lab">{{ $t('TOLZAR_WORKFLOWS.OFFSET_MIN') }}</label>
              <input v-model.number="draft.trigger.offset_minutes" type="number" class="tz-in" />
            </template>
            <div class="flex justify-between items-center mt-5">
              <h4 class="m-0 text-[13px] font-semibold text-n-slate-12">{{ $t('TOLZAR_WORKFLOWS.SETTINGS') }}</h4>
              <button type="button" class="text-xs text-n-brand" @click="addSetting">+ {{ $t('TOLZAR_WORKFLOWS.ADD') }}</button>
            </div>
            <p class="mt-1 mb-2 text-xs text-n-slate-10">{{ $t('TOLZAR_WORKFLOWS.SETTINGS_HINT') }}</p>
            <div v-for="[k] in settingsRows" :key="k" class="mb-2">
              <label class="tz-lab !mt-0">{{ '{' + k + '}' }}</label>
              <input v-model="draft.settings[k]" class="tz-in" />
            </div>
          </template>

          <template v-else-if="sel">
            <h3 class="flex gap-2 items-center mt-0 mb-3 text-[15px] font-semibold text-n-slate-12">
              <span :class="stepMeta(sel.type).icon" class="size-4" :style="{ color: stepMeta(sel.type).accent }" />
              {{ $t(stepMeta(sel.type).label) }}
            </h3>

            <template v-if="sel.type === 'send_message'">
              <div class="flex flex-wrap gap-1 mb-2">
                <button
                  v-for="l in langs"
                  :key="l"
                  type="button"
                  class="px-2 py-0.5 text-xs rounded-md border"
                  :class="l === lang ? 'text-white bg-n-brand border-n-brand' : 'border-n-weak text-n-slate-11'"
                  @click="lang = l"
                >
                  {{ l.toUpperCase() }}
                </button>
                <button type="button" class="px-2 py-0.5 text-xs rounded-md border border-dashed border-n-strong text-n-brand" @click="addLang">+</button>
              </div>
              <textarea v-model="sel.config.text[lang in sel.config.text ? lang : langs[0] || 'en']" rows="6" class="resize-y tz-in" />
              <p class="text-xs text-n-slate-10">{{ $t('TOLZAR_WORKFLOWS.SEND_HINT') }}</p>
              <p class="p-2 text-xs rounded-lg text-amber-700 bg-amber-500/10 dark:text-amber-300">{{ $t('TOLZAR_WORKFLOWS.SHADOW_HINT') }}</p>
            </template>

            <template v-else-if="sel.type === 'comment'">
              <textarea v-model="sel.config.text" rows="5" class="resize-y tz-in" />
            </template>

            <template v-else-if="sel.type === 'wait'">
              <div class="flex gap-2">
                <input
                  type="number"
                  min="1"
                  class="tz-in"
                  :value="waitValue.n"
                  @input="waitValue = { n: $event.target.value, unit: waitValue.unit }"
                />
                <select
                  class="tz-in"
                  :value="waitValue.unit"
                  @change="waitValue = { n: waitValue.n, unit: Number($event.target.value) }"
                >
                  <option :value="1">min</option>
                  <option :value="60">h</option>
                  <option :value="1440">d</option>
                </select>
              </div>
              <label class="flex gap-2 items-center mt-3 text-[13px] text-n-slate-12">
                <input v-model="sel.config.until_reply" type="checkbox" /> {{ $t('TOLZAR_WORKFLOWS.UNTIL_REPLY') }}
              </label>
            </template>

            <template v-else-if="sel.type === 'branch'">
              <label class="tz-lab">{{ $t('TOLZAR_WORKFLOWS.MATCH') }}</label>
              <select v-model="sel.config.match" class="tz-in">
                <option value="all">{{ $t('TOLZAR_WORKFLOWS.MATCH_ALL') }}</option>
                <option value="any">{{ $t('TOLZAR_WORKFLOWS.MATCH_ANY') }}</option>
              </select>
              <div v-for="(c, ci) in sel.config.conditions" :key="ci" class="p-2 mt-2 rounded-lg border border-n-weak">
                <div class="flex gap-1">
                  <select v-model="c.kind" class="tz-in">
                    <option v-for="k in CONDITIONS" :key="k" :value="k">{{ $t(`TOLZAR_WORKFLOWS.COND.${k}`) }}</option>
                  </select>
                  <button type="button" class="px-2 text-n-slate-9 hover:text-rose-500" @click="sel.config.conditions.splice(ci, 1)">×</button>
                </div>
                <input v-if="['field_equals', 'field_empty'].includes(c.kind)" v-model="c.field" class="mt-1 tz-in" :placeholder="$t('TOLZAR_WORKFLOWS.FIELD')" />
                <input v-if="['field_equals', 'channel_is'].includes(c.kind)" v-model="c.value" class="mt-1 tz-in" :placeholder="$t('TOLZAR_WORKFLOWS.VALUE')" />
                <input v-if="c.kind === 'has_tag'" v-model="c.tag" class="mt-1 tz-in" placeholder="tag" />
                <input
                  v-if="c.kind === 'reply_matches'"
                  class="mt-1 tz-in"
                  :value="(c.words || []).join(', ')"
                  :placeholder="$t('TOLZAR_WORKFLOWS.WORDS')"
                  @change="c.words = $event.target.value.split(',').map(w => w.trim()).filter(Boolean)"
                />
                <div v-if="c.kind === 'reply_number'" class="flex gap-1 mt-1">
                  <input v-model.number="c.min" type="number" class="tz-in" placeholder="min" />
                  <input v-model.number="c.max" type="number" class="tz-in" placeholder="max" />
                </div>
              </div>
              <button type="button" class="mt-2 text-xs text-n-brand" @click="sel.config.conditions.push({ kind: 'replied' })">+ {{ $t('TOLZAR_WORKFLOWS.ADD') }}</button>
            </template>

            <template v-else-if="sel.type === 'add_tag'">
              <input v-model="sel.config.tag" class="tz-in" placeholder="tag" />
              <p class="text-xs text-n-slate-10">{{ $t('TOLZAR_WORKFLOWS.MIRROR_TAG_HINT') }}</p>
            </template>

            <template v-else-if="sel.type === 'ai_tag'">
              <p class="mt-0 text-xs text-n-slate-10">{{ $t('TOLZAR_WORKFLOWS.AI_TAG_HINT') }}</p>
              <div v-for="(t, ti) in sel.config.tags" :key="ti" class="flex gap-1 mb-1">
                <input v-model="t.tag" class="tz-in !w-[100px]" placeholder="tag" />
                <input v-model="t.when" class="tz-in" :placeholder="$t('TOLZAR_WORKFLOWS.WHEN')" />
                <button type="button" class="px-1 text-n-slate-9 hover:text-rose-500" @click="sel.config.tags.splice(ti, 1)">×</button>
              </div>
              <button type="button" class="text-xs text-n-brand" @click="sel.config.tags.push({ tag: '', when: '' })">+ {{ $t('TOLZAR_WORKFLOWS.ADD') }}</button>
            </template>

            <template v-else-if="sel.type === 'update_field'">
              <input v-model="sel.config.field" class="tz-in" :placeholder="$t('TOLZAR_WORKFLOWS.FIELD')" />
              <input v-model="sel.config.value" class="mt-2 tz-in" :placeholder="$t('TOLZAR_WORKFLOWS.VALUE')" />
            </template>
            <template v-else-if="sel.type === 'update_stage'">
              <input v-model="sel.config.stage" class="tz-in" placeholder="Customer Won" />
            </template>
            <template v-else-if="sel.type === 'assign_team'">
              <input v-model="sel.config.team_id" class="tz-in" placeholder="team id" />
            </template>
            <template v-else-if="sel.type === 'record_score'">
              <input v-model="sel.config.name" class="tz-in" placeholder="nps" />
              <p class="text-xs text-n-slate-10">{{ $t('TOLZAR_WORKFLOWS.SCORE_HINT') }}</p>
            </template>
          </template>

          <p v-else class="text-sm text-n-slate-10">{{ $t('TOLZAR_WORKFLOWS.PICK_HINT') }}</p>
        </div>
      </div>

      <!-- runs -->
      <div v-else-if="tab === 'runs'" class="overflow-auto flex-1 p-5">
        <table class="w-full text-sm">
          <thead>
            <tr class="text-xs text-left text-n-slate-10">
              <th class="py-2">{{ $t('TOLZAR_WORKFLOWS.RUN.CONTACT') }}</th>
              <th>{{ $t('TOLZAR_WORKFLOWS.RUN.STARTED') }}</th>
              <th>{{ $t('TOLZAR_WORKFLOWS.RUN.STATUS') }}</th>
              <th>{{ $t('TOLZAR_WORKFLOWS.RUN.LAST') }}</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="r in runs" :key="r.id" class="border-t border-n-weak">
              <td class="py-2">#{{ r.contact_id }}</td>
              <td>{{ (r.started_at || '').slice(0, 16).replace('T', ' ') }}</td>
              <td>{{ r.status }}</td>
              <td class="text-n-slate-11">{{ (r.log[r.log.length - 1] || {}).result }}</td>
            </tr>
          </tbody>
        </table>
        <p v-if="!runs.length" class="text-n-slate-10">{{ $t('TOLZAR_WORKFLOWS.NO_RUNS') }}</p>
      </div>

      <!-- test -->
      <div v-else class="overflow-auto flex-1 p-5 max-w-[720px]">
        <p class="mt-0 text-sm text-n-slate-11">{{ $t('TOLZAR_WORKFLOWS.TEST_HINT') }}</p>
        <div class="flex flex-wrap gap-2 items-center">
          <input v-model="test.conversationId" class="tz-in !w-[220px]" :placeholder="$t('TOLZAR_WORKFLOWS.CONVERSATION_ID')" />
          <label class="flex gap-1.5 items-center text-sm text-n-slate-12">
            <input v-model="test.replied" type="checkbox" /> {{ $t('TOLZAR_WORKFLOWS.PRETEND_REPLY') }}
          </label>
          <button type="button" class="tz-btn-primary" :disabled="test.busy" @click="runTest">{{ $t('TOLZAR_WORKFLOWS.RUN_TEST') }}</button>
        </div>
        <ol v-if="test.result && test.result.trace" class="mt-4 text-sm">
          <li v-for="(s, i) in test.result.trace" :key="i" class="mb-1.5">
            <b>{{ $t(stepMeta(s.type).label) }}</b>: <span class="text-n-slate-11">{{ s.result }}</span>
          </li>
        </ol>
        <div v-if="test.result && test.result.ok === false" class="mt-3 text-sm text-rose-600">
          {{ (test.result.errors || []).join(' · ') }}
        </div>
      </div>

      <div class="px-[18px] py-2.5 border-t bg-n-solid-1 border-n-weak">
        <button v-if="!isNew" type="button" class="inline-flex gap-1 items-center text-xs text-n-slate-10 hover:text-rose-500" @click="remove">
          <span class="i-lucide-trash-2 size-3.5" /> {{ $t('TOLZAR_WORKFLOWS.DELETE') }}
        </button>
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
.tz-lab {
  display: block;
  margin: 0.75rem 0 0.25rem;
  font-size: 0.75rem;
  color: rgb(var(--slate-11));
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
}
.tz-btn-primary:disabled {
  opacity: 0.6;
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
.tz-in:focus {
  border-color: #3e63dd;
}
</style>
