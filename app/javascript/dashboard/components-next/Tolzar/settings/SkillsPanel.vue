<script setup>
// AI-agent Skills editor (brain agent_skills.py). Skills are proposals only: the brain writes a
// "would do" private note and executes nothing, in every inbox mode. The pickers offer this
// workspace's own teams, team members, pipeline stages, custom attributes and workflows; a saved
// value that is no longer there stays listed (struck through) until it is unticked.
import { ref, computed, onMounted, watchEffect } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import {
  STAGES,
  applyPipelineStages,
} from 'dashboard/components-next/Tolzar/tolzarStages';
import {
  SKILL_TYPES,
  MAX_SKILLS,
  MAX_WHEN,
  MAX_LIST,
  newSkill,
  parseTags,
  skillProblems,
  toggleValue,
} from 'dashboard/components-next/Tolzar/tolzarSkills';
import { INPUT } from './tzClasses';

const props = defineProps({
  live: { type: Boolean, default: true },
});
// { skills_enabled, skills_dry_run_workflows, skills: [...] } (tolzarSkills form)
const form = defineModel({ type: Object, required: true });

const { t } = useI18n();
const accountId = useMapGetter('getCurrentAccountId');
const getAccount = useMapGetter('accounts/getAccount');
const api = computed(() => `/api/v1/accounts/${accountId.value}`);

// One dot per skill type, in theme tokens (static strings so Tailwind keeps them; follows the
// app theme and a white-label brand, unlike a hex).
const ACCENT = {
  assign: 'bg-n-blue-9',
  update_fields: 'bg-n-iris-9',
  change_stage: 'bg-n-ruby-9',
  close: 'bg-n-teal-9',
  add_tag: 'bg-n-amber-9',
  trigger_workflow: 'bg-n-brand',
};

const teams = ref([]);
const people = ref([]);
const attributes = ref([]);
const workflows = ref([]);
const addOpen = ref(false);
const tagText = ref({});

watchEffect(() =>
  applyPipelineStages(getAccount.value(accountId.value)?.settings)
);

const list = (p, pick) =>
  window.axios
    .get(p)
    .then(r => pick(r.data) || [])
    .catch(() => []);

onMounted(async () => {
  const [tm, attrs, wf] = await Promise.all([
    list(`${api.value}/teams`, d => (Array.isArray(d) ? d : d.payload)),
    list(`${api.value}/custom_attribute_definitions`, d =>
      Array.isArray(d) ? d : d.payload
    ),
    list(`${api.value}/tolzar/workflows`, d => d.workflows),
  ]);
  teams.value = tm.map(x => ({ value: x.id, label: x.name }));
  attributes.value = attrs;
  workflows.value = wf
    .filter(w => w && w.id)
    .map(w => ({ value: w.id, label: w.name || w.id }));
  const members = await Promise.all(
    tm.map(x =>
      list(`${api.value}/teams/${x.id}/team_members`, d =>
        Array.isArray(d) ? d : d.payload
      )
    )
  );
  const names = new Set();
  members.flat().forEach(m => {
    const n = (m && (m.name || m.available_name)) || '';
    if (n) names.add(n);
  });
  people.value = [...names].sort().map(n => ({ value: n, label: n }));
});

const attrOptions = model =>
  attributes.value
    .filter(a => a.attribute_model === model)
    .map(a => ({
      value: a.attribute_key,
      label: a.attribute_display_name || a.attribute_key,
    }));

// The pickers of each type: [config key, i18n label key, options].
const pickers = type => {
  if (type === 'assign')
    return [
      ['team_ids', 'TEAMS', teams.value],
      ['agent_names', 'AGENTS', people.value],
    ];
  if (type === 'update_fields')
    return [
      ['contact_fields', 'CONTACT_FIELDS', attrOptions('contact_attribute')],
      [
        'conversation_fields',
        'CONVERSATION_FIELDS',
        attrOptions('conversation_attribute'),
      ],
    ];
  if (type === 'change_stage')
    return [
      ['stages', 'STAGES', STAGES.map(s => ({ value: s.key, label: s.label }))],
    ];
  if (type === 'trigger_workflow')
    return [['workflow_ids', 'WORKFLOWS', workflows.value]];
  return [];
};

// Options plus any saved value the workspace no longer has (shown struck through).
const withSaved = (options, saved) => {
  const missing = (saved || [])
    .filter(v => !options.some(o => String(o.value) === String(v)))
    .map(v => ({ value: v, label: String(v), missing: true }));
  return [...options, ...missing];
};

const isOn = (sk, key, value) =>
  (sk.config[key] || []).some(x => String(x) === String(value));
