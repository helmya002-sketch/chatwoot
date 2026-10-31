<script setup>
import { ref, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';

// Settings → Holidays (round 4, c103; Tolzar::Holidays): the days the workspace is closed. On those days every
// inbox with working hours on counts as away all day, in its own time zone. Administrators edit; 404 = off.
const { t } = useI18n();
const accountId = useMapGetter('getCurrentAccountId');
const rows = ref([]);
const off = ref(false);
const notice = ref('');
const url = () => `/api/v1/accounts/${accountId.value}/tolzar/holidays`;

onMounted(async () => {
  try {
    rows.value = (await window.axios.get(url())).data.holidays || [];
  } catch (e) {
    off.value = true;
  }
});

function add() {
  rows.value.push({ date: '', name: '' });
}

async function save() {
  notice.value = '';
  try {
    const { data } = await window.axios.post(url(), {
      holidays: rows.value.filter(r => r.date),
    });
    rows.value = data.holidays || [];
    notice.value = t('TOLZAR_SETTINGS_UI.HOLIDAYS.SAVED');
  } catch {
    notice.value = t('TOLZAR_SETTINGS_UI.DOCS.FAILED');
  }
}
</script>

<template>
  <div class="max-w-[640px]">
    <p v-if="off" class="mt-0 text-[13px] text-n-slate-11">
      {{ t('TOLZAR_SETTINGS_UI.HOLIDAYS.OFF') }}
    </p>
    <template v-else>
      <p class="mt-0 text-[13px] text-n-slate-11">
        {{ t('TOLZAR_SETTINGS_UI.HOLIDAYS.WHAT') }}
      </p>
      <div
        v-for="(r, i) in rows"
        :key="i"
        class="flex flex-wrap gap-2 items-center mt-2"
      >
        <input
          v-model="r.date"
          type="date"
          class="px-2 py-1 text-sm rounded-md border border-solid border-n-weak bg-n-solid-2 text-n-slate-12"
          :aria-label="t('TOLZAR_SETTINGS_UI.HOLIDAYS.DATE')"
        />
        <input
          v-model="r.name"
          maxlength="60"
          class="flex-1 min-w-[160px] px-2 py-1 text-sm rounded-md border border-solid border-n-weak bg-n-solid-2 text-n-slate-12"
          :placeholder="t('TOLZAR_SETTINGS_UI.HOLIDAYS.NAME')"
          :aria-label="t('TOLZAR_SETTINGS_UI.HOLIDAYS.NAME')"
        />
        <button
          type="button"
          class="px-2 py-1 text-xs rounded-md text-n-ruby-11"
          @click="rows.splice(i, 1)"
        >
          {{ t('TOLZAR_SETTINGS_UI.HOLIDAYS.REMOVE') }}
        </button>
      </div>
      <div class="flex gap-2 mt-3">
        <button
          type="button"
          class="px-3 py-1 text-sm rounded-md border border-solid border-n-weak bg-n-solid-2 text-n-slate-12"
          @click="add"
        >
          {{ t('TOLZAR_SETTINGS_UI.HOLIDAYS.ADD') }}
        </button>
        <button
          type="button"
          class="px-3 py-1 text-sm rounded-md bg-n-slate-12 text-n-solid-1"
          @click="save"
        >
          {{ t('TOLZAR_SETTINGS_UI.HOLIDAYS.SAVE') }}
        </button>
      </div>
      <p v-if="notice" class="text-[13px] text-n-slate-12" role="status">
        {{ notice }}
      </p>
    </template>
  </div>
</template>
