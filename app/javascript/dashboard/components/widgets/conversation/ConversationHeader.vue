<script setup>
import { computed, ref } from 'vue';
import { useRoute } from 'vue-router';
import { useStore } from 'vuex';
import { useElementSize } from '@vueuse/core';
import BackButton from '../BackButton.vue';
import InboxName from '../InboxName.vue';
import MoreActions from './MoreActions.vue';
import Avatar from 'next/avatar/Avatar.vue';
import SLACardLabel from './components/SLACardLabel.vue';
import ConversationCallButton from './ConversationCallButton.vue';
import wootConstants from 'dashboard/constants/globals';
import { conversationListPageURL } from 'dashboard/helper/URLHelper';
import { snoozedReopenTime } from 'dashboard/helper/snoozeHelpers';
import { useInbox } from 'dashboard/composables/useInbox';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import {
  contactStage,
  defaultStage,
  stageOf,
  stageClass,
  STAGES as SHARED_STAGES,
} from 'dashboard/components-next/Tolzar/tolzarStages';
import LeadScoreRing from 'dashboard/components-next/Tolzar/LeadScoreRing.vue';
import { tolzarBrand } from 'dashboard/components-next/Tolzar/TolzarBranding.vue';

const props = defineProps({
  chat: {
    type: Object,
    default: () => ({}),
  },
  showBackButton: {
    type: Boolean,
    default: false,
  },
});

const { t } = useI18n();
const store = useStore();
const route = useRoute();
const conversationHeader = ref(null);
const { width } = useElementSize(conversationHeader);
const { isAWebWidgetInbox, isAnEmailChannel } = useInbox();

const currentChat = computed(() => store.getters.getSelectedChat);
const accountId = computed(() => store.getters.getCurrentAccountId);

const chatMetadata = computed(() => props.chat.meta);

const backButtonUrl = computed(() => {
  const {
    params: { inbox_id: inboxId, label, teamId, id: customViewId },
    name,
  } = route;

  const conversationTypeMap = {
    conversation_through_mentions: 'mention',
    conversation_through_participating: 'participating',
    conversation_through_unattended: 'unattended',
  };
  return conversationListPageURL({
    accountId: accountId.value,
    inboxId,
    label,
    teamId,
    conversationType: conversationTypeMap[name],
    customViewId,
  });
});

const isHMACVerified = computed(() => {
  if (!isAWebWidgetInbox.value) {
    return true;
  }
  return chatMetadata.value.hmac_verified;
});

const mailSubject = computed(() => {
  if (!isAnEmailChannel.value) return '';
  return props.chat.additional_attributes?.mail_subject;
});

const currentContact = computed(() =>
  store.getters['contacts/getContact'](props.chat.meta.sender.id)
);

const isSnoozed = computed(
  () => currentChat.value.status === wootConstants.STATUS_TYPE.SNOOZED
);

const snoozedDisplayText = computed(() => {
  const { snoozed_until: snoozedUntil } = currentChat.value;
  if (snoozedUntil) {
    return `${t('CONVERSATION.HEADER.SNOOZED_UNTIL')} ${snoozedReopenTime(snoozedUntil)}`;
  }
  return t('CONVERSATION.HEADER.SNOOZED_UNTIL_NEXT_REPLY');
});

const inbox = computed(() => {
  const { inbox_id: inboxId } = props.chat;
  return store.getters['inboxes/getInbox'](inboxId);
});

const hasMultipleInboxes = computed(
  () => store.getters['inboxes/getInboxes'].length > 1
);

const hasSlaPolicyId = computed(
  () => props.chat?.applied_sla?.id && !currentContact.value?.blocked
);

const copyConversationId = async () => {
  try {
    await copyTextToClipboard(String(props.chat.id));
    useAlert(t('CONVERSATION.HEADER.COPY_ID_SUCCESS'));
  } catch (error) {
    // error
  }
};

// Tolzar: lead score surfaced in the conversation header so it is noticeable
// (the brain writes these custom attributes on the contact).
const tolzarLeadScore = computed(() => {
  const n = Number(currentContact.value?.custom_attributes?.tolzar_lead_score);
  return Number.isFinite(n) && n > 0 ? Math.min(100, Math.round(n)) : null;
});
const tolzarLeadLabel = computed(
  () =>
    currentContact.value?.custom_attributes?.tolzar_lead_label ||
    t('TOLZAR_INBOX.LEAD_SCORE.LABEL')
);
const tolzarLeadHint = computed(
  () => currentContact.value?.custom_attributes?.tolzar_lead_hint || ''
);
const tolzarLeadTooltip = computed(
  () =>
    tolzarLeadHint.value ||
    t('TOLZAR_INBOX.LEAD_SCORE.TOOLTIP', { product: tolzarBrand.productName })
);

