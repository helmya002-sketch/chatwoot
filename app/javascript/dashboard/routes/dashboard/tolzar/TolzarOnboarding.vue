<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import {
  BTN,
  BTN_GHOST,
  INPUT,
  LABEL,
} from 'dashboard/components-next/Tolzar/settings/tzClasses';
import {
  NONE_PACK,
  WEEKDAYS,
  LANGUAGES,
  emptyForm,
  bootstrapBody,
  bootstrapWorkspace,
  bootstrapOutcome,
  formProblems,
  getChecklist,
  checklistLink,
  checklistProgress,
  parseLanguages,
  problemFor,
  timezoneOptions,
  toggleLanguage,
  visibleChecklistItems,
} from 'dashboard/components-next/Tolzar/tolzarOnboarding';

// Tolzar onboarding: the brain's one-time workspace bootstrap (first settings, industry pack choice,
// an INACTIVE starter agent from a template; Owner-only, once), then the Getting started checklist.
// Nothing here turns anything live: the agent waits for the owner and then runs in Shadow.
const accountId = useMapGetter('getCurrentAccountId');
const getAccount = useMapGetter('accounts/getAccount');
const { t, te } = useI18n();
const base = computed(() => `/api/v1/accounts/${accountId.value}/tolzar`);

// A format example (not translated: a URL).
const WEBSITE_EXAMPLE = 'https://www.yourbusiness.com';
const step = ref(1); // 1 workspace, 2 agent, 3 checklist
const form = ref(emptyForm());
const busy = ref(false);
const outcome = ref(''); // '' | done | already | invalid | owner_only | error
const errors = ref([]);
const created = ref(null); // the starter agent (inactive) or null
const chunks = ref(null);
const templates = ref([]);
const packs = ref([NONE_PACK]);
const packLabels = ref({});
const packDescriptions = ref({});
const checklist = ref(null);
const checklistError = ref(false);

const problems = computed(() => formProblems(form.value));
const problem = path => problemFor(problems.value, path);
// Going live is locked unless the install turned it on for this workspace (tolzar_live_allowed).
const liveAllowed = computed(
  () =>
    getAccount.value(accountId.value)?.settings?.tolzar_live_allowed === true
);
const items = computed(() =>
  visibleChecklistItems(checklist.value, liveAllowed.value)
);
const progress = computed(() => checklistProgress(checklist.value));
const hintFor = key =>
  te(`TOLZAR_ONBOARDING_UI.CHECK_HINT.${key}`)
    ? t(`TOLZAR_ONBOARDING_UI.CHECK_HINT.${key}`)
    : '';

// Time zone picker (the same list as Settings → Workspace) with a text filter above it.
const tzFilter = ref('');
const timezones = computed(() =>
  timezoneOptions(form.value.timezone, tzFilter.value)
);
// Language chips: the short ISO 639-1 list plus any code the form already holds.
const chosenLanguages = computed(() => parseLanguages(form.value.languages));
const languageChips = computed(() => [
  ...LANGUAGES,
  ...chosenLanguages.value.filter(c => !LANGUAGES.includes(c)),
]);
const languageName = code => {
  try {
    return new Intl.DisplayNames([code], { type: 'language' }).of(code) || code;
  } catch (e) {
    return code;
  }
};
const toggleLang = code => {
  form.value.languages = toggleLanguage(form.value.languages, code);
};

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
  // The built-in packs (brain GET /workspace/pack `choices`), and the current one if it is not built in.
  const choices = Array.isArray(pack.choices) ? pack.choices : [];
  packLabels.value = Object.fromEntries(
    choices.map(c => [c.name, (c.label && c.label.en) || c.name])
  );
  // A one-line description per pack when the brain's list carries one ({en} or a string).
  packDescriptions.value = Object.fromEntries(
    choices
      .map(c => [
        c.name,
        typeof c.description === 'string'
          ? c.description
          : (c.description && c.description.en) || '',
      ])
      .filter(([, d]) => d)
  );
  const names = choices.map(c => c.name);
  if (typeof pack.pack === 'string' && pack.pack && !names.includes(pack.pack))
    names.push(pack.pack);
  packs.value = [NONE_PACK, ...names.filter(n => n !== NONE_PACK)];
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
    // Unknown: the save or the indexing failed (a saved site is indexed by the daily job).
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
const PROBLEM = 'mt-1 text-xs text-n-ruby-11';
</script>

