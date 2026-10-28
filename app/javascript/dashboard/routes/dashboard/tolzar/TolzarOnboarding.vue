<script setup>
import { ref, computed, onMounted } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';

// Tolzar onboarding (E1, approved mock saas-signup-roles-mobile-v1): any business sets up its
// workspace in five steps. The AI agent starts from a ready-made template, reads the website,
// and runs in Shadow until the scoreboard says it's ready. Industry packs are optional.
const accountId = useMapGetter('getCurrentAccountId');
const base = computed(() => `/api/v1/accounts/${accountId.value}/tolzar`);

const PACKS = [
  { key: 'general', template: 'tpl-sales-receptionist', workflows: [] },
  { key: 'retail', template: 'tpl-ecommerce', workflows: ['nps-after-purchase'] },
  { key: 'services', template: 'tpl-appointments', workflows: ['appointment-reminders', 'no-show-follow-up'] },
  { key: 'sales', template: 'tpl-speed-to-lead', workflows: ['speed-to-lead'] },
  { key: 'support', template: 'tpl-support', workflows: [] },
  { key: 'travel', template: 'tpl-travel', workflows: ['post-trip-review-referral'] },
];
const step = ref(1);
const form = ref({ name: '', website: '', pack: 'general', languages: '', agentName: 'Assistant' });
const busy = ref(false);
const result = ref({ agent: null, workflows: 0, chunks: null, error: '' });
const templates = ref([]);
const wfTemplates = ref([]);

onMounted(async () => {
  const [a, w] = await Promise.all([
    window.axios.get(`${base.value}/brain/agent_templates`).then(r => r.data).catch(() => ({})),
    window.axios.get(`${base.value}/workflows/templates`).then(r => r.data).catch(() => ({})),
  ]);
  templates.value = a.templates || [];
  wfTemplates.value = w.templates || [];
});

async function saveWorkspace() {
  if (form.value.name.trim()) {
    await window.axios.patch(`/api/v1/accounts/${accountId.value}`, { name: form.value.name.trim() });
  }
  step.value = 2;
}

async function createAgent() {
  busy.value = true;
  result.value.error = '';
  try {
    const pack = PACKS.find(p => p.key === form.value.pack);
    const t = templates.value.find(x => x.id === pack.template);
    const url = form.value.website.trim();
    const agent = {
      id: `a${Math.random().toString(36).slice(2, 9)}`,
      name: form.value.agentName || 'Assistant',
      emoji: '🤖',
      status: 'active',
      description: t ? t.description : '',
      instructions: t ? t.generic.instructions : '',
      skills: [],
      template: pack.template,
      knowledge: url ? [{ type: /sitemap/i.test(url) ? 'sitemap' : 'url', label: 'Website', value: url }] : [],
      generic: {
        enabled: true,
        ...(t ? JSON.parse(JSON.stringify(t.generic)) : {}),
        languages: form.value.languages.split(',').map(x => x.trim()).filter(Boolean),
        teams: {},
      },
    };
    await window.axios.post(`${base.value}/agents`, { agent });
    result.value.agent = agent;
    if (url) {
      const r = await window.axios.post(`${base.value}/brain/knowledge_refresh`, { id: agent.id });
      result.value.chunks = r.data.total ?? null;
    }
    let n = 0;
    for (const id of pack.workflows) {
      const wf = wfTemplates.value.find(x => x.id === id);
      if (wf) {
        await window.axios.post(`${base.value}/workflows`, { workflow: { ...wf, id: `${wf.id}-${agent.id}`, status: 'draft' } });
        n += 1;
      }
    }
    result.value.workflows = n;
    step.value = 3;
  } catch (e) {
    result.value.error = String(e);
  } finally {
    busy.value = false;
  }
}
</script>

