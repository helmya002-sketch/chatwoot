<script setup>
import { ref, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { copyTextToClipboard } from 'shared/helpers/clipboard';

// Settings → Bookings → Booking request link (round 4, D1; Tolzar::BookingRequest): the workspace's public booking
// request form, to copy and share, and a reset that makes the old link stop working. Administrators only; hidden
// while TOLZAR_BOOKING_REQUESTS_ACCOUNTS is off (the API answers 404).
const { t } = useI18n();
const accountId = useMapGetter('getCurrentAccountId');
const url = ref('');
const copied = ref(false);
const base = () =>
  `/api/v1/accounts/${accountId.value}/tolzar/booking_request_link`;

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
  if (!window.confirm(t('TOLZAR_SETTINGS_UI.BOOKINGS.REQ_RESET_CONFIRM')))
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
      {{ t('TOLZAR_SETTINGS_UI.BOOKINGS.REQ_TITLE') }}
    </h3>
    <p class="mt-1 mb-2 text-[13px] text-n-slate-11">
      {{ t('TOLZAR_SETTINGS_UI.BOOKINGS.REQ_WHAT') }}
    </p>
    <div class="flex flex-wrap gap-2 items-center">
      <input
        :value="url"
        readonly
        class="flex-1 min-w-[240px] px-2 py-1 text-xs rounded-md border border-solid border-n-weak bg-n-solid-2 text-n-slate-12"
        :aria-label="t('TOLZAR_SETTINGS_UI.BOOKINGS.REQ_TITLE')"
      />
      <button
        type="button"
        class="px-2 py-1 text-xs rounded-md border border-solid border-n-weak bg-n-solid-2 text-n-slate-12"
        @click="copy"
      >
        {{
          copied
            ? t('TOLZAR_SETTINGS_UI.BOOKINGS.REQ_COPIED')
            : t('TOLZAR_SETTINGS_UI.BOOKINGS.REQ_COPY')
        }}
      </button>
      <button
        type="button"
        class="px-2 py-1 text-xs rounded-md text-n-ruby-11"
        @click="reset"
      >
        {{ t('TOLZAR_SETTINGS_UI.BOOKINGS.REQ_RESET') }}
      </button>
    </div>
  </section>
</template>
