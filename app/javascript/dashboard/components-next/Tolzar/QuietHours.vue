<script setup>
import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { useAlert } from 'dashboard/composables';
import { quietHours } from './tolzarPwa';

// Profile → Notifications → Quiet hours (round 4, c64): no push to this person's phone or browser between two
// times, in their own time zone. Saved in their ui_settings; the server applies it (Tolzar::PushPrivacy.quiet?).
const { t } = useI18n();
const { uiSettings, updateUISettings } = useUISettings();
let zone = '';
try {
  zone = Intl.DateTimeFormat().resolvedOptions().timeZone || '';
} catch (e) {
  zone = '';
}
const form = ref(quietHours(uiSettings.value?.tolzar_quiet_hours, zone));
watch(
  () => uiSettings.value?.tolzar_quiet_hours,
  saved => {
    form.value = quietHours(saved, zone);
  }
);

function save() {
  updateUISettings({
    tolzar_quiet_hours: { ...form.value, tz: zone || form.value.tz },
  });
  useAlert(t('TOLZAR_PWA.QUIET.SAVED'));
}
</script>

<template>
  <section
    class="flex flex-col w-full gap-3 p-4 border border-solid border-n-weak rounded-xl"
    :aria-label="t('TOLZAR_PWA.QUIET.TITLE')"
  >
    <label class="flex items-center gap-2 min-h-[44px]">
      <input v-model="form.on" type="checkbox" class="size-5" />
      <span class="text-body-main text-n-slate-12">
        {{ t('TOLZAR_PWA.QUIET.TITLE') }}
      </span>
    </label>
    <p class="m-0 text-sm text-n-slate-11">
      {{ t('TOLZAR_PWA.QUIET.HINT', { zone: form.tz || 'UTC' }) }}
    </p>
    <div class="flex flex-wrap gap-4">
      <label class="flex flex-col gap-1 text-sm text-n-slate-11">
        {{ t('TOLZAR_PWA.QUIET.FROM') }}
        <input
          v-model="form.from"
          type="time"
          class="min-h-[44px] px-3 rounded-lg border border-solid border-n-weak bg-n-solid-1 text-n-slate-12"
          :disabled="!form.on"
        />
      </label>
      <label class="flex flex-col gap-1 text-sm text-n-slate-11">
        {{ t('TOLZAR_PWA.QUIET.TO') }}
        <input
          v-model="form.to"
          type="time"
          class="min-h-[44px] px-3 rounded-lg border border-solid border-n-weak bg-n-solid-1 text-n-slate-12"
          :disabled="!form.on"
        />
      </label>
    </div>
    <button
      type="button"
      class="self-start min-h-[44px] px-4 rounded-lg bg-n-brand text-white font-medium"
      @click="save"
    >
      {{ t('TOLZAR_PWA.QUIET.SAVE') }}
    </button>
  </section>
</template>
