<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import {
  NONE_PACK,
  WEEKDAYS,
  emptyForm,
  bootstrapBody,
  bootstrapWorkspace,
  bootstrapOutcome,
  formProblems,
  getChecklist,
  checklistItems,
  checklistLink,
  checklistProgress,
} from 'dashboard/components-next/Tolzar/tolzarOnboarding';

// Tolzar onboarding: the brain's one-time workspace bootstrap (first settings, industry pack choice,
// an INACTIVE starter agent from a template; Owner-only, once), then the Getting started checklist.
// Nothing here turns anything live: the agent waits for the owner and then runs in Shadow.
const accountId = useMapGetter('getCurrentAccountId');
const getAccount = useMapGetter('accounts/getAccount');
const { t } = useI18n();
const base = computed(() => `/api/v1/accounts/${accountId.value}/tolzar`);

// Format examples (not translated: a time zone id, language codes, a URL).
const EXAMPLES = {
  timezone: 'Europe/Berlin',
  languages: 'en, ar, de',
  website: 'https://www.yourbusiness.com',
};
const step = ref(1); // 1 workspace, 2 agent, 3 checklist
const form = ref(emptyForm());
const busy = ref(false);
const outcome = ref(''); // '' | done | already | invalid | owner_only | error
const errors = ref([]);
const created = ref(null); // the starter agent (inactive) or null
const chunks = ref(null);
const templates = ref([]);
const packs = ref([NONE_PACK]);
const checklist = ref(null);
const checklistError = ref(false);

const problems = computed(() => formProblems(form.value));
const items = computed(() => checklistItems(checklist.value));
const progress = computed(() => checklistProgress(checklist.value));

async function loadChecklist() {
  checklistError.value = false;
  try {
    checklist.value = await getChecklist(accountId.value);
    if (!checklist.value || checklist.value.ok === false)
      checklistError.value = true;
  } catch (e) {
    checklistError.value = true;
  }
}

// Steps 1-2 only before the bootstrap ran; the checklist is always open.
const canGo = n =>
  n === 3 || (n <= step.value && !['done', 'already'].includes(outcome.value));
function goStep(n) {
  if (!canGo(n)) return;
  step.value = n;
  if (n === 3) loadChecklist();
}

onMounted(async () => {
  form.value.workspaceName = getAccount.value(accountId.value)?.name || '';
  const [tpl, pack] = await Promise.all([
    window.axios
      .get(`${base.value}/brain/agent_templates`)
      .then(r => r.data)
      .catch(() => ({})),
    window.axios
      .get(`${base.value}/pack`)
      .then(r => r.data)
      .catch(() => ({})),
  ]);
  templates.value = tpl.templates || [];
  if (typeof pack.pack === 'string' && pack.pack && pack.pack !== NONE_PACK)
    packs.value = [NONE_PACK, pack.pack];
  await loadChecklist();
  // Already set up: straight to the checklist.
  if (checklist.value && checklist.value.bootstrapped) {
    outcome.value = 'already';
    step.value = 3;
  }
});

function toggleDay(d) {
  const days = form.value.closedDays;
  form.value.closedDays = days.includes(d)
    ? days.filter(x => x !== d)
    : [...days, d];
}

async function addWebsite(agent) {
  const url = form.value.website.trim();
  if (!agent || !url) return;
  // The agent stays as the brain made it (inactive); only its knowledge source is added.
  const withSite = {
    ...agent,
    knowledge: [
      {
        type: /sitemap/i.test(url) ? 'sitemap' : 'url',
        label: 'Website',
        value: url,
      },
    ],
  };
  try {
    await window.axios.post(`${base.value}/agents`, { agent: withSite });
    const r = await window.axios.post(`${base.value}/brain/knowledge_refresh`, {
      id: agent.id,
    });
    chunks.value = r.data.total ?? null;
  } catch (e) {
    chunks.value = null;
  }
}

