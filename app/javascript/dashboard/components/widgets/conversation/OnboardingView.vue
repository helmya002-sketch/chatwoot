<script setup>
// Tolzar: the first screen of an empty inbox (admins only, EmptyState.vue). A hero with the greeting and the
// promise, Tolzar's four setup steps as a connected path (step 1 marked "start here"), and a small panel that
// shows how shadow mode works. Icons and theme tokens only (light and dark), no pictures.
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

const steps = [
  { key: 'CHANNEL', icon: 'i-lucide-plug', to: 'settings_inbox_new' },
  { key: 'TEACH', icon: 'i-lucide-graduation-cap', to: 'tolzar_ai_agents' },
  { key: 'SHADOW', icon: 'i-lucide-eye', to: 'tolzar_results' },
  { key: 'TEAM', icon: 'i-lucide-users', to: 'agent_list' },
];

const flow = [
  { key: 'CUSTOMER', icon: 'i-lucide-message-circle' },
  { key: 'AI', icon: 'i-lucide-sparkles' },
  { key: 'TEAM', icon: 'i-lucide-user-check' },
];
</script>

<template>
  <div class="min-h-screen w-full overflow-auto font-inter">
    <div class="mx-auto flex w-full max-w-5xl flex-col gap-6 p-6 lg:p-10">
      <!-- Hero -->
      <section
        class="relative overflow-hidden rounded-2xl border border-n-iris-5 bg-gradient-to-br from-n-iris-3 via-n-solid-1 to-n-solid-1 p-6 lg:p-8"
      >
        <div
          class="pointer-events-none absolute -end-16 -top-16 size-56 rounded-full bg-n-iris-5 opacity-40 blur-3xl"
          aria-hidden="true"
        />
        <p
          class="inline-flex items-center gap-1.5 rounded-full border border-n-iris-6 bg-n-solid-1 px-2.5 py-1 text-xs font-medium text-n-iris-11"
        >
          <span class="i-lucide-clock size-3.5" aria-hidden="true" />
          {{ $t('ONBOARDING.TOLZAR.SETUP_TIME') }}
        </p>
        <h1
          class="mt-4 text-2xl font-semibold tracking-tight text-n-slate-12 font-interDisplay lg:text-3xl"
        >
          {{ greetingMessage }}
        </h1>
        <p class="mt-2 max-w-2xl text-base text-n-slate-11">
          {{ $t('ONBOARDING.TOLZAR.INTRO') }}
        </p>
        <div class="mt-5 flex flex-wrap items-center gap-2">
          <router-link
            :to="{ name: steps[0].to }"
            class="inline-flex h-10 items-center gap-2 rounded-lg bg-n-brand px-4 text-sm font-medium text-white shadow-sm transition hover:opacity-90"
          >
            <span class="i-lucide-plug size-4" aria-hidden="true" />
            {{ $t('ONBOARDING.TOLZAR.CHANNEL.LINK') }}
          </router-link>
          <router-link
            :to="{ name: 'tolzar_onboarding' }"
            class="inline-flex h-10 items-center gap-2 rounded-lg border border-n-weak bg-n-solid-1 px-4 text-sm font-medium text-n-slate-12 transition hover:bg-n-alpha-2"
          >
            <span class="i-lucide-list-checks size-4" aria-hidden="true" />
            {{ $t('ONBOARDING.TOLZAR.GUIDE') }}
          </router-link>
        </div>
      </section>

      <!-- One column: this view lives in the narrow conversation pane on every screen size. -->
      <div class="flex flex-col gap-6">
        <!-- The four steps, as one connected path -->
        <ol class="m-0 flex list-none flex-col gap-3 p-0">
          <li v-for="(step, index) in steps" :key="step.key" class="relative">
            <span
              v-if="index < steps.length - 1"
              class="absolute start-[1.6rem] top-14 -bottom-3 w-px bg-n-weak"
              aria-hidden="true"
            />
            <router-link
              :to="{ name: step.to }"
              class="group flex items-start gap-4 rounded-xl border bg-n-solid-1 p-4 no-underline transition hover:-translate-y-px hover:shadow-md"
              :class="
                index === 0
                  ? 'border-n-iris-6 ring-1 ring-n-iris-5'
                  : 'border-n-weak hover:border-n-iris-5'
              "
            >
              <span
                class="flex size-10 shrink-0 items-center justify-center rounded-xl"
                :class="
                  index === 0
                    ? 'bg-n-brand text-white'
                    : 'bg-n-iris-3 text-n-iris-11'
                "
                aria-hidden="true"
              >
                <span :class="step.icon" class="size-5" />
              </span>
              <div class="min-w-0 flex-1">
                <div class="flex flex-wrap items-center gap-2">
                  <span class="text-xs font-medium tabular-nums text-n-slate-10">
                    {{ $t('ONBOARDING.TOLZAR.STEP', { n: index + 1 }) }}
                  </span>
                  <span
                    v-if="index === 0"
                    class="rounded-full bg-n-iris-3 px-2 py-0.5 text-xs font-medium text-n-iris-11"
                  >
                    {{ $t('ONBOARDING.TOLZAR.START_HERE') }}
                  </span>
                  <span class="ms-auto text-xs text-n-slate-10">
                    {{ $t(`ONBOARDING.TOLZAR.${step.key}.TIME`) }}
                  </span>
                </div>
                <p class="mt-1 text-base font-semibold text-n-slate-12">
                  {{ $t(`ONBOARDING.TOLZAR.${step.key}.TITLE`) }}
                </p>
                <p class="mt-0.5 text-sm text-n-slate-11">
                  {{ $t(`ONBOARDING.TOLZAR.${step.key}.DESCRIPTION`) }}
                </p>
                <span
                  class="mt-2 inline-flex items-center gap-1 text-sm font-medium text-n-iris-11"
                >
                  {{ $t(`ONBOARDING.TOLZAR.${step.key}.LINK`) }}
                  <span
                    class="i-lucide-arrow-right size-4 transition group-hover:translate-x-0.5 rtl:rotate-180"
                    aria-hidden="true"
                  />
                </span>
              </div>
            </router-link>
          </li>
        </ol>

        <!-- How shadow mode works -->
        <aside class="rounded-xl border border-n-weak bg-n-solid-2 p-5">
          <p class="text-sm font-semibold text-n-slate-12">
            {{ $t('ONBOARDING.TOLZAR.FLOW.TITLE') }}
          </p>
          <ol class="m-0 mt-4 flex list-none flex-col gap-4 p-0">
            <li v-for="item in flow" :key="item.key" class="flex items-start gap-3">
              <span
                class="flex size-8 shrink-0 items-center justify-center rounded-full bg-n-solid-1 text-n-iris-11 ring-1 ring-n-weak"
                aria-hidden="true"
              >
                <span :class="item.icon" class="size-4" />
              </span>
              <p class="text-sm text-n-slate-11">
                {{ $t(`ONBOARDING.TOLZAR.FLOW.${item.key}`) }}
              </p>
            </li>
          </ol>
          <p
            class="mt-5 flex items-start gap-2 rounded-lg bg-n-solid-1 p-3 text-xs text-n-slate-11 ring-1 ring-n-weak"
          >
            <span class="i-lucide-shield-check mt-px size-4 shrink-0 text-n-teal-11" aria-hidden="true" />
            {{ $t('ONBOARDING.TOLZAR.FLOW.SAFE') }}
          </p>
        </aside>
      </div>
    </div>
  </div>
</template>
