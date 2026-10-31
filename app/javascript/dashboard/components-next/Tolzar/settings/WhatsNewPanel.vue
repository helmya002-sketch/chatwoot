<script setup>
import { ref, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';

// Settings → What's new (round 4, c90): this workspace's release notes (Tolzar::WhatsNew), newest first. Only what
// this workspace can actually use is listed.
const { t } = useI18n();
const accountId = useMapGetter('getCurrentAccountId');
const releases = ref(null);
const failed = ref(false);

onMounted(async () => {
  try {
    const { data } = await window.axios.get(
      `/api/v1/accounts/${accountId.value}/tolzar/whats_new`
    );
    releases.value = data.releases || [];
  } catch {
    failed.value = true;
  }
});
</script>

<template>
  <div class="max-w-[720px]">
    <p v-if="failed" class="text-[13px] text-n-ruby-11" role="alert">
      {{ t('TOLZAR_SETTINGS_UI.DOCS.FAILED') }}
    </p>
    <p
      v-else-if="releases && !releases.length"
      class="text-[13px] text-n-slate-11"
    >
      {{ t('TOLZAR_SETTINGS_UI.WHATS_NEW.EMPTY') }}
    </p>
    <section
      v-for="r in releases || []"
      :key="r.release"
      class="mb-5"
      :aria-label="r.release"
    >
      <h3 class="m-0 mb-2 text-xs font-semibold uppercase text-n-slate-10">
        {{ r.date }}
      </h3>
      <ul class="m-0 p-0 list-none flex flex-col gap-2">
        <li
          v-for="item in r.items"
          :key="item.title"
          class="p-3 rounded-xl border border-solid border-n-weak bg-n-solid-1"
        >
          <b class="block text-sm text-n-slate-12">{{ item.title }}</b>
          <span class="text-[13px] text-n-slate-11">{{ item.text }}</span>
        </li>
      </ul>
    </section>
  </div>
</template>