<template>
  <div class="overflow-auto flex-1 bg-n-background" data-tz-build="onboarding-1">
    <div class="mx-auto max-w-[860px] px-5 pb-16 pt-7">
      <div class="flex flex-wrap gap-2 mb-4">
        <span
          v-for="n in 5"
          :key="n"
          class="px-2.5 py-1 text-xs rounded-full"
          :class="n === step ? 'font-semibold text-n-brand bg-n-brand/10' : n < step ? 'text-emerald-600 bg-emerald-500/10' : 'text-n-slate-10 bg-n-alpha-1'"
          >{{ n }} {{ $t(`TOLZAR_ONBOARDING.STEP.${n}`) }}</span
        >
      </div>

      <div class="p-5 rounded-xl border bg-n-solid-1 border-n-weak">
        <template v-if="step === 1">
          <h2 class="mt-0 text-[17px] font-bold">{{ $t('TOLZAR_ONBOARDING.WORKSPACE.TITLE') }}</h2>
          <label class="tz-lab">{{ $t('TOLZAR_ONBOARDING.WORKSPACE.NAME') }}</label>
          <input v-model="form.name" class="tz-in" />
          <button type="button" class="tz-btn" @click="saveWorkspace">{{ $t('TOLZAR_ONBOARDING.NEXT') }}</button>
        </template>

        <template v-else-if="step === 2">
          <h2 class="mt-0 text-[17px] font-bold">{{ $t('TOLZAR_ONBOARDING.AGENT.TITLE') }}</h2>
          <p class="text-[13px] text-n-slate-10">{{ $t('TOLZAR_ONBOARDING.AGENT.HINT') }}</p>
          <label class="tz-lab">{{ $t('TOLZAR_ONBOARDING.AGENT.WEBSITE') }}</label>
          <input v-model="form.website" class="tz-in" placeholder="https://www.yourbusiness.com" />
          <label class="tz-lab">{{ $t('TOLZAR_ONBOARDING.AGENT.PACK') }}</label>
          <div class="grid gap-2 md:grid-cols-3">
            <button
              v-for="p in PACKS"
              :key="p.key"
              type="button"
              class="p-3 text-left rounded-lg border"
              :class="form.pack === p.key ? 'border-n-brand ring-2 ring-n-brand/20' : 'border-n-weak'"
              @click="form.pack = p.key"
            >
              <b class="text-[13px]">{{ $t(`TOLZAR_ONBOARDING.PACK.${p.key}`) }}</b>
              <div class="text-xs text-n-slate-10">{{ (templates.find(t => t.id === p.template) || {}).description }}</div>
            </button>
          </div>
          <label class="tz-lab">{{ $t('TOLZAR_ONBOARDING.AGENT.NAME') }}</label>
          <input v-model="form.agentName" class="tz-in" />
          <label class="tz-lab">{{ $t('TOLZAR_ONBOARDING.AGENT.LANGUAGES') }}</label>
          <input v-model="form.languages" class="tz-in" placeholder="English, Arabic, German" />
          <p v-if="result.error" class="text-sm text-rose-600">{{ result.error }}</p>
          <button type="button" class="tz-btn" :disabled="busy" @click="createAgent">{{ busy ? '…' : $t('TOLZAR_ONBOARDING.AGENT.CREATE') }}</button>
        </template>

        <template v-else-if="step === 3">
          <h2 class="mt-0 text-[17px] font-bold">{{ $t('TOLZAR_ONBOARDING.CHANNEL.TITLE') }}</h2>
          <p class="text-[13px] text-n-slate-11">{{ $t('TOLZAR_ONBOARDING.CHANNEL.READY', { name: result.agent?.name, chunks: result.chunks ?? 0, workflows: result.workflows }) }}</p>
          <p class="text-[13px] text-n-slate-10">{{ $t('TOLZAR_ONBOARDING.CHANNEL.HINT') }}</p>
          <router-link :to="`/app/accounts/${accountId}/settings/inboxes/new`" class="tz-btn no-underline">{{ $t('TOLZAR_ONBOARDING.CHANNEL.ADD') }}</router-link>
          <button type="button" class="ml-2 tz-btn-ghost" @click="step = 4">{{ $t('TOLZAR_ONBOARDING.NEXT') }}</button>
        </template>

        <template v-else-if="step === 4">
          <h2 class="mt-0 text-[17px] font-bold">{{ $t('TOLZAR_ONBOARDING.TEAM.TITLE') }}</h2>
          <p class="text-[13px] text-n-slate-10">{{ $t('TOLZAR_ONBOARDING.TEAM.HINT') }}</p>
          <router-link :to="`/app/accounts/${accountId}/settings/agents/list`" class="tz-btn no-underline">{{ $t('TOLZAR_ONBOARDING.TEAM.INVITE') }}</router-link>
          <button type="button" class="ml-2 tz-btn-ghost" @click="step = 5">{{ $t('TOLZAR_ONBOARDING.NEXT') }}</button>
        </template>

        <template v-else>
          <h2 class="mt-0 text-[17px] font-bold">{{ $t('TOLZAR_ONBOARDING.WATCH.TITLE') }}</h2>
          <p class="text-[13px] text-n-slate-11">{{ $t('TOLZAR_ONBOARDING.WATCH.HINT') }}</p>
          <router-link :to="{ name: 'tolzar_reports' }" class="tz-btn no-underline">{{ $t('TOLZAR_ONBOARDING.WATCH.OPEN') }}</router-link>
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
