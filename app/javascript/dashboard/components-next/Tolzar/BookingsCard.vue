<script setup>
import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';

// Conversation sidebar → the guest's bookings in the workspace's booking system (Tolzar::BookingConnector, read
// only). Hidden when the workspace has no connector (the API answers 404) or the guest has no phone/e-mail.
const props = defineProps({
  contactId: { type: [Number, String], default: null },
});
const { t } = useI18n();
const accountId = useMapGetter('getCurrentAccountId');

const state = ref('hidden');
const bookings = ref([]);

async function load() {
  bookings.value = [];
  if (!props.contactId) {
    state.value = 'hidden';
    return;
  }
  state.value = 'loading';
  try {
    const { data } = await window.axios.get(
      `/api/v1/accounts/${accountId.value}/tolzar/booking_connector/bookings`,
      { params: { contact_id: props.contactId } }
    );
    bookings.value = data.bookings || [];
    state.value = 'ready';
  } catch (e) {
    state.value = e?.response?.status === 404 ? 'hidden' : 'error';
  }
}

const label = b => b.voucher_no || b.number || b.id;
const status = b => String(b.status || '').toLowerCase();
const balance = b => {
  const v = b.balance ?? b.balance_due;
  return v == null ? '' : `${b.currency || ''} ${Number(v).toFixed(2)}`.trim();
};

watch(() => props.contactId, load, { immediate: true });
</script>

<template>
  <section
    v-if="state !== 'hidden'"
    class="mt-3 p-3 rounded-xl border border-solid border-n-weak bg-n-solid-1"
  >
    <h3 class="m-0 mb-2 text-xs font-semibold text-n-slate-11 uppercase">
      {{ t('TOLZAR_SETTINGS_UI.BOOKINGS_CARD.TITLE') }}
    </h3>
    <p v-if="state === 'loading'" class="m-0 text-xs text-n-slate-11">
      {{ t('TOLZAR_SETTINGS_UI.BOOKINGS_CARD.LOADING') }}
    </p>
    <p v-else-if="state === 'error'" class="m-0 text-xs text-n-ruby-11">
      {{ t('TOLZAR_SETTINGS_UI.BOOKINGS_CARD.FAILED') }}
    </p>
    <p v-else-if="!bookings.length" class="m-0 text-xs text-n-slate-11">
      {{ t('TOLZAR_SETTINGS_UI.BOOKINGS_CARD.NONE') }}
    </p>
    <ul v-else class="m-0 p-0 list-none flex flex-col gap-2">
      <li
        v-for="b in bookings"
        :key="label(b)"
        class="flex justify-between gap-2 text-xs"
      >
        <span class="font-mono text-n-slate-12">{{ label(b) }}</span>
        <span class="text-n-slate-11">{{ status(b) }}</span>
        <span v-if="balance(b)" class="tabular-nums text-n-slate-12">
          {{
            t('TOLZAR_SETTINGS_UI.BOOKINGS_CARD.BALANCE', {
              amount: balance(b),
            })
          }}
        </span>
      </li>
    </ul>
  </section>
</template>
