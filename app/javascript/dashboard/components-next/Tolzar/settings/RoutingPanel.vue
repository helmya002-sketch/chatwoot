<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import BrainNotice from './BrainNotice.vue';
import { BTN, INPUT, LABEL, TONE_WARN } from './tzClasses';
import {
  getWorkspaceSettings,
  saveWorkspaceSettings,
  isConflict,
} from '../tolzarWorkspace';
import { routingModel, routingForm, routingPatch } from '../tolzarRouting';

// Settings hub → Routing (readiness row 4): places and their keywords, team descriptions, the
// "always a person" words and the hand-over message, on the brain's workspace settings. Every
// administrator sees it; only an Owner saves. Keywords stay read-only while the brain keeps them locked.
const { t } = useI18n();
const accountId = useMapGetter('getCurrentAccountId');

const view = ref(null);
const form = ref(null);
const result = ref(null);
const saved = ref('');
const busy = ref(false);
const conflict = ref(false);

const model = computed(() => (view.value ? routingModel(view.value) : null));
const patch = computed(() =>
  model.value && form.value ? routingPatch(model.value, form.value) : {}
);
const dirty = computed(() => Object.keys(patch.value).length > 0);
const languages = computed(() =>
  form.value ? Object.keys(form.value.handover) : []
);
const ownerLanguages = computed(() =>
  form.value ? Object.keys(form.value.handoverOwners) : []
);

async function load() {
  result.value = null;
  conflict.value = false;
  const v = await getWorkspaceSettings(accountId.value);
  if (!v || v.ok === false) {
    result.value = v;
    return;
  }
  view.value = v;
  form.value = routingForm(routingModel(v));
}

async function save() {
  busy.value = true;
  saved.value = '';
  const r = await saveWorkspaceSettings(accountId.value, {
    version: model.value.version,
    set: patch.value,
  });
  busy.value = false;
  if (r && r.ok !== false && r.detail === undefined) {
    await load();
    saved.value = t('TOLZAR_ROUTING.SAVED');
    return;
  }
  conflict.value = isConflict(r);
  result.value = r;
}

onMounted(load);
</script>

<template>
  <div v-if="model && form" class="flex flex-col gap-4">
    <p class="m-0 text-sm text-n-slate-11">{{ t('TOLZAR_ROUTING.INTRO') }}</p>
    <p
      v-if="!model.keywordsEditable"
      class="m-0 px-3 py-2 text-xs rounded-lg"
      :class="TONE_WARN"
    >
      {{ t('TOLZAR_ROUTING.KEYWORDS_LOCKED') }}
    </p>
    <p v-if="!model.owner" class="m-0 text-xs text-n-slate-10">
      {{ t('TOLZAR_ROUTING.OWNER_ONLY') }}
    </p>

    <section>
      <h4 class="m-0 text-sm font-semibold text-n-slate-12">
        {{ t('TOLZAR_ROUTING.PLACES') }}
      </h4>
      <p v-if="!model.places.length" class="text-xs text-n-slate-10">
        {{ t('TOLZAR_ROUTING.NO_PLACES') }}
      </p>
      <div
        v-for="p in model.places"
        :key="p.key"
        class="p-3 mt-2 rounded-xl border border-n-weak"
      >
        <label :class="LABEL" :for="`tz-route-name-${p.key}`">
          {{ t('TOLZAR_ROUTING.PLACE_NAME', { team: p.team }) }}
        </label>
        <input
          :id="`tz-route-name-${p.key}`"
          v-model="form.places[p.key].name"
          :class="INPUT"
          :disabled="!model.owner"
        />
        <label :class="LABEL" :for="`tz-route-kw-${p.key}`">
          {{ t('TOLZAR_ROUTING.KEYWORDS') }}
        </label>
        <textarea
          :id="`tz-route-kw-${p.key}`"
          v-model="form.places[p.key].keywords"
          rows="2"
          :class="INPUT"
          :disabled="!model.owner || !model.keywordsEditable"
          :placeholder="t('TOLZAR_ROUTING.KEYWORDS_PLACEHOLDER')"
        />
      </div>
    </section>

    <section v-if="model.teams.length">
      <h4 class="m-0 text-sm font-semibold text-n-slate-12">
        {{ t('TOLZAR_ROUTING.TEAMS') }}
      </h4>
      <div v-for="team in model.teams" :key="team">
        <label :class="LABEL" :for="`tz-route-team-${team}`">{{ team }}</label>
        <textarea
          :id="`tz-route-team-${team}`"
          v-model="form.teamDescriptions[team]"
          rows="2"
          :class="INPUT"
          :disabled="!model.owner"
          :placeholder="t('TOLZAR_ROUTING.TEAM_PLACEHOLDER')"
        />
      </div>
    </section>

    <section v-if="model.handoverCategory">
      <h4 class="m-0 text-sm font-semibold text-n-slate-12">
        {{ t('TOLZAR_ROUTING.ALWAYS_PERSON') }}
      </h4>
      <p class="mt-1 mb-0 text-xs text-n-slate-11">
        {{ t('TOLZAR_ROUTING.ALWAYS_PERSON_HINT') }}
      </p>
      <textarea
        v-model="form.alwaysPerson"
        rows="2"
        :class="INPUT"
        :aria-label="t('TOLZAR_ROUTING.ALWAYS_PERSON')"
        :disabled="!model.owner || !model.keywordsEditable"
        :placeholder="t('TOLZAR_ROUTING.ALWAYS_PERSON_PLACEHOLDER')"
      />
      <div v-for="lang in ownerLanguages" :key="`o-${lang}`">
        <label :class="LABEL" :for="`tz-route-hoo-${lang}`">
          {{ t('TOLZAR_ROUTING.ALWAYS_PERSON_MESSAGE', { lang }) }}
        </label>
        <textarea
          :id="`tz-route-hoo-${lang}`"
          v-model="form.handoverOwners[lang]"
          rows="2"
          :class="INPUT"
          :disabled="!model.owner"
        />
      </div>
    </section>

    <section v-if="languages.length">
      <h4 class="m-0 text-sm font-semibold text-n-slate-12">
        {{ t('TOLZAR_ROUTING.HANDOVER') }}
      </h4>
      <div v-for="lang in languages" :key="lang">
        <label :class="LABEL" :for="`tz-route-ho-${lang}`">{{ lang }}</label>
        <textarea
          :id="`tz-route-ho-${lang}`"
          v-model="form.handover[lang]"
          rows="2"
          :class="INPUT"
          :disabled="!model.owner"
        />
      </div>
    </section>

    <div class="flex gap-2 items-center">
      <button
        v-if="model.owner"
        type="button"
        :class="BTN"
        :disabled="busy || !dirty"
        @click="save"
      >
        {{ busy ? t('TOLZAR_UI.SAVING') : t('TOLZAR_ROUTING.SAVE') }}
      </button>
      <button
        v-if="conflict"
        type="button"
        class="text-xs underline"
        @click="load"
      >
        {{ t('TOLZAR_ROUTING.RELOAD') }}
      </button>
    </div>
    <BrainNotice :result="result" :saved="saved" />
  </div>
  <BrainNotice v-else :result="result" />
</template>
