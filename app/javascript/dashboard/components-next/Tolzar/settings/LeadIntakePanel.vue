<script setup>
import { ref, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import ShadowBadge from '../ShadowBadge.vue';
import { BTN_GHOST, INPUT, LABEL } from './tzClasses';

// Settings hub → Channels → Lead forms (Tolzar::LeadIntake): the owner copies each API inbox's lead link into
// TikTok Instant Forms' CRM webhook, an ad connector or a website form. The link carries a secret, so the
// endpoint answers the owner only. Leads only arrive: nothing is sent to the person from here.
const { t } = useI18n();
const accountId = useMapGetter('getCurrentAccountId');

const loading = ref(true);
const error = ref('');
const enabled = ref(false);
const inboxes = ref([]);
const copied = ref(null);

async function load() {
  loading.value = true;
  error.value = '';
  try {
    const { data } = await window.axios.get(
      `/api/v1/accounts/${accountId.value}/tolzar/lead_intake`
    );
    enabled.value = data.enabled === true;
    inboxes.value = data.inboxes || [];
  } catch (e) {
    error.value =
      e?.response?.status === 403
        ? t('TOLZAR_SETTINGS.R1.OWNER_ONLY')
        : t('TOLZAR_SETTINGS.WA_LISTEN.FAILED');
  } finally {
    loading.value = false;
  }
}

async function copy(inbox) {
  try {
    await navigator.clipboard.writeText(inbox.url);
    copied.value = inbox.id;
  } catch {
    copied.value = null;
  }
}

onMounted(load);
</script>

<template>
  <div class="max-w-[680px]">
    <ShadowBadge
      state="shadow"
      :hint="t('TOLZAR_SETTINGS_UI.SHADOW_DETAIL.lead_intake')"
    />
    <p class="mt-1 mb-0 text-xs text-n-slate-10">
      {{ t('TOLZAR_SETTINGS_UI.SHADOW_DETAIL.lead_intake') }}
    </p>
    <p v-if="loading" class="mt-3 text-[13px] text-n-slate-11">
      {{ t('TOLZAR_SETTINGS_UI.LEAD_INTAKE.LOADING') }}
    </p>
    <p v-else-if="error" class="mt-3 text-[13px] text-n-ruby-11" role="alert">
      {{ error }}
    </p>
    <template v-else>
      <p v-if="!enabled" class="mt-3 text-[13px] text-n-slate-11">
        {{ t('TOLZAR_SETTINGS_UI.LEAD_INTAKE.OFF') }}
      </p>
      <p v-else-if="!inboxes.length" class="mt-3 text-[13px] text-n-slate-11">
        {{ t('TOLZAR_SETTINGS_UI.LEAD_INTAKE.NO_INBOX') }}
      </p>
      <template v-else>
        <p class="mt-3 mb-0 text-[13px] text-n-amber-11">
          {{ t('TOLZAR_SETTINGS_UI.LEAD_INTAKE.SECRET') }}
        </p>
        <div v-for="inbox in inboxes" :key="inbox.id" class="mt-3">
          <label :class="LABEL" :for="`tz-lead-url-${inbox.id}`">
            {{ t('TOLZAR_SETTINGS_UI.LEAD_INTAKE.LINK', { name: inbox.name }) }}
          </label>
          <div class="flex gap-2 items-center">
            <input
              :id="`tz-lead-url-${inbox.id}`"
              :class="INPUT"
              :value="inbox.url"
              readonly
              class="font-mono"
              @focus="$event.target.select()"
            />
            <button
              type="button"
              :class="BTN_GHOST"
              class="!mt-0 shrink-0"
              @click="copy(inbox)"
            >
              {{
                copied === inbox.id
                  ? t('TOLZAR_SETTINGS_UI.LEAD_INTAKE.COPIED')
                  : t('TOLZAR_SETTINGS_UI.LEAD_INTAKE.COPY')
              }}
            </button>
          </div>
        </div>
      </template>
      <h3 class="mt-5 mb-1 text-sm font-semibold text-n-slate-12">
        {{ t('TOLZAR_SETTINGS_UI.LEAD_INTAKE.FIELDS_TITLE') }}
      </h3>
      <p class="m-0 text-[13px] text-n-slate-11">
        {{ t('TOLZAR_SETTINGS_UI.LEAD_INTAKE.FIELDS') }}
      </p>
      <p class="mt-2 mb-0 text-[13px] text-n-slate-11">
        {{ t('TOLZAR_SETTINGS_UI.LEAD_INTAKE.RESULT') }}
      </p>
    </template>
  </div>
</template>
