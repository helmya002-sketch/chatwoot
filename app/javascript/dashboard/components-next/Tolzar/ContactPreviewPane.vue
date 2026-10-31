<script setup>
// Tolzar Contacts pass 1: preview pane next to the table. Stage (with a writer that re-reads the
// contact first, so a stale copy never overwrites someone else's edit), the brain's summary and
// lead-score reason, contact details (the workspace pack's fields included), tags and recent conversations. "Full profile" opens
// Chatwoot's own contact page for everything else.
import { useI18n } from 'vue-i18n';
import { computed, ref, watch } from 'vue';
import { useRouter, useRoute } from 'vue-router';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useLocale } from 'shared/composables/useLocale';
import { dynamicTime } from 'shared/helpers/timeHelper';
import { conversationUrl, frontendURL } from 'dashboard/helper/URLHelper';
import ContactAPI from 'dashboard/api/contacts';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import ChannelIcon from 'dashboard/components-next/icon/ChannelIcon.vue';
import ContactLabels from 'dashboard/components-next/Contacts/ContactLabels/ContactLabels.vue';
import {
  defaultStage,
  lostStage,
  contactStage,
  dealValue,
  money,
  STAGES,
  leadScore,
  scoreTone,
  stageClass,
  stageOf,
} from './tolzarStages';
import { contactChannel, conversationChannel } from './tolzarChannel';
import { EMPTY_PACK, fetchPack, packRows } from './tolzarPack';
import { tolzarBrand } from './TolzarBranding.vue';

const props = defineProps({
  contactId: { type: Number, required: true },
});
const emit = defineEmits(['close']);

const store = useStore();
const { t, locale } = useI18n();
const { resolvedLocale } = useLocale();
const router = useRouter();
const route = useRoute();
const accountId = useMapGetter('getCurrentAccountId');
const product = computed(() => tolzarBrand.productName);

const raw = computed(
  () => store.getters['contacts/getContact'](props.contactId) || {}
);
const attrs = computed(() => raw.value.custom_attributes || {});
const inbox = computed(() => contactChannel(raw.value));
const stage = computed(() => contactStage(attrs.value) || defaultStage());
const stageIndex = computed(() => STAGES.findIndex(s => s.key === stage.value));
const isLost = computed(() => stage.value === lostStage());
const funnel = computed(() => STAGES.filter(s => s.key !== lostStage()));
const score = computed(() => leadScore(attrs.value));
const summary = computed(() => (attrs.value.tolzar_summary || '').trim());
const scoreLabel = computed(() => attrs.value.tolzar_lead_label || '');
const scoreHint = computed(() => (attrs.value.tolzar_lead_hint || '').trim());
const hintText = computed(() => `: ${scoreHint.value}`);
const scoreText = computed(() =>
  [score.value, scoreLabel.value]
    .filter(v => v !== null && v !== '')
    .join(' · ')
);
const subline = computed(() =>
  [
    inbox.value?.name,
    raw.value.last_activity_at ? dynamicTime(raw.value.last_activity_at) : '',
  ]
    .filter(Boolean)
    .join(' · ')
);

// Generic core rows plus the workspace pack's own fields (labels from the brain, through
// GET /tolzar/pack -> tolzarPack.fetchPack). Industry-specific attributes such as a party or
// group size are NOT listed here: a pack that defines them (fields[].key) shows them through
// packRows, with the pack's own label; a workspace without that pack never sees the row.
const pack = ref(EMPTY_PACK);
watch(
  accountId,
  async id => {
    pack.value = await fetchPack(id);
  },
  { immediate: true }
);
const packed = computed(() =>
  packRows(pack.value, attrs.value, locale.value, t)
);

const details = computed(() =>
  [
    ...packed.value.places,
    [
      t('TOLZAR_CONTACTS.PANE.PLACE'),
      attrs.value.location || raw.value.additional_attributes?.city,
    ],
    ...packed.value.others,
    [
      t('TOLZAR_CONTACTS.PANE.DEAL_VALUE'),
      dealValue(attrs.value)
        ? money(dealValue(attrs.value), { locale: resolvedLocale.value })
        : '',
    ],
    [t('TOLZAR_CONTACTS.PANE.LANGUAGE'), attrs.value.preferred_language],
    [t('TOLZAR_CONTACTS.PANE.PHONE'), raw.value.phone_number],
    [t('TOLZAR_CONTACTS.PANE.EMAIL'), raw.value.email],
  ].filter(([, v]) => v !== undefined && v !== null && v !== '')
);

