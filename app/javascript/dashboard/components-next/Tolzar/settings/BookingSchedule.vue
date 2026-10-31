<script setup>
import { ref, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';

// Settings → Bookings → Schedule (round 4, c102; Tolzar::BookingSchedule): who and what is busy per day for the
// next 14 days, from each line's resource, with a resource used by two bookings on one day flagged as a clash.
const { t } = useI18n();
const accountId = useMapGetter('getCurrentAccountId');
const report = ref(null);
const failed = ref(false);

onMounted(async () => {
  try {
    const { data } = await window.axios.get(
      `/api/v1/accounts/${accountId.value}/tolzar/booking_schedule`
    );
    report.value = data;
  } catch {
    failed.value = true;
  }
});
</script>

<template>
  <section class="mt-3">
    <p v-if="failed" class="text-[13px] text-n-ruby-11" role="alert">
      {{ t('TOLZAR_SETTINGS_UI.DOCS.FAILED') }}
    </p>
    <template v-else-if="report">
      <p class="m-0 text-[13px] text-n-slate-11">
        {{ t('TOLZAR_SETTINGS_UI.BOOKINGS.SCHEDULE_WHAT') }}
      </p>
      <p
        v-if="report.clashes"
        class="mt-2 mb-0 text-[13px] text-n-amber-11"
        role="status"
      >
        {{ t('TOLZAR_SETTINGS_UI.BOOKINGS.CLASHES', { n: report.clashes }) }}
      </p>
      <template v-for="d in report.days" :key="d.date">
        <div v-if="d.resources.length" class="mt-3">
          <h3 class="m-0 text-sm font-semibold text-n-slate-12">
            {{ d.date }}
          </h3>
          <ul class="m-0 mt-1 p-0 list-none">
            <li
              v-for="r in d.resources"
              :key="r.resource"
              class="flex flex-wrap gap-3 text-[13px] py-1 border-b border-n-weak"
            >
              <span class="font-medium text-n-slate-12 min-w-[8rem]">
                {{ r.resource }}
              </span>
              <span class="flex-1 text-n-slate-11">
                {{
                  r.items
                    .map(i => `#${i.booking_id} ${i.description}`)
                    .join(' · ')
                }}
              </span>
              <span
                v-if="r.clash"
                class="px-1.5 rounded text-xs bg-n-amber-3 text-n-amber-11"
              >
                {{ t('TOLZAR_SETTINGS_UI.BOOKINGS.CLASH') }}
              </span>
            </li>
          </ul>
        </div>
      </template>
      <p
        v-if="!report.days.some(d => d.resources.length)"
        class="text-[13px] text-n-slate-11"
      >
        {{ t('TOLZAR_SETTINGS_UI.BOOKINGS.SCHEDULE_EMPTY') }}
      </p>
    </template>
  </section>
</template>
