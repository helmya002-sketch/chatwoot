<script setup>
import { computed, watch, onMounted, ref } from 'vue';
import {
  useMapGetter,
  useFunctionGetter,
  useStore,
} from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

import AccordionItem from 'dashboard/components/Accordion/AccordionItem.vue';
import TolzarSidebarPanel from 'dashboard/components-next/Tolzar/SidebarPanel.vue';
import ContactConversations from './ContactConversations.vue';
import ConversationAction from './ConversationAction.vue';
import ConversationParticipant from './ConversationParticipant.vue';
import ContactInfo from './contact/ContactInfo.vue';
import ContactNotes from './contact/ContactNotes.vue';
import ConversationInfo from './ConversationInfo.vue';
import CustomAttributes from './customAttributes/CustomAttributes.vue';
import SharedFiles from './SharedFiles.vue';
import Draggable from 'vuedraggable';
import MacrosList from './Macros/List.vue';
import ShopifyOrdersList from 'dashboard/components/widgets/conversation/ShopifyOrdersList.vue';
import SidebarActionsHeader from 'dashboard/components-next/SidebarActionsHeader.vue';
import LinearIssuesList from 'dashboard/components/widgets/conversation/linear/IssuesList.vue';
import LinearSetupCTA from 'dashboard/components/widgets/conversation/linear/LinearSetupCTA.vue';
import StripeCustomer from 'dashboard/components/widgets/conversation/StripeCustomer.vue';
// Tolzar #13: surface Chatwoot's existing contact-merge as one obvious action.
import ContactMergeModal from 'dashboard/modules/contact/ContactMergeModal.vue';

const props = defineProps({
  conversationId: {
    type: [Number, String],
    required: true,
  },
  inboxId: {
    type: Number,
    default: undefined,
  },
});

const {
  updateUISettings,
  isContactSidebarItemOpen,
  conversationSidebarItemsOrder,
  toggleSidebarUIState,
  isOnExpandedLayout,
} = useUISettings();

const dragging = ref(false);
const conversationSidebarItems = ref([]);

const shopifyIntegration = useFunctionGetter(
  'integrations/getIntegration',
  'shopify'
);

const isShopifyFeatureEnabled = computed(
  () => shopifyIntegration.value.enabled
);

const { isCloudFeatureEnabled } = useAccount();

const isLinearFeatureEnabled = computed(() =>
  isCloudFeatureEnabled(FEATURE_FLAGS.LINEAR)
);

const linearIntegration = useFunctionGetter(
  'integrations/getIntegration',
  'linear'
);

const isLinearClientIdConfigured = computed(() => {
  return !!linearIntegration.value?.id;
});

const isLinearConnected = computed(
  () => linearIntegration.value?.enabled || false
);

const store = useStore();
const stripeIntegration = useFunctionGetter(
  'integrations/getIntegration',
  'stripe'
);
const currentChat = useMapGetter('getSelectedChat');
const conversationId = computed(() => props.conversationId);
const conversationMetadataGetter = useMapGetter(
  'conversationMetadata/getConversationMetadata'
);
const currentConversationMetaData = computed(() =>
  conversationMetadataGetter.value(conversationId.value)
);
const conversationAdditionalAttributes = computed(
  () => currentConversationMetaData.value.additional_attributes || {}
);

const channelType = computed(() => currentChat.value.meta?.channel);

const contactGetter = useMapGetter('contacts/getContact');
const contactId = computed(() => currentChat.value.meta?.sender?.id);
const contact = computed(() => contactGetter.value(contactId.value));
const contactAdditionalAttributes = computed(
  () => contact.value.additional_attributes || {}
);

const appliedContactFilter = useMapGetter('getAppliedContactFilter');

const isListScopedToContact = computed(
  () =>
    !isOnExpandedLayout.value &&
    appliedContactFilter.value?.id === contactId.value
);

const getContactDetails = () => {
  if (contactId.value) {
    store.dispatch('contacts/show', { id: contactId.value });
  }
};

watch(contactId, (newContactId, prevContactId) => {
  if (newContactId && newContactId !== prevContactId) {
    getContactDetails();
  }
});

const onDragEnd = () => {
  dragging.value = false;
  updateUISettings({
    conversation_sidebar_items_order: conversationSidebarItems.value,
  });
};

