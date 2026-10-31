<script setup>
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { money, resultsView } from './tolzarBookingResults';

// Reports → Results → Bookings: documents issued and bookings made over 7 / 30 / 90 days, from the workspace's
// own records (Tolzar::BookingResults), money per currency. Administrators; hidden when both are off (404).
const { t, locale } = useI18n();
const accountId = useMapGetter('getCurrentAccountId');
const days = ref(30);
const report = ref(null);
const DAYS = [7, 30, 90];
const view = computed(() => resultsView(report.value));

async function load() {
  try {
    const { data } = await window.axios.get(
      `/api/v1/accounts/${accountId.value}/tolzar/booking_results`,
      { params: { days: days.value } }
    );
    report.value = data;
  } catch {
    report.value = null;
  }
}

const cash = row => money(row.total_cents, row.currency, locale.value);
const paid = row => money(row.paid_cents, row.currency, locale.value);
const due = row => money(row.due_cents, row.currency, locale.value);

watch(days, load, { immediate: true });
</script>

<template>
  <section
    v-if="report && (view.documents || view.bookings)"
    class="p-4 mt-6 rounded-xl border border-solid border-n-weak bg-n-solid-1"
  >
    <div class="flex flex-wrap gap-2 justify-between items-center">
      <h2 class="m-0 text-sm font-semibold text-n-slate-12">
        {{ t('TOLZAR_RESULTS_UI.BOOKINGS.TITLE') }}
      </h2>
      <div
        class="flex gap-1"
        role="group"
        :aria-label="t('TOLZAR_RESULTS_UI.BOOKINGS.PERIOD')"
      >
        <button
          v-for="d in DAYS"
          :key="d"
          type="button"
          class="px-2 py-0.5 text-xs rounded-md border border-solid border-n-weak"
          :class="
            d === days
              ? 'bg-n-slate-12 text-n-solid-1'
              : 'bg-n-solid-2 text-n-slate-12'
          "
          :aria-pressed="d === days"
          @click="days = d"
        >
          {{ t('TOLZAR_RESULTS_UI.BOOKINGS.DAYS', { n: d }) }}
        </button>
      </div>
    </div>

    <div class="grid gap-4 mt-3 md:grid-cols-2">
      <div v-if="view.documents">
        <h3 class="m-0 text-xs font-semibold text-n-slate-11 uppercase">
          {{ t('TOLZAR_RESULTS_UI.BOOKINGS.DOCUMENTS') }}
        </h3>
        <p class="mt-1 mb-0 text-sm text-n-slate-12">
          {{
            t('TOLZAR_RESULTS_UI.BOOKINGS.ISSUED', {
              n: view.documents.issued,
              cancelled: view.documents.cancelled,
            })
          }}
        </p>
        <p
          v-if="view.documents.byType.length"
          class="mt-1 mb-0 text-xs text-n-slate-11"
        >
          <span
            v-for="row in view.documents.byType"
            :key="row.type"
            class="me-3"
          >
            {{ t(`TOLZAR_SETTINGS_UI.DOCS.T_${row.type}`) }}: {{ row.n }}
          </span>
        </p>
        <table
          v-if="view.documents.money.length"
          class="mt-2 w-full text-[13px]"
        >
          <thead class="text-xs text-n-slate-11">
            <tr>
              <th class="py-1 text-start font-medium">
                {{ t('TOLZAR_RESULTS_UI.BOOKINGS.VALUE') }}
              </th>
              <th class="py-1 text-end font-medium">
                {{ t('TOLZAR_RESULTS_UI.BOOKINGS.PAID') }}
              </th>
              <th class="py-1 text-end font-medium">
                {{ t('TOLZAR_RESULTS_UI.BOOKINGS.DUE') }}
              </th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="row in view.documents.money"
              :key="row.currency"
              class="border-t border-solid border-n-weak"
            >
              <td class="py-1 tabular-nums">{{ cash(row) }}</td>
              <td class="py-1 text-end tabular-nums">{{ paid(row) }}</td>
              <td class="py-1 text-end tabular-nums">{{ due(row) }}</td>
            </tr>
          </tbody>
        </table>
      </div>

      <div v-if="view.bookings">
        <h3 class="m-0 text-xs font-semibold text-n-slate-11 uppercase">
          {{ t('TOLZAR_RESULTS_UI.BOOKINGS.BOOKINGS') }}
        </h3>
        <p class="mt-1 mb-0 text-xs text-n-slate-11">
          <span
            v-for="row in view.bookings.byStatus"
            :key="row.status"
            class="me-3"
          >
            {{ t(`TOLZAR_SETTINGS_UI.BOOKINGS.ST_${row.status}`) }}:
            {{ row.n }}
          </span>
        </p>
        <table
          v-if="view.bookings.money.length"
          class="mt-2 w-full text-[13px]"
        >
          <thead class="text-xs text-n-slate-11">
            <tr>
              <th class="py-1 text-start font-medium">
                {{ t('TOLZAR_RESULTS_UI.BOOKINGS.VALUE') }}
              </th>
              <th class="py-1 text-end font-medium">
                {{ t('TOLZAR_RESULTS_UI.BOOKINGS.PAID') }}
              </th>
              <th class="py-1 text-end font-medium">
                {{ t('TOLZAR_RESULTS_UI.BOOKINGS.DUE') }}
              </th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="row in view.bookings.money"
              :key="row.currency"
              class="border-t border-solid border-n-weak"
            >
              <td class="py-1 tabular-nums">{{ cash(row) }}</td>
              <td class="py-1 text-end tabular-nums">{{ paid(row) }}</td>
              <td class="py-1 text-end tabular-nums">{{ due(row) }}</td>
            </tr>
          </tbody>
        </table>
        <p v-else class="mt-2 mb-0 text-[13px] text-n-slate-10">
          {{ t('TOLZAR_RESULTS_UI.BOOKINGS.NONE') }}
        </p>
      </div>
    </div>
  </section>
</template>
