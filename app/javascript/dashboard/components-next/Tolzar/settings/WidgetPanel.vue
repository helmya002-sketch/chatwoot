<script setup>
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { BTN, INPUT, LABEL, TONE_OK, TONE_WARN, TONE_BAD } from './tzClasses';
import { whiteContrast, contrastLevel } from './tolzarWidgetPanel';

// Settings hub → Growth → Website widget (Tolzar own widget): a live preview of the brand colour and welcome
// text with a contrast check, the "continue on" hand-off links (owner), and per-page opens and chats started.
const { t } = useI18n();
const accountId = useMapGetter('getCurrentAccountId');
const inboxes = useMapGetter('inboxes/getInboxes');
const webInboxes = computed(() =>
  (inboxes.value || []).filter(i => i.channel_type === 'Channel::WebWidget')
);
const inboxId = ref(null);
const inbox = computed(() =>
  webInboxes.value.find(i => i.id === inboxId.value)
);
const color = computed(() => inbox.value?.widget_color || '#3E63DD');
const handoff = ref({ whatsapp: '', instagram: '', telegram: '' });
const stats = ref([]);
const ownWidget = ref(false);
const notice = ref('');
const base = computed(() => `/api/v1/accounts/${accountId.value}/tolzar`);

async function load() {
  if (!inboxId.value) return;
  notice.value = '';
  try {
    const [h, s] = await Promise.all([
      window.axios.get(`${base.value}/widget_handoff`, {
        params: { inbox_id: inboxId.value },
      }),
      window.axios.get(`${base.value}/widget_stats`, {
        params: { inbox_id: inboxId.value },
      }),
    ]);
    handoff.value = {
      whatsapp: '',
      instagram: '',
      telegram: '',
      ...(h.data.values || {}),
    };
    stats.value = s.data.pages || [];
    ownWidget.value = s.data.own_widget === true;
  } catch {
    notice.value = t('TOLZAR_SETTINGS_UI.DOCS.FAILED');
  }
}

async function saveHandoff() {
  notice.value = '';
  try {
    await window.axios.post(`${base.value}/widget_handoff`, {
      inbox_id: inboxId.value,
      ...handoff.value,
    });
    notice.value = t('TOLZAR_SETTINGS_UI.DOCS.SAVED');
  } catch (e) {
    notice.value =
      e?.response?.status === 403
        ? t('TOLZAR_SETTINGS.R1.OWNER_ONLY')
        : (e?.response?.data?.errors || []).join(' ') ||
          t('TOLZAR_SETTINGS_UI.DOCS.FAILED');
  }
}

const sampleIn = computed(() => t('TOLZAR_SETTINGS_UI.WIDGET.SAMPLE_IN'));
const sampleOut = computed(() => t('TOLZAR_SETTINGS_UI.WIDGET.SAMPLE_OUT'));
const contrast = computed(() => whiteContrast(color.value));
const level = computed(() => contrastLevel(color.value));
const levelTone = computed(
  () => ({ aa: TONE_OK, large: TONE_WARN, fail: TONE_BAD })[level.value]
);

watch(
  webInboxes,
  list => {
    if (!inboxId.value && list.length) inboxId.value = list[0].id;
  },
  { immediate: true }
);
watch(inboxId, load, { immediate: true });
</script>

