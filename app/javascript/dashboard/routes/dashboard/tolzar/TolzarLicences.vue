<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import {
  GROUPS,
  getLicences,
  licencesView,
  safeUrl,
  filterItems,
  summaryLine,
  itemLabel,
} from 'dashboard/components-next/Tolzar/tolzarLicences';

// Profile menu → Open-source licences: the notices of every open-source component Tolzar ships
// (Tolzar::OpenSourceNotices). Every signed-in member of the workspace can read it.
const { t } = useI18n();
const accountId = useMapGetter('getCurrentAccountId');

const data = ref(null);
const loading = ref(true);
const failed = ref(false);
const query = ref('');

const view = computed(() => licencesView(data.value));
const shown = computed(() =>
  Object.fromEntries(
    GROUPS.map(g => [g, filterItems(view.value.groups[g], query.value)])
  )
);

async function load() {
  loading.value = true;
  failed.value = false;
  try {
    data.value = await getLicences(accountId.value);
  } catch (e) {
    failed.value = true;
  } finally {
    loading.value = false;
  }
}

onMounted(load);
</script>

<template>
  <div class="overflow-auto flex-1 bg-n-background">
    <div class="mx-auto max-w-[1000px] px-5 pb-16 pt-6 md:px-7">
      <h1 class="m-0 text-xl font-semibold text-n-slate-12">
        {{ t('TOLZAR_LICENCES.TITLE') }}
      </h1>
      <p class="mt-1 mb-5 text-sm text-n-slate-11">
        {{ t('TOLZAR_LICENCES.INTRO') }}
      </p>

      <p v-if="loading" class="text-sm text-n-slate-10">
        {{ t('TOLZAR_UI.LOADING') }}
      </p>
      <div v-else-if="failed" class="text-sm text-n-slate-11">
        {{ t('TOLZAR_LICENCES.FAILED') }}
        <button
          type="button"
          class="text-xs font-semibold text-n-brand underline"
          @click="load"
        >
          {{ t('TOLZAR_UI.RETRY') }}
        </button>
      </div>

      <template v-else>
        <section class="mb-6">
          <h2 class="m-0 mb-2 text-base font-semibold text-n-slate-12">
            {{ t('TOLZAR_LICENCES.FOUNDATION') }}
          </h2>
          <p class="m-0 mb-2 text-sm text-n-slate-11">
            {{ itemLabel(view.foundation) }}
          </p>
          <pre
            class="p-3 m-0 max-h-64 overflow-auto text-xs whitespace-pre-wrap rounded-lg border border-solid border-n-weak bg-n-solid-1 text-n-slate-11"
            >{{ view.foundation.text }}</pre
          >
        </section>

        <section v-if="view.sourceOffer.length" class="mb-6">
          <h2 class="m-0 mb-2 text-base font-semibold text-n-slate-12">
            {{ t('TOLZAR_LICENCES.SOURCE_OFFER') }}
          </h2>
          <p class="m-0 mb-2 text-sm text-n-slate-11">
            {{ t('TOLZAR_LICENCES.SOURCE_OFFER_HINT') }}
          </p>
          <ul class="m-0 ps-5 text-sm text-n-slate-12">
            <li
              v-for="i in view.sourceOffer"
              :key="`so-${i.name}-${i.version}`"
            >
              {{ itemLabel(i) }}
              <a
                v-if="safeUrl(i.homepage)"
                :href="safeUrl(i.homepage)"
                target="_blank"
                rel="noopener noreferrer"
                class="text-n-brand underline"
                >{{ t('TOLZAR_LICENCES.SOURCE') }}</a
              >
            </li>
          </ul>
        </section>

        <input
          v-model="query"
          type="search"
          class="mb-4 w-full max-w-sm px-3 py-1.5 text-sm rounded-lg border border-solid border-n-weak bg-n-solid-1 text-n-slate-12"
          :placeholder="t('TOLZAR_LICENCES.SEARCH')"
          :aria-label="t('TOLZAR_LICENCES.SEARCH')"
        />

        <section v-for="g in GROUPS" :key="g" class="mb-6">
          <h2 class="m-0 text-base font-semibold text-n-slate-12">
            {{ t(`TOLZAR_LICENCES.GROUP.${g}`, { n: view.groups[g].length }) }}
          </h2>
          <p class="mt-1 mb-2 text-xs text-n-slate-10">
            {{ summaryLine(view.groups[g]) || t('TOLZAR_LICENCES.NONE') }}
          </p>
          <details
            v-for="i in shown[g]"
            :key="`${g}-${i.name}-${i.version}`"
            class="py-1 border-b border-solid border-n-weak"
          >
            <summary class="text-sm cursor-pointer text-n-slate-12">
              {{ itemLabel(i) }}
              <span
                v-if="i.role === 'rollback'"
                class="px-1.5 ms-1 text-[10px] rounded-full bg-n-slate-3 text-n-slate-11"
              >
                {{ t('TOLZAR_LICENCES.ROLLBACK') }}
              </span>
            </summary>
            <div class="py-2 text-xs text-n-slate-11">
              <p v-if="i.author" class="m-0 mb-1">{{ i.author }}</p>
              <a
                v-if="safeUrl(i.homepage)"
                :href="safeUrl(i.homepage)"
                target="_blank"
                rel="noopener noreferrer"
                class="text-n-brand underline break-all"
                >{{ i.homepage }}</a
              >
              <pre
                v-if="i.text"
                class="p-3 mt-2 mb-0 max-h-64 overflow-auto whitespace-pre-wrap rounded-lg bg-n-solid-1"
                >{{ i.text }}</pre
              >
              <p v-else class="m-0 mt-1">
                {{ t('TOLZAR_LICENCES.NO_FILE') }}
              </p>
            </div>
          </details>
        </section>
      </template>
    </div>
  </div>
</template>
