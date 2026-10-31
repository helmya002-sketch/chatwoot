<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import ShadowBadge from '../ShadowBadge.vue';
import { BTN, INPUT, LABEL } from './tzClasses';

// Settings hub → Channels → WhatsApp (listen-only): the workspace owner connects the business's own
// in-house Meta app to a number another provider already runs (Tolzar::ListenOnly). Tolzar only
// subscribes that app to the WhatsApp account and receives; it never sends, never registers the
// number and never changes its webhooks. The token and app secret are write-only.
const { t } = useI18n();
const accountId = useMapGetter('getCurrentAccountId');

const form = ref({
  waba_id: '',
  phone_number_id: '',
  access_token: '',
  app_secret: '',
  inbox_name: '',
});
const busy = ref(false);
const result = ref(null);
const error = ref('');
const ready = computed(() =>
  ['waba_id', 'phone_number_id', 'access_token', 'app_secret'].every(k =>
    form.value[k].trim()
  )
);

async function connect() {
  busy.value = true;
  error.value = '';
  result.value = null;
  try {
    const { data } = await window.axios.post(
      `/api/v1/accounts/${accountId.value}/tolzar/whatsapp/listen_only`,
      form.value
    );
    result.value = data;
    form.value.access_token = '';
    form.value.app_secret = '';
  } catch (e) {
    const status = e?.response?.status;
    error.value =
      status === 403
        ? t('TOLZAR_SETTINGS.WA_LISTEN.OWNER_ONLY')
        : e?.response?.data?.error || t('TOLZAR_SETTINGS.WA_LISTEN.FAILED');
  } finally {
    busy.value = false;
  }
}
</script>

<template>
  <div class="max-w-[620px]">
    <ShadowBadge state="shadow" :hint="t('TOLZAR_SETTINGS.WA_LISTEN.BADGE')" />
    <p class="mt-1 mb-0 text-xs text-n-slate-10">
      {{ t('TOLZAR_SETTINGS_UI.SHADOW_DETAIL.whatsapp_listen') }}
    </p>
    <p class="mt-2 mb-0 text-[13px] text-n-slate-11">
      {{ t('TOLZAR_SETTINGS.WA_LISTEN.WHAT') }}
    </p>
    <ul class="mt-2 mb-0 ps-4 text-[13px] text-n-slate-11 list-disc">
      <li>{{ t('TOLZAR_SETTINGS.WA_LISTEN.NEVER_SENDS') }}</li>
      <li>{{ t('TOLZAR_SETTINGS.WA_LISTEN.NUMBER_UNTOUCHED') }}</li>
      <li>{{ t('TOLZAR_SETTINGS.WA_LISTEN.SECRETS') }}</li>
    </ul>
    <label :class="LABEL">{{ t('TOLZAR_SETTINGS.WA_LISTEN.WABA_ID') }}</label>
    <input v-model="form.waba_id" :class="INPUT" autocomplete="off" />
    <label :class="LABEL">{{
      t('TOLZAR_SETTINGS.WA_LISTEN.PHONE_NUMBER_ID')
    }}</label>
    <input v-model="form.phone_number_id" :class="INPUT" autocomplete="off" />
    <label :class="LABEL">{{ t('TOLZAR_SETTINGS.WA_LISTEN.TOKEN') }}</label>
    <input
      v-model="form.access_token"
      :class="INPUT"
      type="password"
      autocomplete="new-password"
    />
    <label :class="LABEL">{{
      t('TOLZAR_SETTINGS.WA_LISTEN.APP_SECRET')
    }}</label>
    <input
      v-model="form.app_secret"
      :class="INPUT"
      type="password"
      autocomplete="new-password"
    />
    <label :class="LABEL">{{
      t('TOLZAR_SETTINGS.WA_LISTEN.INBOX_NAME')
    }}</label>
    <input v-model="form.inbox_name" :class="INPUT" autocomplete="off" />
    <button type="button" :class="BTN" :disabled="!ready || busy" @click="connect">
      {{ busy ? t('TOLZAR_UI.SAVING') : t('TOLZAR_SETTINGS.WA_LISTEN.CONNECT') }}
    </button>
    <p v-if="error" class="mt-3 mb-0 text-[13px] text-n-ruby-11">{{ error }}</p>
    <div
      v-if="result"
      class="mt-4 p-3 rounded-lg border border-solid border-n-weak text-[13px] text-n-slate-12"
    >
      <p class="m-0 font-semibold">
        {{
          result.ok
            ? t('TOLZAR_SETTINGS.WA_LISTEN.CONNECTED')
            : t('TOLZAR_SETTINGS.WA_LISTEN.SUBSCRIBE_FAILED')
        }}
      </p>
      <p v-if="result.subscription_error" class="mt-1 mb-0 text-n-ruby-11">
        {{ result.subscription_error }}
      </p>
      <p class="mt-2 mb-1 text-n-slate-11">
        {{ t('TOLZAR_SETTINGS.WA_LISTEN.IN_META') }}
      </p>
      <div :class="LABEL">
        {{ t('TOLZAR_SETTINGS.WA_LISTEN.CALLBACK_URL') }}
      </div>
      <code class="block break-all">{{ result.callback_url }}</code>
      <div :class="LABEL">
        {{ t('TOLZAR_SETTINGS.WA_LISTEN.VERIFY_TOKEN') }}
      </div>
      <code class="block break-all">{{ result.verify_token }}</code>
    </div>
  </div>
</template>