const conversations = computed(() =>
  store.getters['contactConversations/getContactConversation'](
    props.contactId
  ).slice(0, 5)
);

watch(
  () => props.contactId,
  id => {
    if (!id) return;
    store.dispatch('contactConversations/get', id);
    store.dispatch('contactLabels/get', id);
  },
  { immediate: true }
);

const stageOpen = ref(false);
const saving = ref(false);
const setStage = async key => {
  stageOpen.value = false;
  if (key === stage.value || saving.value) return;
  saving.value = true;
  try {
    // Re-read before write: custom_attributes is replaced as a whole on update.
    const { data } = await ContactAPI.show(props.contactId);
    const fresh = data?.payload?.custom_attributes || {};
    await store.dispatch('contacts/update', {
      id: props.contactId,
      customAttributes: { ...fresh, lifecycle_stage: key },
    });
    useAlert(
      t('TOLZAR_CONTACTS.STAGES.SET_SUCCESS', { stage: stageOf(key).label })
    );
  } catch (e) {
    useAlert(t('TOLZAR_CONTACTS.STAGES.SET_FAILED'));
  } finally {
    saving.value = false;
  }
};

const openProfile = () => {
  const routeTypes = {
    contacts_dashboard_segments_index: ['contacts_edit_segment', 'segmentId'],
    contacts_dashboard_labels_index: ['contacts_edit_label', 'label'],
  };
  const [name, key] = routeTypes[route.name] || ['contacts_edit'];
  router.push({
    name,
    params: {
      contactId: props.contactId,
      ...(key && { [key]: route.params[key] }),
    },
    query: route.query,
  });
};

const openConversation = conv => {
  router.push(
    frontendURL(conversationUrl({ accountId: accountId.value, id: conv.id }))
  );
};
</script>

