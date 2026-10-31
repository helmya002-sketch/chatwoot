<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { useLocale } from 'shared/composables/useLocale';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import BrainNotice from './BrainNotice.vue';
import { BTN, BTN_GHOST, INPUT, LABEL, TONE_WARN } from './tzClasses';
import { fmtAt } from '../tolzarTime';
import {
  WEEKDAYS,
  getWorkspaceSettings,
  saveWorkspaceSettings,
  workspaceFields,
  formFromView,
  buildPatch,
  isEmptyPatch,
  fieldErrors,
  isConflict,
  isOwner,
  defaultOf,
  hasOverride,
} from '../tolzarWorkspace';

// Settings hub → Workspace settings: the editable keys of the brain's workspace settings, each
// showing its default and whether it is changed here. Saving sends only the difference; a 409
// (someone saved in between) asks to reload; a 400 puts the brain's errors on their fields.
const { t } = useI18n();
const { resolvedLocale } = useLocale();
const accountId = useMapGetter('getCurrentAccountId');

const view = ref(null);
const form = ref({});
const resets = ref([]);
const result = ref(null);
const saved = ref('');
const conflict = ref(false);
const errors = ref({ byPath: {}, other: [] });
const busy = ref(false);
const loadFailed = ref(false);

const fields = computed(() => (view.value ? workspaceFields(view.value) : []));
const owner = computed(() => isOwner(view.value));
const GROUPS = [
  'general',
  'hours',
  'budgets',
  'templates',
  'places',
  'categories',
  'teams',
];
const grouped = computed(() =>
  GROUPS.map(g => [g, fields.value.filter(f => f.group === g)]).filter(
    ([, fs]) => fs.length
  )
);
const timezones = computed(() => {
  let list = [];
  try {
    list = Intl.supportedValuesOf('timeZone');
  } catch (e) {
    list = [];
  }
  const cur = form.value.timezone;
  return cur && !list.includes(cur)
    ? [cur, 'UTC', ...list]
    : ['UTC', ...list.filter(z => z !== 'UTC')];
});
// ~400 zones: a searchable combobox instead of a bare <select>. Picking the chosen zone again
// would clear it in ComboBox, so an empty value is ignored (a timezone is never "none").
const timezoneOptions = computed(() =>
  timezones.value.map(z => ({ value: z, label: z.replace(/_/g, ' ') }))
);
function pickTimezone(path, v) {
  if (v) form.value[path] = v;
}

function apply(v) {
  view.value = v;
  form.value = formFromView(v);
  resets.value = [];
  errors.value = { byPath: {}, other: [] };
  conflict.value = false;
}
async function load() {
  busy.value = true;
  loadFailed.value = false;
  try {
    const v = await getWorkspaceSettings(accountId.value);
    if (v && v.ok !== false) apply(v);
    else {
      loadFailed.value = true;
      result.value = v;
    }
  } catch (e) {
    loadFailed.value = true;
  } finally {
    busy.value = false;
  }
}

const key = path => path.replace(/\./g, '_');
function label(f) {
  if (f.group === 'templates')
    return t('TOLZAR_WORKSPACE.TEMPLATE', {
      name: t(`TOLZAR_WORKSPACE.TEMPLATE_NAME.${f.name}`),
      lang: f.lang,
    });
  if (f.group === 'places')
    return t('TOLZAR_WORKSPACE.PLACE', { name: f.name });
  if (f.group === 'categories')
    return t('TOLZAR_WORKSPACE.CATEGORY', { name: f.name });
  if (f.group === 'teams') return t('TOLZAR_WORKSPACE.TEAM', { name: f.name });
  return t(`TOLZAR_WORKSPACE.FIELD.${key(f.path)}`);
}
const hint = f => {
  const k = `TOLZAR_WORKSPACE.FIELD_HINT.${key(f.path)}`;
  const s = t(k);
  return s === k ? '' : s;
};
function shown(f, v) {
  if (f.kind === 'days')
    return v.map(d => t(`TOLZAR_WORKSPACE.DAYS.${d}`)).join(', ');
  if (Array.isArray(v)) return v.join(', ');
  return v === null || v === undefined ? '' : String(v);
}
function defaultLine(f) {
  const v = shown(f, defaultOf(view.value, f));
  return v
    ? t('TOLZAR_WORKSPACE.DEFAULT', {
        value: v.length > 120 ? `${v.slice(0, 120)}…` : v,
      })
    : t('TOLZAR_WORKSPACE.DEFAULT_EMPTY');
}
function defaultText(f) {
  const h = hint(f);
  const d = defaultLine(f);
  return h ? `${d} · ${h}` : d;
}
const changed = f => hasOverride(view.value, f);
const resetting = f => resets.value.includes(f.path);
function toggleReset(f) {
  resets.value = resetting(f)
    ? resets.value.filter(p => p !== f.path)
    : [...resets.value, f.path];
}
function toggleDay(d) {
  const days = form.value['working_hours.closed_days'] || [];
  form.value['working_hours.closed_days'] = days.includes(d)
    ? days.filter(x => x !== d)
    : [...days, d];
}

