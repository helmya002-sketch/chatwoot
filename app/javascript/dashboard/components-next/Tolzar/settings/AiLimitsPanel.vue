<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import BrainNotice from './BrainNotice.vue';
import { BTN, BTN_GHOST, INPUT, LABEL, CHECK, SHADOW_BADGE } from './tzClasses';
import {
  allowedDiscount,
  MAX_POLICIES,
  MAX_POLICY_CHARS,
  getNegotiation,
  saveNegotiation,
  getAgentTeams,
  saveAgentTeams,
  teamRows,
  teamsFromRows,
  getTuning,
  runTuning,
  decideTuning,
} from '../tolzarAiLimits';

// Settings hub → AI: negotiation limits (a guard on every reply), which AI agent speaks for
// which team, and the daily improvement proposals (approve / reject; nothing changes by itself).
const props = defineProps({
  section: { type: String, required: true }, // negotiation | agent_teams | tuning
});
const { t } = useI18n();
const accountId = useMapGetter('getCurrentAccountId');

const data = ref(null);
const result = ref(null);
const saved = ref('');
const busy = ref(false);

const allowed = computed(() => (data.value && data.value.form ? allowedDiscount(data.value.form) : 0));

async function load() {
  result.value = null;
  saved.value = '';
  if (props.section === 'negotiation') {
    const r = await getNegotiation(accountId.value);
    const s = r.settings || {};
    data.value = { form: { ...s, perks: (s.perks || []).join('\n'), policies: [...(s.policies || [])] }, instructions: r.instructions || '' };
  } else if (props.section === 'agent_teams') {
    const [m, teams] = await Promise.all([
      getAgentTeams(accountId.value),
      window.axios.get(`/api/v1/accounts/${accountId.value}/teams`).then(x => x.data),
    ]);
    data.value = { rows: teamRows(teams || [], m.teams || {}), agents: m.agents || [], missing: m.missing || [] };
  } else {
    const r = await getTuning(accountId.value);
    data.value = { proposals: r.proposals || [] };
  }
}

const after = (r, ok) => {
  result.value = r;
  saved.value = r && r.ok ? ok : '';
};
async function run(fn) {
  busy.value = true;
  try {
    await fn();
  } finally {
    busy.value = false;
  }
}

// Standing policies: one editable row each (the brain cleans and caps them again on save).
const addPolicy = () => {
  if (data.value.form.policies.length < MAX_POLICIES) data.value.form.policies.push('');
};
const removePolicy = i => data.value.form.policies.splice(i, 1);

const saveLimits = () =>
  run(async () => {
    const r = await saveNegotiation(accountId.value, data.value.form);
    after(r, t('TOLZAR_SETTINGS.R1.SAVED'));
    if (r && r.ok) data.value.instructions = r.instructions || data.value.instructions;
  });
const saveTeams = () =>
  run(async () => {
    after(await saveAgentTeams(accountId.value, teamsFromRows(data.value.rows)), t('TOLZAR_SETTINGS.R1.SAVED'));
  });
const suggest = () =>
  run(async () => {
    const r = await runTuning(accountId.value);
    if (r && r.ok) await load();
    after(r, r && r.proposal ? t('TOLZAR_SETTINGS.AI.SUGGESTED') : t('TOLZAR_SETTINGS.AI.NOTHING_TO_SUGGEST'));
  });
const decide = (p, status, edit) =>
  run(async () => {
    const r = await decideTuning(accountId.value, p.date, status, edit);
    after(r, t('TOLZAR_SETTINGS.AI.DECIDED'));
    if (r && r.ok && r.proposal) Object.assign(p, r.proposal);
  });
const copy = text => navigator.clipboard && navigator.clipboard.writeText(text);

onMounted(load);
</script>

