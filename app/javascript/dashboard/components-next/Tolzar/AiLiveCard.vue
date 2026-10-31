<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { aiLiveSummary } from './tolzarShell';

// UI phase 2 (new UI only, body.tz-ui): the sidebar's "AI live" card. How many inboxes the AI runs on in Shadow
// and Live, and the kill switch, from the workspace settings the brain keeps. Read-only; hidden for members who
// cannot read the settings (the endpoint is for administrators) and in the old UI.
const { t } = useI18n();
const accountId = useMapGetter('getCurrentAccountId');
const inboxes = useMapGetter('inboxes/getInboxes');
const settings = ref(null);
const shown = ref(false);

onMounted(async () => {
  if (!document.body.classList.contains('tz-ui')) return;
  try {
    const { data } = await window.axios.get(
      `/api/v1/accounts/${accountId.value}/tolzar/workspace/settings`
    );
    settings.value = data;
    shown.value = true;
  } catch {
    shown.value = false;
  }
});

const summary = computed(() =>
  aiLiveSummary(settings.value, (inboxes.value || []).length)
);
</script>

<template>
  <section
    v-if="shown"
    class="tz-ai-live mx-2 mb-3 p-3 rounded-xl border border-solid border-n-weak bg-n-solid-1"
    :aria-label="t('TOLZAR_SETTINGS_UI.SHELL.AI_LIVE')"
  >
    <div class="flex items-center gap-2 text-xs font-semibold text-n-slate-12">
      <span
        class="tz-ai-dot size-2 rounded-full"
        :class="
          summary.state === 'live'
            ? 'bg-n-teal-8 tz-pulse'
            : summary.state === 'stopped'
              ? 'bg-n-ruby-8'
              : 'bg-n-amber-9'
        "
        aria-hidden="true"
      />
      {{ t(`TOLZAR_SETTINGS_UI.SHELL.STATE_${summary.state}`) }}
    </div>
    <p class="m-0 mt-1 text-xs text-n-slate-11">
      {{
        t('TOLZAR_SETTINGS_UI.SHELL.COUNTS', {
          live: summary.live,
          shadow: summary.shadow,
        })
      }}
    </p>
  </section>
</template>