const closeContactPanel = () => {
  updateUISettings({
    is_contact_sidebar_open: false,
    is_copilot_panel_open: false,
  });
};

onMounted(() => {
  conversationSidebarItems.value = conversationSidebarItemsOrder.value;
  getContactDetails();
  store.dispatch('attributes/get', 0);
  store.dispatch('integrations/get');
});

// Tolzar #3: group the sidebar sections under a vertical icon rail so the contact
// pane reads as tabs (Overview / Files / Actions) instead of one long scroll.
const activeTab = ref('overview');
const SECTION_TAB = {
  conversation_info: 'overview',
  contact_attributes: 'overview',
  contact_notes: 'overview',
  shared_files: 'files',
  conversation_actions: 'actions',
  conversation_participants: 'actions',
  previous_conversation: 'actions',
  macros: 'actions',
  linear_issues: 'actions',
  shopify_orders: 'actions',
  stripe_customer: 'actions',
};
const tabOf = name => SECTION_TAB[name] || 'actions';
const TZ_TABS = [
  { key: 'overview', label: 'Overview' },
  { key: 'files', label: 'Files' },
  { key: 'actions', label: 'Actions' },
];
</script>

<template>
  <div class="w-full flex flex-col h-full min-h-0">
    <SidebarActionsHeader
      :title="$t('CONVERSATION.SIDEBAR.CONTACT')"
      @close="closeContactPanel"
    />
    <div class="flex flex-1 min-h-0">
      <div class="flex-1 min-w-0 overflow-y-auto">
    <ContactInfo :contact="contact" :channel-type="channelType" />
    <div v-show="activeTab === 'overview'" class="px-2 pt-3">
      <TolzarSidebarPanel :contact="contact" />
    </div>
    <div class="px-2 pb-8 list-group">
      <Draggable
        :list="conversationSidebarItems"
        animation="200"
        ghost-class="ghost"
        handle=".drag-handle"
        item-key="name"
        class="flex flex-col gap-3"
        @start="dragging = true"
        @end="onDragEnd"
      >
        <template #item="{ element }">
          <div v-show="tabOf(element.name) === activeTab">
          <div
            v-if="element.name === 'conversation_actions'"
            class="conversation--actions"
          >
            <AccordionItem
              :title="$t('CONVERSATION_SIDEBAR.ACCORDION.CONVERSATION_ACTIONS')"
              :is-open="isContactSidebarItemOpen('is_conv_actions_open')"
              @toggle="
                value => toggleSidebarUIState('is_conv_actions_open', value)
              "
            >
              <ConversationAction
                :conversation-id="conversationId"
                :inbox-id="inboxId"
              />
            </AccordionItem>
          </div>
          <div
            v-else-if="element.name === 'conversation_participants'"
            class="conversation--actions"
          >
            <AccordionItem
              :title="$t('CONVERSATION_PARTICIPANTS.SIDEBAR_TITLE')"
              :is-open="isContactSidebarItemOpen('is_conv_participants_open')"
              @toggle="
                value =>
                  toggleSidebarUIState('is_conv_participants_open', value)
              "
            >
              <ConversationParticipant
                :conversation-id="conversationId"
                :inbox-id="inboxId"
              />
            </AccordionItem>
          </div>
          <div v-else-if="element.name === 'conversation_info'">
            <AccordionItem
              :title="$t('CONVERSATION_SIDEBAR.ACCORDION.CONVERSATION_INFO')"
              :is-open="isContactSidebarItemOpen('is_conv_details_open')"
              compact
              @toggle="
                value => toggleSidebarUIState('is_conv_details_open', value)
              "
            >
              <ConversationInfo
                :conversation-attributes="conversationAdditionalAttributes"
                :contact-attributes="contactAdditionalAttributes"
              />
            </AccordionItem>
          </div>
          <div v-else-if="element.name === 'contact_attributes'">
            <AccordionItem
              :title="$t('CONVERSATION_SIDEBAR.ACCORDION.CONTACT_ATTRIBUTES')"
              :is-open="isContactSidebarItemOpen('is_contact_attributes_open')"
              compact
              @toggle="
                value =>
                  toggleSidebarUIState('is_contact_attributes_open', value)
              "
            >
              <CustomAttributes
                attribute-type="contact_attribute"
                attribute-from="conversation_contact_panel"
                :contact-id="contact.id"
              />
            </AccordionItem>
          </div>
          <div
            v-else-if="
              element.name === 'previous_conversation' && !isListScopedToContact
            "
          >
            <AccordionItem
              v-if="contact.id"
              :title="
                $t('CONVERSATION_SIDEBAR.ACCORDION.PREVIOUS_CONVERSATION')
              "
              :is-open="isContactSidebarItemOpen('is_previous_conv_open')"
              compact
              @toggle="
                value => toggleSidebarUIState('is_previous_conv_open', value)
              "
            >
              <ContactConversations
                :contact-id="contact.id"
                :conversation-id="conversationId"
              />
            </AccordionItem>
          </div>
          <woot-feature-toggle
            v-else-if="element.name === 'macros'"
            feature-key="macros"
          >
            <AccordionItem
              :title="$t('CONVERSATION_SIDEBAR.ACCORDION.MACROS')"
              :is-open="isContactSidebarItemOpen('is_macro_open')"
              compact
              @toggle="value => toggleSidebarUIState('is_macro_open', value)"
            >
              <MacrosList :conversation-id="conversationId" />
            </AccordionItem>
          </woot-feature-toggle>
          <div
            v-else-if="
              element.name === 'linear_issues' &&
              isLinearFeatureEnabled &&
              isLinearClientIdConfigured
            "
          >
            <AccordionItem
              :title="$t('CONVERSATION_SIDEBAR.ACCORDION.LINEAR_ISSUES')"
              :is-open="isContactSidebarItemOpen('is_linear_issues_open')"
              compact
              @toggle="
                value => toggleSidebarUIState('is_linear_issues_open', value)
              "
            >
              <LinearSetupCTA v-if="!isLinearConnected" />
              <LinearIssuesList v-else :conversation-id="conversationId" />
            </AccordionItem>
          </div>
          <div
            v-else-if="
              element.name === 'shopify_orders' && isShopifyFeatureEnabled
            "
          >
            <AccordionItem
              :title="$t('CONVERSATION_SIDEBAR.ACCORDION.SHOPIFY_ORDERS')"
              :is-open="isContactSidebarItemOpen('is_shopify_orders_open')"
              compact
              @toggle="
                value => toggleSidebarUIState('is_shopify_orders_open', value)
              "
            >
              <ShopifyOrdersList :contact-id="contactId" />
            </AccordionItem>
          </div>
          <div
            v-else-if="
              element.name === 'stripe_customer' &&
              isCloudFeatureEnabled(FEATURE_FLAGS.STRIPE) &&
              stripeIntegration.enabled
            "
          >
            <AccordionItem
              :title="$t('STRIPE_INTEGRATION.TITLE')"
              :is-open="isContactSidebarItemOpen('is_stripe_customer_open')"
              compact
              @toggle="
                value => toggleSidebarUIState('is_stripe_customer_open', value)
              "
            >
              <StripeCustomer
                v-if="isContactSidebarItemOpen('is_stripe_customer_open')"
                :conversation-id="conversationId"
                :contact-email="contact.email"
              />
            </AccordionItem>
          </div>
          <div v-else-if="element.name === 'contact_notes'">
            <AccordionItem
              :title="$t('CONVERSATION_SIDEBAR.ACCORDION.CONTACT_NOTES')"
              :is-open="isContactSidebarItemOpen('is_contact_notes_open')"
              compact
              @toggle="
                value => toggleSidebarUIState('is_contact_notes_open', value)
              "
            >
              <ContactNotes :contact-id="contactId" />
            </AccordionItem>
          </div>
          <div v-else-if="element.name === 'shared_files'">
            <AccordionItem
              :title="$t('CONVERSATION_SIDEBAR.ACCORDION.SHARED_FILES')"
              :is-open="isContactSidebarItemOpen('is_shared_files_open')"
              compact
              @toggle="
                value => toggleSidebarUIState('is_shared_files_open', value)
              "
            >
              <SharedFiles />
            </AccordionItem>
          </div>
          </div>
        </template>
      </Draggable>
      <!-- Tolzar #13: one-click contact merge (opens the stock merge picker) -->
      <div
        v-show="activeTab === 'actions'"
        v-if="contact && contact.id"
        class="pt-1 pb-2"
      >
        <ContactMergeModal :primary-contact="contact">
          <template #trigger>
            <button type="button" class="tz-merge-btn">
              <svg
                class="size-4"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                stroke-width="1.7"
              >
                <path d="M7 4v5a5 5 0 0 0 5 5 5 5 0 0 0 5-5V4" />
                <line x1="12" y1="14" x2="12" y2="20" />
                <polyline points="9 17 12 20 15 17" />
              </svg>
              <span>{{ $t('MERGE_CONTACTS.TITLE') || 'Merge contact' }}</span>
            </button>
          </template>
        </ContactMergeModal>
      </div>
    </div>
      </div>
      <!-- Tolzar #3: vertical icon rail switching the contact-pane tabs -->
      <nav class="tz-rail">
        <button
          v-for="tab in TZ_TABS"
          :key="tab.key"
          v-tooltip.left="tab.label"
          type="button"
          class="tz-rail-btn"
          :class="{ 'tz-rail-on': activeTab === tab.key }"
          @click="activeTab = tab.key"
        >
          <svg
            v-if="tab.key === 'overview'"
            class="tz-rail-ic"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            stroke-width="1.7"
          >
            <circle cx="12" cy="8" r="3.4" />
            <path d="M5.5 20c0-3.3 2.9-5.8 6.5-5.8s6.5 2.5 6.5 5.8" />
          </svg>
          <svg
            v-else-if="tab.key === 'files'"
            class="tz-rail-ic"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            stroke-width="1.7"
          >
            <path
              d="M7 3h7l4 4v13a1 1 0 0 1-1 1H7a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1z"
            />
            <path d="M14 3v4h4" />
          </svg>
          <svg
            v-else
            class="tz-rail-ic"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            stroke-width="1.7"
          >
            <line x1="4" y1="8" x2="20" y2="8" />
            <circle cx="10" cy="8" r="2.2" fill="currentColor" stroke="none" />
            <line x1="4" y1="16" x2="20" y2="16" />
            <circle cx="15" cy="16" r="2.2" fill="currentColor" stroke="none" />
          </svg>
          <span class="tz-rail-lbl">{{ tab.label }}</span>
        </button>
      </nav>
    </div>
  </div>