<template>
  <div
    class="overflow-auto flex-1 bg-n-background"
    data-tz-build="onboarding-3-ux"
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
                ? 'text-n-teal-11 bg-n-teal-3'
                : 'text-n-slate-10 bg-n-alpha-1'
          "
          :disabled="!canGo(n)"
          :aria-current="n === step ? 'step' : undefined"
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
          <label :class="LABEL" for="tz-onb-name">{{
            t('TOLZAR_ONBOARDING.WORKSPACE.NAME')
          }}</label>
          <input
            id="tz-onb-name"
            v-model="form.workspaceName"
            :class="INPUT"
            maxlength="80"
            :aria-invalid="!!problem('workspace_name')"
          />
          <p v-if="problem('workspace_name')" :class="PROBLEM">
            {{ t(`TOLZAR_ONBOARDING_UI.PROBLEM.${problem('workspace_name')}`) }}
          </p>

          <label :class="LABEL" for="tz-onb-tz">{{
            t('TOLZAR_ONBOARDING.WORKSPACE.TIMEZONE')
          }}</label>
          <input
            v-model="tzFilter"
            type="search"
            :class="INPUT"
            class="mb-1.5"
            :placeholder="t('TOLZAR_ONBOARDING_UI.TIMEZONE_FILTER')"
            aria-controls="tz-onb-tz"
          />
          <select
            id="tz-onb-tz"
            v-model="form.timezone"
            :class="INPUT"
            :aria-invalid="!!problem('timezone')"
          >
            <option v-for="z in timezones" :key="z" :value="z">{{ z }}</option>
          </select>
          <p v-if="!timezones.length" class="mt-1 text-xs text-n-slate-10">
            {{ t('TOLZAR_ONBOARDING_UI.TIMEZONE_NONE') }}
          </p>
          <p v-if="problem('timezone')" :class="PROBLEM">
            {{ t(`TOLZAR_ONBOARDING_UI.PROBLEM.${problem('timezone')}`) }}
          </p>

          <label :class="LABEL">{{
            t('TOLZAR_ONBOARDING.WORKSPACE.HOURS')
          }}</label>
          <div class="flex gap-2 items-center">
            <input
              v-model="form.start"
              type="time"
              :class="INPUT"
              class="!w-auto"
              :aria-invalid="!!problem('working_hours')"
            />
            <span class="text-n-slate-10">–</span>
            <input
              v-model="form.end"
              type="time"
              :class="INPUT"
              class="!w-auto"
              :aria-invalid="!!problem('working_hours')"
            />
          </div>
          <p v-if="problem('working_hours')" :class="PROBLEM">
            {{ t(`TOLZAR_ONBOARDING_UI.PROBLEM.${problem('working_hours')}`) }}
          </p>

          <label :class="LABEL">{{
            t('TOLZAR_ONBOARDING.WORKSPACE.CLOSED')
          }}</label>
          <div class="flex flex-wrap gap-1.5">
            <button
              v-for="d in WEEKDAYS"
              :key="d"
              type="button"
              class="px-2 py-0.5 text-xs rounded-full border border-solid"
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

          <label :class="LABEL">{{
            t('TOLZAR_ONBOARDING.AGENT.LANGUAGES')
          }}</label>
          <div class="flex flex-wrap gap-1.5">
            <button
              v-for="code in languageChips"
              :key="code"
              type="button"
              class="px-2 py-0.5 text-xs rounded-full border border-solid"
              :class="
                chosenLanguages.includes(code)
                  ? 'text-white border-transparent bg-n-brand'
                  : 'border-n-weak text-n-slate-11'
              "
              :aria-pressed="chosenLanguages.includes(code)"
              :title="code"
              @click="toggleLang(code)"
            >
              {{ languageName(code) }}
            </button>
          </div>
          <p class="mt-1 text-xs text-n-slate-10">
            {{ t('TOLZAR_ONBOARDING_UI.LANGUAGES_HINT') }}
          </p>

          <button
            type="button"
            :class="BTN"
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

          <!-- the pack first: it decides which templates make sense -->
          <label :class="LABEL" for="tz-onb-pack">{{
            t('TOLZAR_ONBOARDING.AGENT.INDUSTRY_PACK')
          }}</label>
          <select
            id="tz-onb-pack"
            v-model="form.pack"
            :class="INPUT"
            class="!w-auto"
          >
            <option v-for="p in packs" :key="p" :value="p">
              {{
                p === NONE_PACK
                  ? t('TOLZAR_ONBOARDING.AGENT.NO_PACK')
                  : packLabels[p] || p
              }}
            </option>
          </select>
          <p class="mt-1 text-xs text-n-slate-10">
            {{
              form.pack === NONE_PACK
                ? t('TOLZAR_ONBOARDING_UI.PACK_NONE_HINT')
                : packDescriptions[form.pack] ||
                  t('TOLZAR_ONBOARDING_UI.PACK_FIRST_HINT')
            }}
          </p>

          <p class="mt-4 text-[13px] text-n-slate-10">
            {{ t('TOLZAR_ONBOARDING.AGENT.HINT_INACTIVE') }}
          </p>
          <label :class="LABEL">{{ t('TOLZAR_ONBOARDING.AGENT.PACK') }}</label>
          <div class="grid gap-2 md:grid-cols-3">
            <button
              type="button"
              class="p-3 text-start rounded-lg border border-solid"
              :class="
                !form.template
                  ? 'border-n-brand ring-2 ring-n-brand/20'
                  : 'border-n-weak'
              "
              :aria-pressed="!form.template"
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
              class="p-3 text-start rounded-lg border border-solid"
              :class="
                form.template === tp.id
                  ? 'border-n-brand ring-2 ring-n-brand/20'
                  : 'border-n-weak'
              "
              :aria-pressed="form.template === tp.id"
              @click="form.template = tp.id"
            >
              <b class="text-[13px]">{{ tp.name }}</b>
              <div class="text-xs text-n-slate-10">{{ tp.description }}</div>
            </button>
          </div>
          <template v-if="form.template">
            <label :class="LABEL" for="tz-onb-agent">{{
              t('TOLZAR_ONBOARDING.AGENT.NAME')
            }}</label>
            <input
              id="tz-onb-agent"
              v-model="form.agentName"
              :class="INPUT"
              maxlength="80"
            />
            <label :class="LABEL" for="tz-onb-site">{{
              t('TOLZAR_ONBOARDING.AGENT.WEBSITE')
            }}</label>
            <input
              id="tz-onb-site"
              v-model="form.website"
              :class="INPUT"
              :placeholder="WEBSITE_EXAMPLE"
            />
          </template>

          <p
            v-if="outcome === 'owner_only'"
            class="text-sm text-n-ruby-11"
            role="alert"
          >
            {{ t('TOLZAR_ONBOARDING.OWNER_ONLY') }}
          </p>
          <p
            v-if="outcome === 'error'"
            class="text-sm text-n-ruby-11"
            role="alert"
          >
            {{ t('TOLZAR_ONBOARDING.FAILED') }}
          </p>
          <ul
            v-if="errors.length"
            class="ps-4 text-sm text-n-ruby-11"
            role="alert"
          >
            <li v-for="e in errors" :key="e.path + e.error">
              {{ e.path }}: {{ e.error }}
            </li>
          </ul>
          <div class="flex gap-2">
            <button type="button" :class="BTN_GHOST" @click="step = 1">
              {{ t('TOLZAR_ONBOARDING.BACK') }}
            </button>
            <button
              type="button"
              :class="BTN"
              class="gap-2"
              :disabled="busy || problems.length > 0"
              :aria-busy="busy"
              @click="runBootstrap"
            >
              <Spinner v-if="busy" :size="16" />
              {{
                busy
                  ? t('TOLZAR_ONBOARDING_UI.SETTING_UP')
                  : t('TOLZAR_ONBOARDING.SET_UP')
              }}
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
          <p v-if="checklistError" class="text-sm text-n-ruby-11" role="alert">
            {{ t('TOLZAR_ONBOARDING.CHECKLIST.FAILED') }}
            <button
              type="button"
              class="ms-2 font-semibold underline"
              @click="loadChecklist"
            >
              {{ t('TOLZAR_UI.RETRY') }}
            </button>
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
                    ? 'i-lucide-circle-check text-n-teal-11'
                    : 'i-lucide-circle text-n-slate-9'
                "
              />
              <div class="flex-1 min-w-0">
                <div class="text-[13px] font-semibold text-n-slate-12">
                  {{ t(`TOLZAR_ONBOARDING.CHECK.${item.key}`, item.key) }}
                  <span
                    v-if="item.required === false"
                    class="ms-1 text-[11px] font-normal text-n-slate-10"
                  >
                    {{ t('TOLZAR_ONBOARDING.CHECKLIST.OPTIONAL') }}
                  </span>
                </div>
                <div v-if="hintFor(item.key)" class="text-xs text-n-slate-11">
                  {{ hintFor(item.key) }}
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
          <button type="button" :class="BTN_GHOST" @click="loadChecklist">
            {{ t('TOLZAR_ONBOARDING.CHECKLIST.REFRESH') }}
          </button>
        </template>
      </div>
    </div>
  </div>
</template>