async function runBootstrap() {
  if (problems.value.length || busy.value) return;
  busy.value = true;
  errors.value = [];
  try {
    const data = await bootstrapWorkspace(
      accountId.value,
      bootstrapBody(form.value)
    );
    outcome.value = bootstrapOutcome(data);
    if (outcome.value === 'done') {
      created.value = data.agent || null;
      await addWebsite(created.value);
      if (data.checklist) checklist.value = data.checklist;
      else await loadChecklist();
      step.value = 3;
    } else if (outcome.value === 'already') {
      await loadChecklist();
      step.value = 3;
    } else if (outcome.value === 'invalid') {
      errors.value = data.errors || [];
    }
  } catch (e) {
    outcome.value = 'error';
  } finally {
    busy.value = false;
  }
}

const linkFor = hint => checklistLink(hint, accountId.value);
</script>

<template>
  <div
    class="overflow-auto flex-1 bg-n-background"
    data-tz-build="onboarding-2-bootstrap"
  >
    <div class="mx-auto max-w-[860px] px-5 pb-16 pt-7">
      <div class="flex flex-wrap gap-2 mb-4">
        <button
          v-for="n in 3"
          :key="n"
          type="button"
          class="px-2.5 py-1 text-xs rounded-full border-0"
          :class="
            n === step
              ? 'font-semibold text-n-brand bg-n-brand/10'
              : n < step
                ? 'text-emerald-600 bg-emerald-500/10'
                : 'text-n-slate-10 bg-n-alpha-1'
          "
          :disabled="!canGo(n)"
          @click="goStep(n)"
        >
          {{ n }} {{ t(`TOLZAR_ONBOARDING.STEP2.${n}`) }}
        </button>
      </div>

      <div
        v-if="outcome === 'already'"
        class="flex flex-wrap gap-2 justify-between items-center px-4 py-3 mb-4 text-[13px] rounded-xl border border-n-weak bg-n-alpha-1 text-n-slate-12"
        role="status"
        data-tz-already
      >
        <span>{{ t('TOLZAR_ONBOARDING.ALREADY') }}</span>
        <router-link
          :to="{
            name: 'tolzar_settings',
            query: { section: 'workspace_settings' },
          }"
          class="font-semibold text-n-brand"
        >
          {{ t('TOLZAR_ONBOARDING.OPEN_SETTINGS') }}
        </router-link>
      </div>

      <div class="p-5 rounded-xl border bg-n-solid-1 border-n-weak">
        <template v-if="step === 1">
          <h2 class="mt-0 text-[17px] font-bold">
            {{ t('TOLZAR_ONBOARDING.WORKSPACE.TITLE') }}
          </h2>
          <label class="tz-lab">{{
            t('TOLZAR_ONBOARDING.WORKSPACE.NAME')
          }}</label>
          <input v-model="form.workspaceName" class="tz-in" maxlength="80" />
          <label class="tz-lab">{{
            t('TOLZAR_ONBOARDING.WORKSPACE.TIMEZONE')
          }}</label>
          <input
            v-model="form.timezone"
            class="tz-in"
            :placeholder="EXAMPLES.timezone"
          />
          <label class="tz-lab">{{
            t('TOLZAR_ONBOARDING.WORKSPACE.HOURS')
          }}</label>
          <div class="flex gap-2 items-center">
            <input v-model="form.start" type="time" class="tz-in !w-auto" />
            <span class="text-n-slate-10">–</span>
            <input v-model="form.end" type="time" class="tz-in !w-auto" />
          </div>
          <label class="tz-lab">{{
            t('TOLZAR_ONBOARDING.WORKSPACE.CLOSED')
          }}</label>
          <div class="flex flex-wrap gap-1.5">
            <button
              v-for="d in WEEKDAYS"
              :key="d"
              type="button"
              class="px-2 py-0.5 text-xs rounded-full border"
              :class="
                form.closedDays.includes(d)
                  ? 'text-white border-transparent bg-n-brand'
                  : 'border-n-weak text-n-slate-11'
              "
              :aria-pressed="form.closedDays.includes(d)"
              @click="toggleDay(d)"
            >
              {{ t(`TOLZAR_ONBOARDING.DAY.${d}`) }}
            </button>
          </div>
          <label class="tz-lab">{{
            t('TOLZAR_ONBOARDING.WORKSPACE.LANGUAGES')
          }}</label>
          <input
            v-model="form.languages"
            class="tz-in"
            :placeholder="EXAMPLES.languages"
          />
          <button
            type="button"
            class="tz-btn"
            :disabled="problems.length > 0"
            @click="step = 2"
          >
            {{ t('TOLZAR_ONBOARDING.NEXT') }}
          </button>
        </template>

        <template v-else-if="step === 2">
          <h2 class="mt-0 text-[17px] font-bold">
            {{ t('TOLZAR_ONBOARDING.AGENT.TITLE') }}
          </h2>
          <p class="text-[13px] text-n-slate-10">
            {{ t('TOLZAR_ONBOARDING.AGENT.HINT_INACTIVE') }}
          </p>
          <label class="tz-lab">{{ t('TOLZAR_ONBOARDING.AGENT.PACK') }}</label>
          <div class="grid gap-2 md:grid-cols-3">
            <button
              type="button"
              class="p-3 text-left rounded-lg border"
              :class="
                !form.template
                  ? 'border-n-brand ring-2 ring-n-brand/20'
                  : 'border-n-weak'
              "
              @click="form.template = ''"
            >
              <b class="text-[13px]">{{
                t('TOLZAR_ONBOARDING.AGENT.NO_TEMPLATE')
              }}</b>
              <div class="text-xs text-n-slate-10">
                {{ t('TOLZAR_ONBOARDING.AGENT.NO_TEMPLATE_HINT') }}
              </div>
            </button>
            <button
              v-for="tp in templates"
              :key="tp.id"
              type="button"
              class="p-3 text-left rounded-lg border"
              :class="
                form.template === tp.id
                  ? 'border-n-brand ring-2 ring-n-brand/20'
                  : 'border-n-weak'
              "
              @click="form.template = tp.id"
            >
              <b class="text-[13px]">{{ tp.name }}</b>
              <div class="text-xs text-n-slate-10">{{ tp.description }}</div>
            </button>
          </div>
          <template v-if="form.template">
            <label class="tz-lab">{{
              t('TOLZAR_ONBOARDING.AGENT.NAME')
            }}</label>
            <input v-model="form.agentName" class="tz-in" maxlength="80" />
            <label class="tz-lab">{{
              t('TOLZAR_ONBOARDING.AGENT.WEBSITE')
            }}</label>
            <input
              v-model="form.website"
              class="tz-in"
              :placeholder="EXAMPLES.website"
            />
          </template>
          <label class="tz-lab">{{
            t('TOLZAR_ONBOARDING.AGENT.INDUSTRY_PACK')
          }}</label>
          <select v-model="form.pack" class="tz-in !w-auto">
            <option v-for="p in packs" :key="p" :value="p">
              {{ p === 'none' ? t('TOLZAR_ONBOARDING.AGENT.NO_PACK') : p }}
            </option>
          </select>
          <p v-if="outcome === 'owner_only'" class="text-sm text-rose-600">
            {{ t('TOLZAR_ONBOARDING.OWNER_ONLY') }}
          </p>
          <p v-if="outcome === 'error'" class="text-sm text-rose-600">
            {{ t('TOLZAR_ONBOARDING.FAILED') }}
          </p>
          <ul v-if="errors.length" class="pl-4 text-sm text-rose-600">
            <li v-for="e in errors" :key="e.path + e.error">
              {{ e.path }}: {{ e.error }}
            </li>
          </ul>
          <div class="flex gap-2">
            <button type="button" class="tz-btn-ghost" @click="step = 1">
              {{ t('TOLZAR_ONBOARDING.BACK') }}
            </button>
            <button
              type="button"
              class="tz-btn"
              :disabled="busy || problems.length > 0"
              @click="runBootstrap"
            >
              {{ busy ? '…' : t('TOLZAR_ONBOARDING.SET_UP') }}
            </button>
          </div>
        </template>

        <template v-else>
          <div class="flex flex-wrap gap-2 justify-between items-center">
            <h2 class="m-0 text-[17px] font-bold">
              {{ t('TOLZAR_ONBOARDING.CHECKLIST.TITLE') }}
            </h2>
            <span class="text-xs text-n-slate-11" data-tz-progress>
              {{ t('TOLZAR_ONBOARDING.CHECKLIST.PROGRESS', progress) }}
            </span>
          </div>
          <p v-if="outcome === 'done'" class="text-[13px] text-n-slate-11">
            {{
              created
                ? t('TOLZAR_ONBOARDING.CHECKLIST.CREATED', {
                    name: created.name,
                    chunks: chunks ?? 0,
                  })
                : t('TOLZAR_ONBOARDING.CHECKLIST.CREATED_NO_AGENT')
            }}
          </p>
          <p class="text-[13px] text-n-slate-10">
            {{ t('TOLZAR_ONBOARDING.CHECKLIST.HINT') }}
          </p>
          <p v-if="checklistError" class="text-sm text-rose-600">
            {{ t('TOLZAR_ONBOARDING.CHECKLIST.FAILED') }}
          </p>
          <ul class="p-0 m-0 list-none">
            <li
              v-for="item in items"
              :key="item.key"
              class="flex gap-3 items-start py-2.5 border-b border-n-weak last:border-0"
              :data-tz-check="item.key"
            >
              <span
                class="flex-shrink-0 mt-0.5 size-4"
                :class="
                  item.done
                    ? 'i-lucide-circle-check text-emerald-600'
                    : 'i-lucide-circle text-n-slate-9'
                "
              />
              <div class="flex-1 min-w-0">
                <div class="text-[13px] font-semibold text-n-slate-12">
                  {{ t(`TOLZAR_ONBOARDING.CHECK.${item.key}`, item.key) }}
                  <span
                    v-if="item.required === false"
                    class="ml-1 text-[11px] font-normal text-n-slate-10"
                  >
                    {{ t('TOLZAR_ONBOARDING.CHECKLIST.OPTIONAL') }}
                  </span>
                </div>
                <div class="text-xs text-n-slate-10 break-words">
                  {{ item.detail }}
                </div>
              </div>
              <router-link
                v-if="linkFor(item.action_hint) && !item.done"
                :to="linkFor(item.action_hint)"
                class="flex-shrink-0 text-xs font-semibold text-n-brand"
              >
                {{ t('TOLZAR_ONBOARDING.CHECKLIST.FIX') }}
              </router-link>
            </li>
          </ul>
          <button type="button" class="tz-btn-ghost" @click="loadChecklist">
            {{ t('TOLZAR_ONBOARDING.CHECKLIST.REFRESH') }}
          </button>
        </template>
      </div>
    </div>
  </div>
</template>

<style scoped>
.tz-lab {
  display: block;
  margin: 0.75rem 0 0.25rem;
  font-size: 0.75rem;
  color: rgb(var(--slate-11));
}
.tz-btn,
.tz-btn-ghost {
  display: inline-flex;
  align-items: center;
  height: 2.25rem;
  margin-top: 1rem;
  padding: 0 1rem;
  font-size: 0.875rem;
  font-weight: 600;
  border-radius: 0.75rem;
  cursor: pointer;
}
.tz-btn {
  color: #fff;
  background: #3e63dd;
  border: 0;
}
.tz-btn:disabled {
  opacity: 0.5;
  cursor: not-allowed;
}
.tz-btn-ghost {
  color: rgb(var(--slate-11));
  background: rgb(var(--solid-1));
  border: 1px solid rgb(var(--border-weak));
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
</style>