async function save() {
  saved.value = '';
  result.value = null;
  const patch = buildPatch(view.value, form.value, fields.value, resets.value);
  if (isEmptyPatch(patch)) {
    saved.value = t('TOLZAR_WORKSPACE.NOTHING_CHANGED');
    return;
  }
  busy.value = true;
  try {
    const r = await saveWorkspaceSettings(accountId.value, patch);
    if (isConflict(r)) {
      conflict.value = true;
    } else if (r && r.ok) {
      apply({ ...view.value, ...r });
      saved.value = t('TOLZAR_WORKSPACE.SAVED');
    } else {
      errors.value = fieldErrors(r, fields.value);
      // field errors are shown on their fields; anything else in the notice
      result.value = r && r.errors ? null : r;
    }
  } catch (e) {
    result.value = { ok: false, error: 'brain_unreachable' };
  } finally {
    busy.value = false;
  }
}

onMounted(load);
</script>

<template>
  <div data-tz-workspace-settings>
    <p
      v-if="loadFailed"
      class="p-2 text-[13px] rounded-lg text-n-ruby-11 bg-n-ruby-9/10"
    >
      {{ t('TOLZAR_WORKSPACE.LOAD_FAILED') }}
    </p>
    <template v-if="view">
      <p class="m-0 text-xs text-n-slate-10">
        {{
          view.version
            ? t('TOLZAR_WORKSPACE.VERSION', {
                version: view.version,
                at: fmtAt(view.updated_at, resolvedLocale),
                by: String(view.updated_by || '')
                  .split(':')
                  .pop(),
              })
            : t('TOLZAR_WORKSPACE.NEVER_CHANGED')
        }}
      </p>
      <p v-if="!owner" class="p-2 mt-2 text-xs rounded-lg" :class="TONE_WARN">
        {{ t('TOLZAR_WORKSPACE.OWNER_ONLY_EDIT') }}
      </p>
      <div
        v-if="view.invalid && view.invalid.length"
        class="p-2 mt-2 text-xs rounded-lg text-n-ruby-11 bg-n-ruby-9/10"
      >
        {{ t('TOLZAR_WORKSPACE.INVALID_STORED') }}
        <div v-for="e in view.invalid" :key="e.path">
          {{ e.path }}: {{ e.error }}
        </div>
      </div>

      <section v-for="[group, fs] in grouped" :key="group" class="mt-5">
        <h3 class="m-0 text-sm font-semibold text-n-slate-12">
          {{ t(`TOLZAR_WORKSPACE.GROUP.${group}`) }}
        </h3>
        <div class="grid gap-x-4 md:grid-cols-2">
          <div
            v-for="f in fs"
            :key="f.path"
            :class="
              f.kind === 'longtext' || f.kind === 'lines' ? 'md:col-span-2' : ''
            "
          >
            <label :class="LABEL" class="flex flex-wrap gap-2 items-center">
              <span>{{ label(f) }}</span>
              <span
                v-if="changed(f) && !resetting(f)"
                class="px-1.5 py-px text-[10px] font-semibold rounded-full text-n-brand bg-n-brand/10"
              >
                {{ t('TOLZAR_WORKSPACE.CHANGED') }}
              </span>
              <span
                v-if="resetting(f)"
                class="px-1.5 py-px text-[10px] font-semibold rounded-full"
                :class="TONE_WARN"
              >
                {{ t('TOLZAR_WORKSPACE.WILL_RESET') }}
              </span>
            </label>
            <ComboBox
              v-if="f.kind === 'select'"
              :model-value="form[f.path] || ''"
              :options="timezoneOptions"
              :disabled="!owner || resetting(f)"
              :search-placeholder="t('TOLZAR_SETTINGS_UI.WORKSPACE.SEARCH_TIMEZONE')"
              :empty-state="t('TOLZAR_SETTINGS_UI.WORKSPACE.NO_TIMEZONE')"
              data-tz-timezone
              @update:model-value="pickTimezone(f.path, $event)"
            />
            <input
              v-else-if="f.kind === 'time'"
              v-model="form[f.path]"
              type="time"
              :class="INPUT"
              :aria-label="label(f)"
              :disabled="!owner || resetting(f)"
            />
            <input
              v-else-if="f.kind === 'number'"
              v-model="form[f.path]"
              type="number"
              min="0"
              :class="INPUT"
              :aria-label="label(f)"
              :disabled="!owner || resetting(f)"
            />
            <div v-else-if="f.kind === 'days'" class="flex flex-wrap gap-1.5">
              <button
                v-for="d in WEEKDAYS"
                :key="d"
                type="button"
                class="px-2.5 h-8 text-xs font-semibold rounded-lg border border-solid cursor-pointer disabled:opacity-50"
                :class="
                  (form[f.path] || []).includes(d)
                    ? 'text-white bg-n-slate-11 border-n-slate-11'
                    : 'text-n-slate-11 bg-n-solid-1 border-n-weak'
                "
                :aria-pressed="(form[f.path] || []).includes(d)"
                :disabled="!owner || resetting(f)"
                @click="toggleDay(d)"
              >
                {{ t(`TOLZAR_WORKSPACE.DAYS.${d}`) }}
              </button>
            </div>
            <textarea
              v-else-if="f.kind === 'lines' || f.kind === 'longtext'"
              v-model="form[f.path]"
              :rows="f.kind === 'lines' ? 4 : 2"
              :class="INPUT"
              :aria-label="label(f)"
              :disabled="!owner || resetting(f)"
            />
            <input
              v-else
              v-model="form[f.path]"
              :class="INPUT"
              :aria-label="label(f)"
              :disabled="!owner || resetting(f)"
            />
            <div class="flex flex-wrap gap-2 justify-between items-center mt-1">
              <span class="text-[11px] break-all text-n-slate-10">
                {{ defaultText(f) }}
              </span>
              <button
                v-if="owner && changed(f)"
                type="button"
                class="text-[11px] font-semibold bg-transparent border-0 cursor-pointer text-n-brand"
                @click="toggleReset(f)"
              >
                {{
                  resetting(f)
                    ? t('TOLZAR_WORKSPACE.KEEP')
                    : t('TOLZAR_WORKSPACE.RESET')
                }}
              </button>
            </div>
            <p
              v-if="errors.byPath[f.path]"
              class="m-0 mt-1 text-xs text-n-ruby-11"
            >
              {{ errors.byPath[f.path] }}
            </p>
          </div>
        </div>
      </section>

      <div
        v-if="conflict"
        class="flex flex-wrap gap-3 items-center p-3 mt-4 text-[13px] rounded-lg"
        :class="TONE_WARN"
        role="alert"
      >
        <span class="flex-1">{{ t('TOLZAR_WORKSPACE.CONFLICT') }}</span>
        <button type="button" :class="BTN_GHOST" class="!mt-0" @click="load">
          {{ t('TOLZAR_WORKSPACE.RELOAD') }}
        </button>
      </div>
      <div
        v-if="errors.other.length"
        class="p-2 mt-3 text-[13px] rounded-lg text-n-ruby-11 bg-n-ruby-9/10"
      >
        <div v-for="e in errors.other" :key="e">{{ e }}</div>
      </div>
      <button
        v-if="owner"
        type="button"
        :class="BTN"
        :disabled="busy || conflict"
        @click="save"
      >
        {{ t('TOLZAR_SETTINGS.SAVE') }}
      </button>
    </template>
    <BrainNotice :result="result" :saved="saved" />
  </div>
</template>