<template>
  <div v-if="data">
    <!-- Negotiation limits -->
    <div v-if="section === 'negotiation'" class="grid gap-5 lg:grid-cols-2">
      <div>
        <label :class="CHECK"><input v-model="data.form.enabled" type="checkbox" /> {{ t('TOLZAR_SETTINGS.AI.NEGOTIATE') }}</label>
        <label :class="LABEL">{{ t('TOLZAR_SETTINGS.AI.FLOOR') }}</label>
        <input v-model.number="data.form.floor_pct" type="number" min="0" max="100" step="0.5" :class="INPUT" />
        <label :class="LABEL">{{ t('TOLZAR_SETTINGS.AI.MAX_DISCOUNT') }}</label>
        <input v-model.number="data.form.max_discount_pct" type="number" min="0" max="100" step="0.5" :class="INPUT" />
        <label :class="LABEL">{{ t('TOLZAR_SETTINGS.AI.PERKS') }}</label>
        <textarea v-model="data.form.perks" rows="4" :class="INPUT" :placeholder="t('TOLZAR_SETTINGS.AI.PERKS_PLACEHOLDER')" />
        <div class="flex justify-between items-baseline">
          <label :class="LABEL">{{ t('TOLZAR_SETTINGS.AI.POLICIES') }}</label>
          <span class="text-xs text-n-slate-10">{{ data.form.policies.length }}/{{ MAX_POLICIES }}</span>
        </div>
        <p class="mt-0 mb-1 text-xs text-n-slate-10">{{ t('TOLZAR_SETTINGS.AI.POLICIES_HINT') }}</p>
        <div v-for="(p, i) in data.form.policies" :key="i" class="flex gap-2 items-center mt-1">
          <input v-model="data.form.policies[i]" type="text" :maxlength="MAX_POLICY_CHARS" :class="INPUT" :placeholder="t('TOLZAR_SETTINGS.AI.POLICY_PLACEHOLDER')" />
          <span class="text-[11px] text-n-slate-10 shrink-0">{{ (p || '').length }}/{{ MAX_POLICY_CHARS }}</span>
          <button type="button" class="text-xs text-n-ruby-11 shrink-0" :aria-label="t('TOLZAR_SETTINGS.AI.POLICY_REMOVE')" @click="removePolicy(i)">{{ t('TOLZAR_SETTINGS.AI.POLICY_REMOVE') }}</button>
        </div>
        <button type="button" :class="BTN_GHOST" class="!h-7 !mt-2" :disabled="data.form.policies.length >= MAX_POLICIES" @click="addPolicy">{{ t('TOLZAR_SETTINGS.AI.POLICY_ADD') }}</button>
        <p class="p-2 mt-3 text-[13px] rounded-lg bg-n-alpha-1">{{ t('TOLZAR_SETTINGS.AI.ALLOWED', { n: allowed }) }}</p>
        <button type="button" :class="BTN" :disabled="busy" @click="saveLimits">{{ t('TOLZAR_SETTINGS.SAVE') }}</button>
      </div>
      <div>
        <h3 class="m-0 text-sm font-semibold text-n-slate-12">{{ t('TOLZAR_SETTINGS.AI.SNIPPET') }}</h3>
        <p class="mt-1 text-xs text-n-slate-10">{{ t('TOLZAR_SETTINGS.AI.SNIPPET_HINT') }}</p>
        <pre class="overflow-auto p-2 text-xs whitespace-pre-wrap rounded bg-n-alpha-1">{{ data.instructions }}</pre>
        <button type="button" :class="BTN_GHOST" @click="copy(data.instructions)">{{ t('TOLZAR_SETTINGS.AI.COPY') }}</button>
      </div>
    </div>

    <!-- Agent per team -->
    <div v-if="section === 'agent_teams'" class="max-w-[620px]">
      <div v-for="r in data.rows" :key="r.id" class="flex gap-3 items-center py-2 border-t border-solid border-n-weak text-[13px]">
        <span class="flex-1">{{ r.name }}</span>
        <select v-model="r.agent" :class="INPUT" class="!w-[240px]">
          <option value="">{{ t('TOLZAR_SETTINGS.AI.DEFAULT_AGENT') }}</option>
          <option v-for="a in data.agents" :key="a.id" :value="a.id">{{ a.name || a.id }}</option>
        </select>
      </div>
      <p v-if="!data.rows.length" class="text-n-slate-10 text-[13px]">{{ t('TOLZAR_SETTINGS.AI.NO_TEAMS') }}</p>
      <p v-if="data.missing.length" class="text-xs text-amber-700">{{ t('TOLZAR_SETTINGS.AI.MISSING_AGENT', { teams: data.missing.join(', ') }) }}</p>
      <p class="text-xs text-n-slate-10">{{ t('TOLZAR_SETTINGS.AI.TEAMS_NOTE') }}</p>
      <button type="button" :class="BTN" :disabled="busy" @click="saveTeams">{{ t('TOLZAR_SETTINGS.SAVE') }}</button>
    </div>

    <!-- Tuning proposals -->
    <div v-if="section === 'tuning'">
      <span :class="SHADOW_BADGE">{{ t('TOLZAR_SETTINGS.AI.PROPOSALS_ONLY') }}</span>
      <div>
        <button type="button" :class="BTN_GHOST" :disabled="busy" @click="suggest">{{ busy ? '…' : t('TOLZAR_SETTINGS.AI.SUGGEST_NOW') }}</button>
      </div>
      <div v-for="p in data.proposals" :key="p.date" class="p-3 mt-3 rounded-lg border border-solid border-n-weak">
        <div class="flex flex-wrap gap-2 justify-between items-center">
          <b class="text-[13.5px]">{{ p.date }} · {{ p.agent_name || p.agent_id }}</b>
          <span class="text-xs text-n-slate-10">{{ t('TOLZAR_SETTINGS.AI.SIGNALS', { n: p.signals || 0 }) }} · {{ t(`TOLZAR_SETTINGS.AI.STATUS.${p.status}`) }}</span>
        </div>
        <div v-for="e in p.edits" :key="e.n" class="pt-2 mt-2 border-t border-solid border-n-weak">
          <pre class="p-2 m-0 text-xs whitespace-pre-wrap rounded bg-n-alpha-1">{{ e.edit }}</pre>
          <p class="mt-1 mb-0 text-xs text-n-slate-11">{{ e.reason }}</p>
          <ul v-if="(e.signals || []).length" class="pl-4 my-1 text-xs text-n-slate-10">
            <li v-for="(s, i) in e.signals" :key="i">{{ s.text || s }}</li>
          </ul>
          <div class="flex flex-wrap gap-2 items-center">
            <span class="text-xs text-n-slate-10">{{ t(`TOLZAR_SETTINGS.AI.STATUS.${e.status}`) }}</span>
            <template v-if="e.status === 'proposed'">
              <button type="button" :class="BTN" class="!mt-1 !h-7" :disabled="busy" @click="decide(p, 'approved', e.n)">{{ t('TOLZAR_SETTINGS.AI.APPROVE') }}</button>
              <button type="button" :class="BTN_GHOST" class="!mt-1 !h-7" :disabled="busy" @click="decide(p, 'rejected', e.n)">{{ t('TOLZAR_SETTINGS.AI.REJECT') }}</button>
            </template>
            <button v-if="e.status === 'approved'" type="button" class="text-xs text-n-brand" @click="copy(e.edit)">{{ t('TOLZAR_SETTINGS.AI.COPY') }}</button>
          </div>
        </div>
      </div>
      <p v-if="!data.proposals.length" class="text-n-slate-10 text-[13px]">{{ t('TOLZAR_SETTINGS.NONE_YET') }}</p>
      <p class="text-xs text-n-slate-10">{{ t('TOLZAR_SETTINGS.AI.APPROVE_NOTE') }}</p>
    </div>
    <BrainNotice :result="result" :saved="saved" />
  </div>
</template>