// Tolzar #5: set the lifecycle Stage from the conversation header. Writes
// the contact's `lifecycle_stage` custom attribute — the same field the list-card
// pill reads, so the card updates instantly. Existing attributes are preserved.
// The workspace's own stage list (Settings > Pipeline), in order; colours from the
// shared tone map (theme tokens), the same as every other stage chip.
const STAGES = computed(() => SHARED_STAGES.map(s => s.key));
const stageOpen = ref(false);
const currentStage = computed(
  () => contactStage(currentContact.value?.custom_attributes) || defaultStage()
);
const stageLabel = computed(() => stageOf(currentStage.value).label);
const setStage = stage => {
  stageOpen.value = false;
  const cc = currentContact.value;
  if (!cc?.id || stage === currentStage.value) return;
  const merged = { ...(cc.custom_attributes || {}), lifecycle_stage: stage };
  store
    .dispatch('contacts/update', { id: cc.id, customAttributes: merged })
    .then(() => useAlert(t('TOLZAR_CONTACTS.STAGES.SET_SUCCESS', { stage: stageOf(stage).label })))
    .catch(() => useAlert(t('TOLZAR_CONTACTS.STAGES.SET_FAILED')));
};
</script>

<template>
  <div
    ref="conversationHeader"
    class="flex flex-col gap-3 items-center justify-between flex-1 w-full min-w-0 xl:flex-row px-3 pt-3 pb-2 h-24 xl:h-12"
  >
    <div
      class="flex items-center justify-start w-full xl:w-auto max-w-full min-w-0 xl:flex-1"
    >
      <BackButton
        v-if="showBackButton"
        :back-url="backButtonUrl"
        class="me-2"
      />
      <Avatar
        :name="currentContact.name"
        :src="currentContact.thumbnail"
        :size="32"
        :status="currentContact.availability_status"
        hide-offline-status
      />
      <div class="flex flex-col items-start min-w-0 ms-2 overflow-hidden">
        <div class="flex flex-row items-center max-w-full gap-1 p-0 m-0">
          <span
            class="text-sm font-medium truncate leading-tight text-n-slate-12"
          >
            {{ currentContact.name }}
          </span>
          <fluent-icon
            v-if="!isHMACVerified"
            v-tooltip="$t('CONVERSATION.UNVERIFIED_SESSION')"
            size="14"
            class="text-n-amber-10 my-0 mx-0 min-w-[14px] flex-shrink-0"
            icon="warning"
          />
        </div>

        <div
          class="flex items-center max-w-full gap-1 overflow-hidden text-xs conversation--header--actions text-n-slate-11 text-ellipsis whitespace-nowrap"
        >
          <button
            type="button"
            class="truncate shrink-0 text-label-small text-n-slate-11 hover:text-n-slate-12 !p-0 cucursor-pointer"
            @click="copyConversationId"
          >
            {{ `#${chat.id}` }}
          </button>
          <span v-if="hasMultipleInboxes">•</span>
          <InboxName v-if="hasMultipleInboxes" :inbox="inbox" class="!mx-0" />
          <span v-if="mailSubject">•</span>
          <span
            v-if="mailSubject"
            v-tooltip="mailSubject"
            class="flex-1 min-w-16 truncate text-label-small text-n-slate-11"
          >
            {{ mailSubject }}
          </span>
          <span v-if="isSnoozed">•</span>
          <span
            v-if="isSnoozed"
            class="min-w-0 truncate font-medium text-n-amber-10 shrink-0"
          >
            {{ snoozedDisplayText }}
          </span>
        </div>
      </div>
    </div>
    <div
      class="flex flex-row items-center justify-start xl:justify-end flex-shrink-0 gap-2 w-full xl:w-auto header-actions-wrap"
    >
      <!-- Tolzar #5: per-conversation Stage control (writes contact lifecycle_stage) -->
      <div v-if="currentContact && currentContact.id" class="tz-stage">
        <button
          v-tooltip="t('TOLZAR_INBOX.HEADER.SET_STAGE')"
          type="button"
          class="tz-stage-btn"
          aria-haspopup="menu"
          :aria-expanded="stageOpen ? 'true' : 'false'"
          @click="stageOpen = !stageOpen"
          @keydown.esc="stageOpen = false"
        >
          <span class="tz-stage-dot" :class="stageClass(currentStage)">
            <span class="tz-stage-dot-in" />
          </span>
          <span class="tz-stage-lbl">{{ stageLabel }}</span>
          <svg
            class="tz-stage-caret"
            viewBox="0 0 16 16"
            fill="none"
            stroke="currentColor"
            stroke-width="1.6"
          >
            <path d="M4 6l4 4 4-4" />
          </svg>
        </button>
        <div
          v-if="stageOpen"
          class="tz-stage-backdrop"
          @click="stageOpen = false"
        />
        <div
          v-if="stageOpen"
          class="tz-stage-menu"
          role="menu"
          @keydown.esc="stageOpen = false"
        >
          <button
            v-for="s in STAGES"
            :key="s"
            type="button"
            role="menuitemradio"
            :aria-checked="s === currentStage ? 'true' : 'false'"
            class="tz-stage-opt"
            :class="{ 'tz-stage-opt-on': s === currentStage }"
            @click="setStage(s)"
          >
            <span class="tz-stage-dot" :class="stageClass(s)">
              <span class="tz-stage-dot-in" />
            </span>
            <span>{{ stageOf(s).label }}</span>
          </button>
        </div>
      </div>
      <div
        v-if="tolzarLeadScore"
        v-tooltip="tolzarLeadTooltip"
        class="tolzar-leadscore hidden md:flex"
      >
        <LeadScoreRing :score="tolzarLeadScore" size="sm" />
        <span class="tz-txt">
          <b>{{ tolzarLeadLabel }}</b>
          <i v-if="tolzarLeadHint">{{ tolzarLeadHint }}</i>
        </span>
      </div>
      <SLACardLabel
        v-if="hasSlaPolicyId"
        :chat="chat"
        show-extended-info
        :parent-width="width"
        class="hidden md:flex"
      />
      <ConversationCallButton :inbox="inbox" :chat="currentChat" />
      <MoreActions :conversation-id="currentChat.id" />
    </div>
  </div>