</template>

<style lang="scss" scoped>
:deep(.contact--profile) {
  @apply pb-3 border-b border-solid border-n-weak;
}

/* Tolzar #3: vertical icon rail on the contact pane's edge */
.tz-rail {
  flex: 0 0 44px;
  display: flex;
  flex-direction: column;
  align-items: stretch;
  gap: 2px;
  padding: 8px 4px;
  border-inline-start: 1px solid rgb(var(--slate-4));
  background: rgb(var(--surface-1));
}
.tz-rail-btn {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 2px;
  padding: 7px 0 6px;
  border-radius: 8px;
  color: rgb(var(--slate-10));
  transition:
    background 0.12s ease,
    color 0.12s ease;
}
.tz-rail-btn:hover {
  background: rgb(var(--slate-3));
  color: rgb(var(--slate-12));
}
.tz-rail-on {
  background: rgb(var(--blue-3));
  color: rgb(var(--blue-11));
}
.tz-rail-ic {
  width: 19px;
  height: 19px;
}
.tz-rail-lbl {
  font-size: 9px;
  font-weight: 600;
  line-height: 1;
  letter-spacing: 0.01em;
}

/* Tolzar #13: merge-contact action button */
.tz-merge-btn {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 8px;
  width: 100%;
  padding: 8px 12px;
  border-radius: 8px;
  font-size: 13px;
  font-weight: 500;
  color: rgb(var(--slate-11));
  border: 1px solid rgb(var(--slate-5));
  background: rgb(var(--surface-1));
  transition:
    background 0.12s ease,
    color 0.12s ease,
    border-color 0.12s ease;
}
.tz-merge-btn:hover {
  color: rgb(var(--slate-12));
  border-color: rgb(var(--slate-7));
  background: rgb(var(--slate-3));
}
</style>
