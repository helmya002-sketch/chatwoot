<script setup>
// Tolzar: the first screen of an empty inbox. Tolzar's own path to a working AI inbox (the same four steps as the
// website's "How it works"), with icons instead of pictures; the setup guide (tolzar_onboarding) does the rest.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStoreGetters } from 'dashboard/composables/store';

const getters = useStoreGetters();
const { t } = useI18n();
const globalConfig = computed(() => getters['globalConfig/get'].value);
const currentUser = computed(() => getters.getCurrentUser.value);

const greetingMessage = computed(() => {
  const hours = new Date().getHours();
  let translationKey;
  if (hours < 12) {
    translationKey = 'ONBOARDING.GREETING_MORNING';
  } else if (hours < 18) {
    translationKey = 'ONBOARDING.GREETING_AFTERNOON';
  } else {
    translationKey = 'ONBOARDING.GREETING_EVENING';
  }
  return t(translationKey, {
    name: currentUser.value.name,
    installationName: globalConfig.value.installationName,
  });
});

// Shown to admins only (EmptyState.vue); others with no channel see the "ask your admin" message there.
const steps = [
  { key: 'CHANNEL', icon: 'i-lucide-plug', to: 'settings_inbox_new' },
  { key: 'TEACH', icon: 'i-lucide-graduation-cap', to: 'tolzar_ai_agents' },
  { key: 'SHADOW', icon: 'i-lucide-eye', to: 'tolzar_results' },
  { key: 'TEAM', icon: 'i-lucide-users', to: 'agent_list' },
];
</script>

<template>
  <div
    class="min-h-screen lg:max-w-4xl max-w-3xl mx-auto flex flex-col gap-6 p-8 w-full font-inter overflow-auto"
  >
    <div>
      <p class="text-xl font-semibold text-n-slate-12 font-interDisplay">
        {{ greetingMessage }}
      </p>
      <p class="mt-1 text-n-slate-11 max-w-2xl text-base">
        {{ $t('ONBOARDING.TOLZAR.INTRO') }}
      </p>
    </div>

    <ol class="flex flex-col gap-3 list-none p-0 m-0">
      <li
        v-for="(step, index) in steps"
        :key="step.key"
        class="flex items-start gap-4 bg-n-surface-2 border border-n-weak rounded-lg p-4"
      >
        <span
          class="flex size-9 shrink-0 items-center justify-center rounded-lg bg-n-alpha-2 text-n-slate-12"
          aria-hidden="true"
        >
          <span :class="step.icon" class="size-5" />
        </span>
        <div class="min-w-0 flex-1">
          <p class="text-base font-semibold text-n-slate-12">
            <span class="text-n-slate-10 tabular-nums">
              {{ index + 1 }}.
            </span>
            {{ $t(`ONBOARDING.TOLZAR.${step.key}.TITLE`) }}
          </p>
          <p class="mt-0.5 text-sm text-n-slate-11">
            {{ $t(`ONBOARDING.TOLZAR.${step.key}.DESCRIPTION`) }}
          </p>
          <router-link
            :to="{ name: step.to }"
            class="mt-2 inline-flex items-center gap-1 text-sm text-n-blue-11 hover:underline"
          >
            {{ $t(`ONBOARDING.TOLZAR.${step.key}.LINK`) }}
            <span class="i-lucide-arrow-right size-4" aria-hidden="true" />
          </router-link>
        </div>
      </li>
    </ol>

    <router-link
      :to="{ name: 'tolzar_onboarding' }"
      class="self-start inline-flex items-center gap-1.5 rounded-lg bg-n-brand px-3.5 h-9 text-sm font-medium text-white hover:opacity-90"
    >
      <span class="i-lucide-list-checks size-4" aria-hidden="true" />
      {{ $t('ONBOARDING.TOLZAR.GUIDE') }}
    </router-link>
  </div>
</template>