<template>
  <aside
    class="flex flex-col w-80 flex-shrink-0 h-full overflow-y-auto border-s border-n-weak bg-n-background"
    @keydown.esc="stageOpen = false"
  >
    <div class="p-4 border-b border-n-weak">
      <div class="flex items-start gap-3">
        <div class="relative flex-shrink-0">
          <Avatar :name="raw.name" :src="raw.thumbnail" :size="44" />
          <span
            v-if="inbox && inbox.channel_type"
            class="absolute -bottom-1 -end-1 flex items-center justify-center size-[17px] rounded-full bg-n-background ring-2 ring-n-background"
          >
            <ChannelIcon :inbox="inbox" class="size-[14px]" />
          </span>
        </div>
        <div class="flex-1 min-w-0">
          <div class="text-base font-semibold truncate text-n-slate-12">
            {{ raw.name || '—' }}
          </div>
          <div class="text-xs truncate text-n-slate-11">
            {{ subline }}
          </div>
        </div>
        <Button
          icon="i-lucide-x"
          variant="ghost"
          color="slate"
          size="xs"
          :aria-label="t('TOLZAR_UI.CLOSE')"
          @click="emit('close')"
        />
      </div>
      <div class="flex items-center gap-2 mt-3">
        <Button
          :label="t('TOLZAR_CONTACTS.PANE.FULL_PROFILE')"
          size="sm"
          @click="openProfile"
        />
        <div class="relative">
          <Button
            :label="
              saving
                ? t('TOLZAR_CONTACTS.STAGES.SAVING')
                : t('TOLZAR_CONTACTS.STAGES.SET')
            "
            icon="i-lucide-chevron-down"
            trailing-icon
            variant="outline"
            color="slate"
            size="sm"
            :disabled="saving"
            aria-haspopup="menu"
            :aria-expanded="stageOpen ? 'true' : 'false'"
            @click="stageOpen = !stageOpen"
          />
          <div
            v-if="stageOpen"
            class="fixed inset-0 z-40"
            @click="stageOpen = false"
          />
          <div
            v-if="stageOpen"
            role="menu"
            class="absolute z-50 p-1 mt-1 border shadow-lg min-w-44 rounded-xl border-n-weak bg-n-alpha-3 backdrop-blur-[100px]"
          >
            <button
              v-for="s in STAGES"
              :key="s.key"
              type="button"
              role="menuitemradio"
              :aria-checked="s.key === stage ? 'true' : 'false'"
              class="flex items-center w-full gap-2 px-2 py-1.5 text-sm rounded-lg text-start text-n-slate-12 hover:bg-n-alpha-2"
              :class="{ 'font-semibold': s.key === stage }"
              @click="setStage(s.key)"
            >
              <span class="p-0.5 rounded-full" :class="stageClass(s.key)">
                <span class="block rounded-full size-1.5 bg-current" />
              </span>
              {{ s.label }}
            </button>
          </div>
        </div>
      </div>
    </div>

    <section class="px-4 py-3 border-b border-n-weak">
      <h3
        class="mb-2 text-xs font-medium tracking-wide uppercase text-n-slate-10"
      >
        {{ t('TOLZAR_CONTACTS.PANE.STAGE') }}
      </h3>
      <div v-if="!isLost" class="flex gap-1">
        <span
          v-for="(s, i) in funnel"
          :key="s.key"
          class="flex-1 py-1 text-xs text-center rounded-md"
          :class="
            i < stageIndex
              ? 'bg-n-blue-3 text-n-blue-11'
              : i === stageIndex
                ? 'bg-n-brand text-white font-semibold'
                : 'bg-n-slate-3 text-n-slate-10'
          "
        >
          {{ s.label }}
        </span>
      </div>
      <span
        v-else
        class="inline-flex items-center gap-1.5 px-2 py-0.5 text-xs font-semibold rounded-full"
        :class="stageClass(stage)"
      >
        {{ t('TOLZAR_CONTACTS.PANE.LOST') }}
      </span>
    </section>

    <section class="px-4 py-3 border-b border-n-weak">
      <h3
        class="mb-2 text-xs font-medium tracking-wide uppercase text-n-slate-10"
      >
        {{ t('TOLZAR_CONTACTS.PANE.SUMMARY', { product }) }}
      </h3>
      <p
        v-if="summary"
        class="px-3 py-2 mb-0 text-sm rounded-lg bg-n-blue-2 text-n-slate-12"
      >
        {{ summary }}
      </p>
      <p v-else class="mb-0 text-sm text-n-slate-10">
        {{ t('TOLZAR_CONTACTS.PANE.NO_SUMMARY', { product }) }}
      </p>
      <p v-if="score !== null" class="mt-2 mb-0 text-xs text-n-slate-11">
        {{ t('TOLZAR_CONTACTS.PANE.LEAD_SCORE') }}
        <b :class="scoreTone(score)">{{ scoreText }}</b>
        <span v-if="scoreHint">{{ hintText }}</span>
      </p>
    </section>

    <section v-if="details.length" class="px-4 py-3 border-b border-n-weak">
      <h3
        class="mb-2 text-xs font-medium tracking-wide uppercase text-n-slate-10"
      >
        {{ t('TOLZAR_CONTACTS.PANE.DETAILS') }}
      </h3>
      <dl class="grid grid-cols-[7rem_1fr] gap-x-3 gap-y-1.5 text-sm m-0">
        <template v-for="[k, v] in details" :key="k">
          <dt class="text-n-slate-10">{{ k }}</dt>
          <dd class="m-0 truncate text-n-slate-12" :title="String(v)">
            {{ v }}
          </dd>
        </template>
      </dl>
    </section>

    <section class="px-4 py-3 border-b border-n-weak">
      <h3
        class="mb-2 text-xs font-medium tracking-wide uppercase text-n-slate-10"
      >
        {{ t('TOLZAR_CONTACTS.PANE.TAGS') }}
      </h3>
      <ContactLabels :contact-id="contactId" />
    </section>

    <section class="px-4 py-3">
      <h3
        class="mb-2 text-xs font-medium tracking-wide uppercase text-n-slate-10"
      >
        {{ t('TOLZAR_CONTACTS.PANE.RECENT') }}
      </h3>
      <p v-if="!conversations.length" class="mb-0 text-sm text-n-slate-10">
        {{ t('TOLZAR_CONTACTS.PANE.NONE_YET') }}
      </p>
      <button
        v-for="conv in conversations"
        :key="conv.id"
        type="button"
        class="flex items-center w-full gap-2 px-2 py-1.5 -mx-2 text-sm rounded-lg text-start hover:bg-n-slate-2"
        @click="openConversation(conv)"
      >
        <ChannelIcon
          v-if="conversationChannel(conv)"
          :inbox="conversationChannel(conv)"
          class="flex-shrink-0 size-4 text-n-slate-11"
        />
        <span class="flex-1 truncate text-n-slate-12">#{{ conv.id }}</span>
        <span class="text-xs capitalize text-n-slate-10">{{
          conv.status
        }}</span>
        <span class="text-xs text-n-slate-10 whitespace-nowrap">
          {{ dynamicTime(conv.last_activity_at || conv.timestamp) }}
        </span>
      </button>
    </section>
  </aside>
</template>