const toggle = (sk, key, value) => {
  sk.config[key] = toggleValue(sk.config[key], value);
};

const tagsOf = sk =>
  tagText.value[sk.type] ?? (sk.config.tags || []).join(', ');
const setTags = (sk, text) => {
  tagText.value[sk.type] = text;
  sk.config.tags = parseTags(text);
};

const available = computed(() =>
  SKILL_TYPES.filter(type => !form.value.skills.some(s => s.type === type))
);
function add(type) {
  if (form.value.skills.length >= MAX_SKILLS) return;
  form.value.skills.push(newSkill(type));
  addOpen.value = false;
}
function remove(i) {
  form.value.skills.splice(i, 1);
}

const problems = computed(() => skillProblems(form.value));
const badge = computed(() =>
  props.live ? t('TOLZAR_SKILLS.BADGE') : t('TOLZAR_HONEST.COMING_SOON')
);
const problemsAt = i => problems.value.filter(p => p.index === i);
const listProblems = computed(() => problems.value.filter(p => p.index < 0));
</script>

<template>
  <section
    class="p-[18px] rounded-2xl border shadow-sm bg-n-solid-1 border-n-weak"
    :aria-disabled="!props.live"
    data-tz-skills
  >
    <div class="flex relative justify-between items-center">
      <h3
        class="inline-flex gap-2 items-center m-0 text-[15px] font-semibold text-n-slate-12"
      >
        {{ t('TOLZAR_SKILLS.TITLE') }}
        <span
          class="inline-flex items-center px-2 py-0.5 text-[11px] font-semibold rounded-full text-n-slate-11 bg-n-alpha-2"
        >
          {{ badge }}
        </span>
      </h3>
      <button
        type="button"
        class="tz-btn-soft disabled:opacity-50 disabled:cursor-not-allowed"
        :disabled="
          !props.live || !available.length || form.skills.length >= MAX_SKILLS
        "
        @click="addOpen = !addOpen"
      >
        <span class="i-lucide-plus size-3.5" /> {{ t('TOLZAR_SKILLS.ADD') }}
      </button>
      <div
        v-if="props.live && addOpen"
        class="overflow-hidden absolute top-9 z-10 w-[300px] rounded-xl border shadow-lg end-0 bg-n-solid-1 border-n-weak"
      >
        <button
          v-for="type in available"
          :key="type"
          type="button"
          class="block px-3 py-2.5 w-full text-start border-b transition-colors border-n-weak last:border-0 hover:bg-n-alpha-1"
          @click="add(type)"
        >
          <div class="text-[13px] font-semibold text-n-slate-12">
            {{ t(`TOLZAR_SKILLS.TYPE.${type}`) }}
          </div>
          <div class="text-[11px] text-n-slate-10">
            {{ t(`TOLZAR_SKILLS.TYPE_HINT.${type}`) }}
          </div>
        </button>
      </div>
    </div>

    <p v-if="!props.live" class="mt-1.5 mb-3 text-xs text-n-slate-11">
      {{ t('TOLZAR_HONEST.SKILLS_SOON') }}
    </p>
    <template v-else>
      <div
        class="flex gap-2 items-start px-2.5 py-2 mt-2 mb-3 text-xs rounded-lg border text-n-amber-11 bg-n-amber-3 border-n-amber-6"
        role="note"
        data-tz-skills-banner
      >
        <span class="flex-shrink-0 mt-0.5 i-lucide-shield-check size-3.5" />
        <span>{{ t('TOLZAR_SKILLS.BANNER') }}</span>
      </div>
      <label class="flex gap-2 items-center mb-1 text-[13px] text-n-slate-12">
        <input
          v-model="form.skills_enabled"
          type="checkbox"
          class="accent-n-brand"
        />
        {{ t('TOLZAR_SKILLS.ENABLED') }}
      </label>
      <p class="mt-0 mb-3 text-[11.5px] text-n-slate-10">
        {{ t('TOLZAR_SKILLS.ENABLED_HINT') }}
      </p>
      <label class="flex gap-2 items-center mb-3 text-[12px] text-n-slate-11">
        <input
          type="checkbox"
          class="accent-n-brand"
          :checked="form.skills_dry_run_workflows !== false"
          disabled
        />
        {{ t('TOLZAR_SKILLS.DRY_RUN') }}
      </label>
      <p
        v-for="p in listProblems"
        :key="p.error"
        class="mt-0 mb-2 text-xs text-n-ruby-11"
      >
        {{ t(`TOLZAR_SKILLS.ERROR.${p.error}`, { max: MAX_SKILLS }) }}
      </p>
      <div v-if="!form.skills.length" class="text-[13px] text-n-slate-10">
        {{ t('TOLZAR_SKILLS.EMPTY') }}
      </div>
    </template>

    <div
      v-for="(sk, i) in form.skills"
      :key="sk.type"
      class="p-3 mb-2.5 rounded-xl border border-n-weak bg-n-alpha-1"
      :class="{ 'opacity-60': !props.live || !sk.enabled }"
      :data-tz-skill="sk.type"
    >
      <div class="flex justify-between items-center mb-1.5">
        <label class="inline-flex gap-1.5 items-center text-[13px] font-bold">
          <input
            v-model="sk.enabled"
            type="checkbox"
            class="accent-n-brand"
            :disabled="!props.live"
          />
          <span
            class="inline-block rounded-full size-2"
            :class="ACCENT[sk.type] || 'bg-n-slate-9'"
            aria-hidden="true"
          />
          <span class="text-n-slate-12">{{
            t(`TOLZAR_SKILLS.TYPE.${sk.type}`)
          }}</span>
        </label>
        <button
          type="button"
          class="grid place-content-center rounded-lg transition-colors size-6 text-n-slate-10 hover:text-n-ruby-11 hover:bg-n-alpha-2 disabled:pointer-events-none"
          :disabled="!props.live"
          :aria-label="t('TOLZAR_SKILLS.REMOVE')"
          @click="remove(i)"
        >
          <span class="i-lucide-x size-4" />
        </button>
      </div>
      <label class="block mb-1 text-[11.5px] text-n-slate-11">{{
        t('TOLZAR_SKILLS.WHEN')
      }}</label>
      <textarea
        v-model="sk.when"
        :readonly="!props.live"
        rows="2"
        :maxlength="MAX_WHEN + 40"
        :placeholder="t('TOLZAR_SKILLS.WHEN_PLACEHOLDER')"
        class="box-border p-2 w-full text-[12.5px] rounded-lg border outline-none resize-y border-n-weak bg-n-solid-1 text-n-slate-12 focus:border-n-brand"
      />
      <div class="text-[10.5px] text-n-slate-10 text-end">
        {{ (sk.when || '').trim().length }} / {{ MAX_WHEN }}
      </div>

      <template v-if="props.live">
        <div
          v-for="[key, label, options] in pickers(sk.type)"
          :key="key"
          class="mt-2"
        >
          <div class="mb-1 text-[11.5px] text-n-slate-11">
            {{ t(`TOLZAR_SKILLS.PICK.${label}`) }}
          </div>
          <div class="flex flex-wrap gap-1.5">
            <button
              v-for="o in withSaved(options, sk.config[key])"
              :key="String(o.value)"
              type="button"
              class="px-2 py-0.5 text-xs rounded-full border transition-colors"
              :class="[
                isOn(sk, key, o.value)
                  ? 'text-white border-transparent bg-n-brand'
                  : 'border-n-weak text-n-slate-11 hover:bg-n-alpha-2',
                o.missing ? 'line-through' : '',
              ]"
              :title="o.missing ? t('TOLZAR_SKILLS.MISSING') : ''"
              :aria-pressed="isOn(sk, key, o.value)"
              @click="toggle(sk, key, o.value)"
            >
              {{ o.label }}
            </button>
            <span
              v-if="!withSaved(options, sk.config[key]).length"
              class="text-xs text-n-slate-10"
            >
              {{ t('TOLZAR_SKILLS.NONE_AVAILABLE') }}
            </span>
          </div>
        </div>
        <div v-if="sk.type === 'add_tag'" class="mt-2">
          <div class="mb-1 text-[11.5px] text-n-slate-11">
            {{ t('TOLZAR_SKILLS.PICK.TAGS') }}
          </div>
          <input
            :value="tagsOf(sk)"
            :class="INPUT"
            :placeholder="t('TOLZAR_SKILLS.TAGS_PLACEHOLDER')"
            :aria-label="t('TOLZAR_SKILLS.PICK.TAGS')"
            @input="setTags(sk, $event.target.value)"
          />
        </div>
        <p
          v-if="sk.type === 'close'"
          class="mt-2 mb-0 text-[11.5px] text-n-slate-10"
        >
          {{ t('TOLZAR_SKILLS.CLOSE_HINT') }}
        </p>
        <p
          v-for="p in problemsAt(i)"
          :key="p.error"
          class="mt-1.5 mb-0 text-xs text-n-ruby-11"
        >
          {{
            t(`TOLZAR_SKILLS.ERROR.${p.error}`, {
              max: p.error === 'when_too_long' ? MAX_WHEN : MAX_LIST,
            })
          }}
        </p>
      </template>
    </div>
  </section>
</template>

<style scoped>
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
}
</style>