</template>

<style scoped>
/* Tolzar lead-score badge — premium, theme-aware via Radix tokens */
.tolzar-leadscore {
  display: flex;
  align-items: center;
  gap: 9px;
  background: rgb(var(--blue-9) / 0.1);
  border: 1px solid rgb(var(--blue-9) / 0.2);
  border-radius: 11px;
  padding: 3px 12px 3px 5px;
}
.tolzar-leadscore .tz-txt {
  display: flex;
  flex-direction: column;
  line-height: 1.15;
}
.tolzar-leadscore .tz-txt b {
  font-size: 12px;
  font-weight: 700;
  color: rgb(var(--slate-12));
}
.tolzar-leadscore .tz-txt i {
  font-size: 10px;
  font-style: normal;
  color: rgb(var(--slate-11));
}

/* Tolzar #5: Stage control in the conversation header */
.tz-stage {
  position: relative;
  flex-shrink: 0;
}
.tz-stage-btn {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  height: 28px;
  padding: 0 8px 0 9px;
  border-radius: 8px;
  border: 1px solid rgb(var(--slate-5));
  background: rgb(var(--surface-1));
  font-size: 12px;
  font-weight: 600;
  color: rgb(var(--slate-12));
  white-space: nowrap;
  transition: border-color 0.12s ease;
}
.tz-stage-btn:hover {
  border-color: rgb(var(--slate-7));
}
/* The stage dot: the tone's text colour (stageClass) through currentColor, so the dot
   matches the chips in the list and the Contacts table in both themes. */
.tz-stage-dot {
  display: inline-grid;
  place-items: center;
  width: 12px;
  height: 12px;
  border-radius: 50%;
  flex: 0 0 12px;
}
.tz-stage-dot-in {
  width: 6px;
  height: 6px;
  border-radius: 50%;
  background: currentColor;
}
.tz-stage-caret {
  width: 13px;
  height: 13px;
  color: rgb(var(--slate-10));
}
.tz-stage-backdrop {
  position: fixed;
  inset: 0;
  z-index: 40;
}
.tz-stage-menu {
  position: absolute;
  top: calc(100% + 6px);
  inset-inline-end: 0;
  z-index: 41;
  min-width: 180px;
  padding: 4px;
  border-radius: 10px;
  border: 1px solid rgb(var(--slate-4));
  background: rgb(var(--surface-1));
  box-shadow: 0 8px 24px rgb(0 0 0 / 0.12);
}
.tz-stage-opt {
  display: flex;
  align-items: center;
  gap: 8px;
  width: 100%;
  padding: 7px 9px;
  border-radius: 7px;
  font-size: 12.5px;
  font-weight: 500;
  color: rgb(var(--slate-12));
  text-align: start;
}
.tz-stage-opt:hover {
  background: rgb(var(--slate-3));
}
.tz-stage-opt-on {
  background: rgb(var(--blue-3));
  color: rgb(var(--blue-11));
  font-weight: 600;
}
</style>
