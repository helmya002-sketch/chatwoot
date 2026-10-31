<script setup>
import { ref, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { copyTextToClipboard } from 'shared/helpers/clipboard';

// Settings → Bookings → Your calendar link (round 4, c101; Tolzar::BookingCalendar): the signed-in person's own
// private, read-only iCal feed, to copy into a calendar app, and a reset that makes the old link stop working.
const { t } = useI18n();
const accountId = useMapGetter('getCurrentAccountId');
const url = ref('');
const copied = ref(false);
const base = () =>
  `/api/v1/accounts/${accountId.value}/tolzar/booking_calendar`;

async function load() {
  try {
    url.value = (await window.axios.get(base())).data.url || '';
  } catch {
    url.value = '';
  }
}

async function copy() {
  await copyTextToClipboard(url.value);
  copied.value = true;
}

async function reset() {
  // eslint-disable-next-line no-alert
  if (!window.confirm(t('TOLZAR_SETTINGS_UI.BOOKINGS.ICAL_RESET_CONFIRM')))
    return;
  url.value = (await window.axios.post(`${base()}/reset`)).data.url || '';
  copied.value = false;
}

onMounted(load);
</script>

<template>
  <section
    v-if="url"
    class="p-3 mt-6 rounded-xl border border-solid border-n-weak bg-n-solid-1"
  >
    <h3 class="m-0 text-sm font-semibold text-n-slate-12">
      {{ t('TOLZAR_SETTINGS_UI.BOOKINGS.ICAL_TITLE') }}
    </h3>
    <p class="mt-1 mb-2 text-[13px] text-n-slate-11">
      {{ t('TOLZAR_SETTINGS_UI.BOOKINGS.ICAL_WHAT') }}
    </p>
    <div class="flex flex-wrap gap-2 items-center">
      <input
        :value="url"
        readonly
        class="flex-1 min-w-[240px] px-2 py-1 text-xs rounded-md border border-solid border-n-weak bg-n-solid-2 text-n-slate-12"
        :aria-label="t('TOLZAR_SETTINGS_UI.BOOKINGS.ICAL_TITLE')"
      />
      <button
        type="button"
        class="px-2 py-1 text-xs rounded-md border border-solid border-n-weak bg-n-solid-2 text-n-slate-12"
        @click="copy"
      >
        {{
          copied
            ? t('TOLZAR_SETTINGS_UI.BOOKINGS.ICAL_COPIED')
            : t('TOLZAR_SETTINGS_UI.BOOKINGS.ICAL_COPY')
        }}
      </button>
      <button
        type="button"
        class="px-2 py-1 text-xs rounded-md text-n-ruby-11"
        @click="reset"
      >
        {{ t('TOLZAR_SETTINGS_UI.BOOKINGS.ICAL_RESET') }}
      </button>
    </div>
  </section>
</template>
