<script setup>
// Tolzar fair use (Tolzar::FairUse, only with TOLZAR_FAIR_USE): the Owner's in-app notice at 80% and 100% of
// the plan's monthly AI replies. Soft limit, so the banner only informs; it can be dismissed for the month
// and comes back when the level rises (near → over) or a new month starts.
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useMapGetter } from 'dashboard/composables/store';
import Banner from 'dashboard/components-next/banner/Banner.vue';

const { t } = useI18n();
const router = useRouter();
const accountId = useMapGetter('getCurrentAccountId');
const getAccount = useMapGetter('accounts/getAccount');
const currentRole = useMapGetter('getCurrentRole');

const state = computed(() => {
  const account = getAccount.value(accountId.value) || {};
  const s = account.tolzar_fair_use;
  return s && ['near', 'over'].includes(s.level) ? s : null;
});
const dismissKey = computed(() =>
  state.value
    ? `tolzar-fair-use:${accountId.value}:${state.value.month}:${state.value.level}`
    : ''
);
const readDismissed = key => {
  try {
    return !!key && window.localStorage.getItem(key) === '1';
  } catch (e) {
    return false;
  }
};
const dismissedNow = ref('');
const show = computed(
  () =>
    currentRole.value === 'administrator' &&
    !!state.value &&
    dismissedNow.value !== dismissKey.value &&
    !readDismissed(dismissKey.value)
);
const message = computed(() =>
  state.value
    ? t(`TOLZAR_FAIR_USE.${state.value.level === 'over' ? 'OVER' : 'NEAR'}`, {
        used: state.value.used,
        allowance: state.value.allowance,
      })
    : ''
);

const seeUsage = () =>
  router.push({
    name: 'tolzar_settings',
    params: { accountId: accountId.value },
  });
const dismiss = () => {
  dismissedNow.value = dismissKey.value;
  try {
    window.localStorage.setItem(dismissKey.value, '1');
  } catch (e) {
    // private window: dismissed for this page only
  }
};
</script>

<!-- eslint-disable-next-line vue/no-root-v-if -->
<template>
  <Banner
    v-if="show"
    :color="state.level === 'over' ? 'ruby' : 'amber'"
    role="status"
    class="!rounded-none !justify-center flex-wrap shrink-0"
    :action-label="t('TOLZAR_FAIR_USE.SEE_USAGE')"
    @action="seeUsage"
  >
    {{ message }}
    <button type="button" class="ms-3 underline text-xs" @click="dismiss">
      {{ t('TOLZAR_FAIR_USE.DISMISS') }}
    </button>
  </Banner>
</template>