<template>
  <div class="max-w-[820px]">
    <p class="mt-0 text-[13px] text-n-slate-11">
      {{ t('TOLZAR_SETTINGS_UI.WIDGET.WHAT') }}
    </p>
    <p v-if="!webInboxes.length" class="text-[13px] text-n-slate-11">
      {{ t('TOLZAR_SETTINGS_UI.WIDGET.NO_INBOX') }}
    </p>
    <template v-else>
      <label :class="LABEL" for="tz-wp-inbox">{{
        t('TOLZAR_SETTINGS_UI.WIDGET.INBOX')
      }}</label>
      <select
        id="tz-wp-inbox"
        v-model.number="inboxId"
        :class="INPUT"
        class="!w-72"
      >
        <option v-for="i in webInboxes" :key="i.id" :value="i.id">
          {{ i.name }}
        </option>
      </select>
      <p v-if="notice" class="text-[13px] text-n-slate-12" role="status">
        {{ notice }}
      </p>
      <p v-if="!ownWidget" class="text-xs text-n-amber-11">
        {{ t('TOLZAR_SETTINGS_UI.WIDGET.OLD_WIDGET') }}
      </p>

      <div class="grid gap-5 mt-4 md:grid-cols-[300px_minmax(0,1fr)]">
        <section :aria-label="t('TOLZAR_SETTINGS_UI.WIDGET.PREVIEW')">
          <div
            class="overflow-hidden rounded-2xl border border-solid border-n-weak shadow-sm bg-n-solid-1"
          >
            <div class="p-4 text-white" :style="{ background: color }">
              <div class="font-semibold">
                {{ inbox?.welcome_title || inbox?.name }}
              </div>
              <div class="text-xs opacity-90">
                {{
                  inbox?.welcome_tagline ||
                  t('TOLZAR_SETTINGS_UI.WIDGET.TAGLINE')
                }}
              </div>
            </div>
            <div class="flex flex-col gap-2 p-3 text-[13px]">
              <span
                class="self-start px-3 py-2 rounded-xl bg-n-slate-3 text-n-slate-12"
              >
                {{ sampleIn }}
              </span>
              <span
                class="self-end px-3 py-2 rounded-xl text-white"
                :style="{ background: color }"
              >
                {{ sampleOut }}
              </span>
            </div>
          </div>
          <p class="mt-2 mb-0 text-xs">
            <span class="px-1.5 rounded" :class="levelTone">{{
              t(`TOLZAR_SETTINGS_UI.WIDGET.CONTRAST_${level}`, {
                ratio: contrast,
              })
            }}</span>
          </p>
        </section>

        <section>
          <h3 class="m-0 text-sm font-semibold text-n-slate-12">
            {{ t('TOLZAR_SETTINGS_UI.WIDGET.HANDOFF') }}
          </h3>
          <p class="m-0 text-xs text-n-slate-10">
            {{ t('TOLZAR_SETTINGS_UI.WIDGET.HANDOFF_HINT') }}
          </p>
          <label :class="LABEL" for="tz-wp-wa">{{
            t('TOLZAR_SETTINGS_UI.WIDGET.CH_WA')
          }}</label>
          <input
            id="tz-wp-wa"
            v-model="handoff.whatsapp"
            :class="INPUT"
            :placeholder="t('TOLZAR_SETTINGS_UI.WIDGET.WA_PH')"
          />
          <label :class="LABEL" for="tz-wp-ig">{{
            t('TOLZAR_SETTINGS_UI.WIDGET.CH_IG')
          }}</label>
          <input
            id="tz-wp-ig"
            v-model="handoff.instagram"
            :class="INPUT"
            :placeholder="t('TOLZAR_SETTINGS_UI.WIDGET.HANDLE_PH')"
          />
          <label :class="LABEL" for="tz-wp-tg">{{
            t('TOLZAR_SETTINGS_UI.WIDGET.CH_TG')
          }}</label>
          <input
            id="tz-wp-tg"
            v-model="handoff.telegram"
            :class="INPUT"
            :placeholder="t('TOLZAR_SETTINGS_UI.WIDGET.HANDLE_PH')"
          />
          <button type="button" :class="BTN" @click="saveHandoff">
            {{ t('TOLZAR_SETTINGS_UI.WIDGET.SAVE_HANDOFF') }}
          </button>
        </section>
      </div>

      <h3 class="mt-6 mb-1 text-sm font-semibold text-n-slate-12">
        {{ t('TOLZAR_SETTINGS_UI.WIDGET.STATS') }}
      </h3>
      <p v-if="!stats.length" class="m-0 text-[13px] text-n-slate-11">
        {{ t('TOLZAR_SETTINGS_UI.WIDGET.STATS_NONE') }}
      </p>
      <table v-else class="w-full text-[13px]">
        <thead class="text-xs text-n-slate-11">
          <tr class="border-b border-n-weak">
            <th class="py-2 pe-3 text-start font-medium">
              {{ t('TOLZAR_SETTINGS_UI.WIDGET.PAGE') }}
            </th>
            <th class="py-2 pe-3 text-end font-medium">
              {{ t('TOLZAR_SETTINGS_UI.WIDGET.OPENS') }}
            </th>
            <th class="py-2 pe-3 text-end font-medium">
              {{ t('TOLZAR_SETTINGS_UI.WIDGET.STARTS') }}
            </th>
            <th class="py-2 text-end font-medium">
              {{ t('TOLZAR_SETTINGS_UI.WIDGET.RATE') }}
            </th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="row in stats"
            :key="row.page"
            class="border-b border-n-weak"
          >
            <td class="py-2 pe-3 font-mono text-xs break-all">
              {{ row.page }}
            </td>
            <td class="py-2 pe-3 text-end tabular-nums">{{ row.open }}</td>
            <td class="py-2 pe-3 text-end tabular-nums">{{ row.start }}</td>
            <td class="py-2 text-end tabular-nums">
              {{ row.rate == null ? '–' : `${row.rate}%` }}
            </td>
          </tr>
        </tbody>
      </table>
    </template>
  </div>
</template>
