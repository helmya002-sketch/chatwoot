<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { requestPushPermissions } from 'dashboard/helper/pushHelper.js';
import { shouldOfferPush } from './tolzarPwa';

// Installed app only (round 4, c64): iPhone asks for notification permission only after a tap, so the app offers
// one clear button once. "Not now" hides it on this phone (localStorage, a per-device convenience).
const { t } = useI18n();
const KEY = 'tolzar_push_offer_dismissed';
const readDismissed = () => {
  try {
    return window.localStorage.getItem(KEY) === '1';
  } catch (e) {
    return false;
  }
};
const visible = ref(shouldOfferPush(window, { dismissed: readDismissed() }));

function later() {
  visible.value = false;
  try {
    window.localStorage.setItem(KEY, '1');
  } catch (e) {
    // Blocked storage: the offer simply comes back next time.
  }
}

function enable() {
  requestPushPermissions({ onSuccess: () => {} });
  visible.value = false;
}
</script>

<template>
  <div
    v-if="visible"
    class="tz-push-offer fixed z-50 inset-x-3 flex items-center gap-3 p-3 rounded-2xl bg-n-solid-1 border border-solid border-n-weak shadow-lg"
    role="dialog"
    :aria-label="t('TOLZAR_PWA.PUSH.TITLE')"
    @keydown.esc="later"
  >
    <span class="flex-1 text-sm text-n-slate-12">
      {{ t('TOLZAR_PWA.PUSH.TEXT') }}
    </span>
    <button
      type="button"
      class="min-h-[44px] px-3 rounded-lg text-sm text-n-slate-11"
      @click="later"
    >
      {{ t('TOLZAR_PWA.PUSH.LATER') }}
    </button>
    <button
      type="button"
      class="min-h-[44px] px-4 rounded-lg bg-n-brand text-white text-sm font-medium"
      @click="enable"
    >
      {{ t('TOLZAR_PWA.PUSH.ENABLE') }}
    </button>
  </div>
</template>

<style scoped>
.tz-push-offer {
  bottom: max(12px, env(safe-area-inset-bottom));
}
</style>
