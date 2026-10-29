<script setup>
import { h, ref, computed, onMounted, onBeforeUnmount, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { usePolicy } from 'dashboard/composables/usePolicy';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { provideSidebarContext, useSidebarResize } from './provider';
import { useAccount } from 'dashboard/composables/useAccount';
import { useConfig } from 'dashboard/composables/useConfig';
import { useKbd } from 'dashboard/composables/utils/useKbd';
import { useMapGetter } from 'dashboard/composables/store';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useSidebarKeyboardShortcuts } from './useSidebarKeyboardShortcuts';
import { vOnClickOutside } from '@vueuse/components';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { useWindowSize, useEventListener } from '@vueuse/core';

import Button from 'dashboard/components-next/button/Button.vue';
import SidebarGroup from './SidebarGroup.vue';
import SidebarProfileMenu from './SidebarProfileMenu.vue';
import SidebarChangelogCard from './SidebarChangelogCard.vue';
import SidebarChangelogButton from './SidebarChangelogButton.vue';
import ChannelLeaf from './ChannelLeaf.vue';
import ChannelIcon from 'next/icon/ChannelIcon.vue';
import Icon from 'next/icon/Icon.vue';
import EmojiIcon from 'next/emoji-icon-picker/EmojiIcon.vue';
import SidebarAccountSwitcher from './SidebarAccountSwitcher.vue';
import Logo from 'next/icon/Logo.vue';
import NotificationsBell from 'dashboard/components-next/Tolzar/NotificationsBell.vue';
import ComposeConversation from 'dashboard/components-next/NewConversation/ComposeConversation.vue';
import {
  SIDEBAR_SORT_SECTIONS,
  getSidebarSortOptions,
  resolveSidebarSort,
  sortSidebarItems,
} from 'dashboard/helper/sidebarSort';

const props = defineProps({
  isMobileSidebarOpen: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits([
  'closeKeyShortcutModal',
  'openKeyShortcutModal',
  'showCreateAccountModal',
  'closeMobileSidebar',
]);

const { accountScopedRoute, isOnChatwootCloud } = useAccount();
const { isEnterprise } = useConfig();
const store = useStore();

// Calls run on the enterprise-only API (cloud runs enterprise); hide the entry
// on community so it doesn't lead to a dashboard/CTA the backend can't serve.
const isCallsAvailable = computed(
  () => isOnChatwootCloud.value || isEnterprise
);
const searchShortcut = useKbd([`$mod`, 'k']);
const { t } = useI18n();

const isACustomBrandedInstance = useMapGetter(
  'globalConfig/isACustomBrandedInstance'
);
const isRTL = useMapGetter('accounts/isRTL');

const { width: windowWidth } = useWindowSize();
const isMobile = computed(() => windowWidth.value < 768);

const accountId = useMapGetter('getCurrentAccountId');
const currentUserId = useMapGetter('getCurrentUserID');
const isFeatureEnabledonAccount = useMapGetter(
  'accounts/isFeatureEnabledonAccount'
);

const isMonitorsAvailable = computed(
  () =>
    (isOnChatwootCloud.value || isEnterprise) &&
    [FEATURE_FLAGS.REPORTS, FEATURE_FLAGS.CONVERSATION_MONITORS].every(flag =>
      isFeatureEnabledonAccount.value(accountId.value, flag)
    )
);

const hasAdvancedAssignment = computed(() => {
  return isFeatureEnabledonAccount.value(
    accountId.value,
    FEATURE_FLAGS.ADVANCED_ASSIGNMENT
  );
});

const hasConversationUnreadCounts = computed(() => {
  return isFeatureEnabledonAccount.value(
    accountId.value,
    FEATURE_FLAGS.CONVERSATION_UNREAD_COUNTS
  );
});

const hasFilteredUnreadCounts = computed(() => {
  return (
    hasConversationUnreadCounts.value &&
    isFeatureEnabledonAccount.value(
      accountId.value,
      FEATURE_FLAGS.UNREAD_COUNT_FOR_FILTERS
    )
  );
});

const hasDataImport = computed(() => {
  return isFeatureEnabledonAccount.value(
    accountId.value,
    FEATURE_FLAGS.DATA_IMPORT
  );
});

const fetchConversationUnreadCounts = ([currentAccountId, isEnabled]) => {
  if (!currentAccountId) return;

  if (!isEnabled) {
    store.dispatch('conversationUnreadCounts/clear');
    return;
  }

  store.dispatch('conversationUnreadCounts/get');
};

const fetchSidebarSortPreferences = ([currentAccountId, userId]) => {
  if (!currentAccountId || !userId) return;
  store.dispatch('sidebarSortPreferences/initialize');
};

const toggleShortcutModalFn = show => {
  if (show) {
    emit('openKeyShortcutModal');
  } else {
    emit('closeKeyShortcutModal');
  }
};

useSidebarKeyboardShortcuts(toggleShortcutModalFn);

const expandedItem = ref(null);

const setExpandedItem = name => {
  expandedItem.value = expandedItem.value === name ? null : name;
};

const {
  sidebarWidth,
  isCollapsed,
  setSidebarWidth,
  saveWidth,
  snapToCollapsed,
  snapToExpanded,
  COLLAPSED_THRESHOLD,
} = useSidebarResize();

// On mobile, sidebar is always expanded (flyout mode)
const isEffectivelyCollapsed = computed(
  () => !isMobile.value && isCollapsed.value
);

// Tolzar: explicit collapse/expand toggle (respond.io-style) so the feature is
// discoverable instead of hidden behind the drag/double-click resize handle.
const toggleSidebarCollapse = () => {
  if (isCollapsed.value) snapToExpanded();
  else snapToCollapsed();
};

// Resize handle logic
const isResizing = ref(false);
const startX = ref(0);
const startWidth = ref(0);

// Tolzar nav-IA: the sub-sidebar column always renders the active section's tree
// in expanded form, so the shared context is never "collapsed" — the icon rail
// is its own markup below, not a collapsed SidebarGroup.
provideSidebarContext({
  expandedItem,
  setExpandedItem,
  isCollapsed: computed(() => false),
  sidebarWidth,
  isResizing,
});

// Get clientX from mouse or touch event
const getClientX = event =>
  event.touches ? event.touches[0].clientX : event.clientX;

const onResizeStart = event => {
  isResizing.value = true;
  startX.value = getClientX(event);
  startWidth.value = sidebarWidth.value;
  Object.assign(document.body.style, {
    cursor: 'col-resize',
    userSelect: 'none',
  });
  // Prevent default to avoid scrolling on touch
  event.preventDefault();
};

const onResizeMove = event => {
  if (!isResizing.value) return;

  const delta = isRTL.value
    ? startX.value - getClientX(event)
    : getClientX(event) - startX.value;
  setSidebarWidth(startWidth.value + delta);
};

const onResizeEnd = () => {
  if (!isResizing.value) return;

  isResizing.value = false;
  Object.assign(document.body.style, { cursor: '', userSelect: '' });

  // Snap to collapsed state if below threshold
  if (sidebarWidth.value < COLLAPSED_THRESHOLD) {
    snapToCollapsed();
  } else {
    saveWidth();
  }
};

const onResizeHandleDoubleClick = () => {
  if (isCollapsed.value) snapToExpanded();
  else snapToCollapsed();
};

// Support both mouse and touch events
useEventListener(document, 'mousemove', onResizeMove);
useEventListener(document, 'mouseup', onResizeEnd);
useEventListener(document, 'touchmove', onResizeMove, { passive: false });
useEventListener(document, 'touchend', onResizeEnd);

const inboxes = useMapGetter('inboxes/getInboxes');
const labels = useMapGetter('labels/getLabelsOnSidebar');
const allUnreadCount = useMapGetter(
  'conversationUnreadCounts/getAllUnreadCount'
);
const getInboxUnreadCount = useMapGetter(
  'conversationUnreadCounts/getInboxUnreadCount'
);
const getLabelUnreadCount = useMapGetter(
  'conversationUnreadCounts/getLabelUnreadCount'
);
const getTeamUnreadCount = useMapGetter(
  'conversationUnreadCounts/getTeamUnreadCount'
);
const mentionsUnreadCount = useMapGetter(
  'conversationUnreadCounts/getMentionsUnreadCount'
);
const participatingUnreadCount = useMapGetter(
  'conversationUnreadCounts/getParticipatingUnreadCount'
);
const unattendedUnreadCount = useMapGetter(
  'conversationUnreadCounts/getUnattendedUnreadCount'
);
const getFolderUnreadCount = useMapGetter(
  'conversationUnreadCounts/getFolderUnreadCount'
);
const teams = useMapGetter('teams/getMyTeams');
// Tolzar: managers/owners (administrators) see ALL teams in the inbox rail
// (respond.io-style team inbox); agents still see only the teams they belong to.
const allTeams = useMapGetter('teams/getTeams');

// Tolzar: AI Agents tree. The agents are stored by the brain (AI Agents builder, through the
// admin proxy); listed as children under the AI Agents nav, each opening its builder.
const currentRole = useMapGetter('getCurrentRole');
const tzAiAgents = ref([]);
const loadTzAiAgents = async () => {
  if (currentRole.value !== 'administrator' || !accountId.value) {
    tzAiAgents.value = [];
    return;
  }
  try {
    const { data } = await window.axios.get(
      `/api/v1/accounts/${accountId.value}/tolzar/agents`
    );
    tzAiAgents.value = Array.isArray(data?.agents) ? data.agents : [];
  } catch (e) {
    tzAiAgents.value = [];
  }
};
const teamsForSidebar = computed(() =>
  currentRole.value === 'administrator' ? allTeams.value : teams.value
);

// Tolzar: manager "Team Inbox" tree — each team expands to its agents, and a
// click filters the inbox to that agent within that team (respond.io-style).
// Administrators only; agents keep the plain per-team "Teams" group.
const getTeamMembers = useMapGetter('teamMembers/getTeamMembers');
// Tolzar #1: separate Users tree — filter the inbox by a single agent (assignee).
const verifiedAgents = useMapGetter('agents/getVerifiedAgents');
const loadTeamAgents = () => {
  if (currentRole.value !== 'administrator') return;
  (allTeams.value || []).forEach(team =>
    store.dispatch('teamMembers/get', { teamId: team.id })
  );
};

const contactCustomViews = useMapGetter('customViews/getContactCustomViews');
const conversationCustomViews = useMapGetter(
  'customViews/getConversationCustomViews'
);
const getSidebarSectionSort = useMapGetter(
  'sidebarSortPreferences/getSectionSort'
);

onMounted(() => {
  store.dispatch('labels/get');
  store.dispatch('inboxes/get');
  store.dispatch('notifications/unReadCount');
  store.dispatch('teams/get');
  store.dispatch('attributes/get');
  store.dispatch('customViews/get', 'conversation');
  store.dispatch('customViews/get', 'contact');
  store.dispatch('agents/get');
  loadTzAiAgents();
  // The AI Agents builder says when it stored, added or deleted an agent.
  window.addEventListener('tolzar:agents-changed', loadTzAiAgents);
});
onBeforeUnmount(() =>
  window.removeEventListener('tolzar:agents-changed', loadTzAiAgents)
);
watch([accountId, currentRole], loadTzAiAgents);

watch([accountId, hasConversationUnreadCounts], fetchConversationUnreadCounts, {
  immediate: true,
});

watch([accountId, currentUserId], fetchSidebarSortPreferences, {
  immediate: true,
});

// Load each team's agents once the team list is available (manager Team Inbox).
watch(allTeams, loadTeamAgents, { immediate: true });

const hasUnreadCountsForSection = section => {
  if (section === SIDEBAR_SORT_SECTIONS.FOLDERS) {
    return hasFilteredUnreadCounts.value;
  }

  return hasConversationUnreadCounts.value;
};

const getSortOptionsForSection = section =>
  getSidebarSortOptions(section, {
    hasUnreadCounts: hasUnreadCountsForSection(section),
  });

const getSortForSection = section =>
  resolveSidebarSort(section, getSidebarSectionSort.value(section), {
    hasUnreadCounts: hasUnreadCountsForSection(section),
  });

const updateSortPreference = (section, sortBy) => {
  store.dispatch('sidebarSortPreferences/setSectionSort', {
    section,
    sortBy,
  });
};

const buildSortConfig = section => ({
  sortOptions: getSortOptionsForSection(section),
  activeSort: getSortForSection(section),
  onSortChange: sortBy => updateSortPreference(section, sortBy),
});

const sortedFolders = computed(() =>
  sortSidebarItems(conversationCustomViews.value, {
    sortBy: getSortForSection(SIDEBAR_SORT_SECTIONS.FOLDERS),
    labelKey: view => view.name,
    unreadCountKey: view => getFolderUnreadCount.value(view.id),
  })
);

const sortedTeams = computed(() =>
  sortSidebarItems(teamsForSidebar.value, {
    sortBy: getSortForSection(SIDEBAR_SORT_SECTIONS.TEAMS),
    labelKey: team => team.name,
    unreadCountKey: team => getTeamUnreadCount.value(team.id),
  })
);

const sortedInboxes = computed(() =>
  sortSidebarItems(inboxes.value, {
    sortBy: getSortForSection(SIDEBAR_SORT_SECTIONS.CHANNELS),
    labelKey: inbox => inbox.name,
    unreadCountKey: inbox => getInboxUnreadCount.value(inbox.id),
  })
);

const sortedLabels = computed(() =>
  sortSidebarItems(labels.value, {
    sortBy: getSortForSection(SIDEBAR_SORT_SECTIONS.LABELS),
    labelKey: label => label.title,
    unreadCountKey: label => getLabelUnreadCount.value(label.id),
  })
);

const closeMobileSidebar = () => {
  if (!props.isMobileSidebarOpen) return;
  emit('closeMobileSidebar');
};

const newReportRoutes = () => [
  {
    name: 'Reports Agent',
    label: t('SIDEBAR.REPORTS_AGENT'),
    to: accountScopedRoute('agent_reports_index'),
    activeOn: ['agent_reports_show'],
  },
  {
    name: 'Reports Label',
    label: t('SIDEBAR.REPORTS_LABEL'),
    to: accountScopedRoute('label_reports_index'),
  },
  {
    name: 'Reports Inbox',
    label: t('SIDEBAR.REPORTS_INBOX'),
    to: accountScopedRoute('inbox_reports_index'),
    activeOn: ['inbox_reports_show'],
  },
  {
    name: 'Reports Team',
    label: t('SIDEBAR.REPORTS_TEAM'),
    to: accountScopedRoute('team_reports_index'),
    activeOn: ['team_reports_show'],
  },
];

const reportRoutes = computed(() => newReportRoutes());

const menuItems = computed(() => {
  return [
    {
      name: 'Dashboard',
      label: 'Dashboard',
      icon: 'i-lucide-layout-dashboard',
      to: accountScopedRoute('tolzar_dashboard'),
      activeOn: ['tolzar_dashboard'],
    },
    {
      name: 'Pipeline',
      label: 'Pipeline',
      icon: 'i-lucide-columns-3',
      to: accountScopedRoute('tolzar_pipeline'),
      activeOn: ['tolzar_pipeline'],
    },
    {
      name: 'Conversation',
      label: 'Inbox',
      icon: 'i-lucide-inbox',
      children: [
        {
          name: 'All',
          label: t('SIDEBAR.ALL_CONVERSATIONS'),
          icon: 'i-lucide-inbox',
          badgeCount: allUnreadCount.value,
          activeOn: ['inbox_conversation'],
          to: accountScopedRoute('home'),
        },
        {
          name: 'Mentions',
          label: t('SIDEBAR.MENTIONED_CONVERSATIONS'),
          icon: 'i-lucide-at-sign',
          badgeCount: hasFilteredUnreadCounts.value
            ? mentionsUnreadCount.value
            : 0,
          activeOn: ['conversation_through_mentions'],
          to: accountScopedRoute('conversation_mentions'),
        },
        {
          name: 'Participating',
          label: t('SIDEBAR.PARTICIPATING_CONVERSATIONS'),
          icon: 'i-lucide-user-round-check',
          badgeCount: hasFilteredUnreadCounts.value
            ? participatingUnreadCount.value
            : 0,
          activeOn: ['conversation_through_participating'],
          to: accountScopedRoute('conversation_participating'),
        },
        {
          name: 'Unattended',
          activeOn: ['conversation_through_unattended'],
          label: t('SIDEBAR.UNATTENDED_CONVERSATIONS'),
          icon: 'i-lucide-clock-alert',
          badgeCount: hasFilteredUnreadCounts.value
            ? unattendedUnreadCount.value
            : 0,
          to: accountScopedRoute('conversation_unattended'),
        },
        {
          name: 'Folders',
          label: t('SIDEBAR.CUSTOM_VIEWS_FOLDER'),
          icon: 'i-lucide-folder',
          activeOn: ['conversations_through_folders'],
          ...buildSortConfig(SIDEBAR_SORT_SECTIONS.FOLDERS),
          collapsible: true,
          showTreeLine: true,
          children: sortedFolders.value.map(view => ({
            name: `${view.name}-${view.id}`,
            label: view.name,
            badgeCount: hasFilteredUnreadCounts.value
              ? getFolderUnreadCount.value(view.id)
              : 0,
            to: accountScopedRoute('folder_conversations', { id: view.id }),
          })),
        },
        {
          name: 'Teams',
          label: t('SIDEBAR.TEAMS'),
          icon: 'i-lucide-users',
          activeOn: ['conversations_through_team'],
          ...buildSortConfig(SIDEBAR_SORT_SECTIONS.TEAMS),
          collapsible: true,
          showTreeLine: true,
          children: sortedTeams.value.map(team => ({
            name: `${team.name}-${team.id}`,
            label: team.name,
            badgeCount: getTeamUnreadCount.value(team.id),
            icon: team.icon
              ? h(EmojiIcon, {
                  value: team.icon,
                  color: team.icon_color,
                  class: 'size-3.5',
                })
              : undefined,
            to: accountScopedRoute('team_conversations', { teamId: team.id }),
          })),
        },
        // Tolzar #1: Users tree — one leaf per agent, filters the inbox to that
        // assignee (managers/admins only; pairs with the per-team "Teams" tree).
        ...(currentRole.value === 'administrator'
          ? [
              {
                name: 'Users',
                label: 'Users',
                icon: 'i-lucide-user-round',
                collapsible: true,
                showTreeLine: true,
                children: (verifiedAgents.value || []).map(agent => ({
                  name: `tz-user-${agent.id}`,
                  label: agent.name || agent.available_name || agent.email,
                  icon: 'i-lucide-user-round',
                  to: accountScopedRoute(
                    'home',
                    {},
                    {
                      filters: JSON.stringify([
                        {
                          attribute_key: 'assignee_id',
                          filter_operator: 'equal_to',
                          values: { id: agent.id },
                          query_operator: 'and',
                        },
                      ]),
                    }
                  ),
                })),
              },
            ]
          : []),
        {
          name: 'Channels',
          label: t('SIDEBAR.CHANNELS'),
          icon: 'i-lucide-mailbox',
          activeOn: ['conversation_through_inbox'],
          ...buildSortConfig(SIDEBAR_SORT_SECTIONS.CHANNELS),
          collapsible: true,
          showTreeLine: true,
          children: sortedInboxes.value.map(inbox => ({
            name: `${inbox.name}-${inbox.id}`,
            label: inbox.name,
            badgeCount: getInboxUnreadCount.value(inbox.id),
            icon: h(ChannelIcon, { inbox, class: 'size-[16px]' }),
            to: accountScopedRoute('inbox_dashboard', { inbox_id: inbox.id }),
            component: leafProps =>
              h(ChannelLeaf, {
                label: leafProps.label,
                active: leafProps.active,
                inbox,
                badgeCount: leafProps.badgeCount,
              }),
          })),
        },
        {
          name: 'Labels',
          label: t('SIDEBAR.LABELS'),
          icon: 'i-lucide-tag',
          activeOn: ['conversations_through_label'],
          ...buildSortConfig(SIDEBAR_SORT_SECTIONS.LABELS),
          collapsible: true,
          showTreeLine: true,
          children: sortedLabels.value.map(label => ({
            name: `${label.title}-${label.id}`,
            label: label.title,
            badgeCount: getLabelUnreadCount.value(label.id),
            icon: h('span', {
              class: `size-[8px] rounded-sm`,
              style: { backgroundColor: label.color },
            }),
            to: accountScopedRoute('label_conversations', {
              label: label.title,
            }),
          })),
        },
      ],
    },
    // Tolzar #1: the old nested "Team Inbox" (team → agents) is superseded by the
    // flat Teams tree + the new Users tree under the Inbox group above.
    {
      name: 'Contacts',
      label: t('SIDEBAR.CONTACTS'),
      icon: 'i-lucide-contact',
      children: [
        {
          name: 'All Contacts',
          label: t('SIDEBAR.ALL_CONTACTS'),
          to: accountScopedRoute(
            'contacts_dashboard_index',
            {},
            { page: 1, search: undefined }
          ),
          activeOn: ['contacts_dashboard_index', 'contacts_edit'],
        },
        {
          name: 'Active',
          label: t('SIDEBAR.ACTIVE'),
          to: accountScopedRoute('contacts_dashboard_active'),
          activeOn: ['contacts_dashboard_active'],
        },
        {
          name: 'Segments',
          icon: 'i-lucide-group',
          label: t('SIDEBAR.CUSTOM_VIEWS_SEGMENTS'),
          collapsible: true,
          showTreeLine: true,
          children: contactCustomViews.value.map(view => ({
            name: `${view.name}-${view.id}`,
            label: view.name,
            to: accountScopedRoute(
              'contacts_dashboard_segments_index',
              { segmentId: view.id },
              { page: 1 }
            ),
            activeOn: [
              'contacts_dashboard_segments_index',
              'contacts_edit_segment',
            ],
          })),
        },
        {
          name: 'Tagged With',
          icon: 'i-lucide-tag',
          label: t('SIDEBAR.TAGGED_WITH'),
          collapsible: true,
          showTreeLine: true,
          children: labels.value.map(label => ({
            name: `${label.title}-${label.id}`,
            label: label.title,
            icon: h('span', {
              class: `size-[8px] rounded-sm`,
              style: { backgroundColor: label.color },
            }),
            to: accountScopedRoute(
              'contacts_dashboard_labels_index',
              { label: label.title },
              { page: 1, search: undefined }
            ),
            activeOn: [
              'contacts_dashboard_labels_index',
              'contacts_edit_label',
            ],
          })),
        },
      ],
    },
    {
      name: 'AI Agents',
      label: 'AI Agents',
      icon: 'i-lucide-bot',
      to: accountScopedRoute('tolzar_ai_agents'),
      activeOn: ['tolzar_ai_agents'],
      collapsible: tzAiAgents.value.length > 0,
      showTreeLine: true,
      children:
        tzAiAgents.value.length > 0
          ? tzAiAgents.value.map(agent => ({
              name: `ai-agent-${agent.id}`,
              label: agent.name,
              icon: 'i-lucide-bot',
              to: accountScopedRoute(
                'tolzar_ai_agents',
                {},
                { agent: agent.id }
              ),
              activeOn: ['tolzar_ai_agents'],
            }))
          : undefined,
    },
    {
      name: 'Campaigns',
      label: 'Broadcasts',
      icon: 'i-lucide-megaphone',
      children: [
        {
          name: 'Live chat',
          label: t('SIDEBAR.LIVE_CHAT'),
          to: accountScopedRoute('campaigns_livechat_index'),
        },
        {
          name: 'SMS',
          label: t('SIDEBAR.SMS'),
          to: accountScopedRoute('campaigns_sms_index'),
        },
        {
          name: 'WhatsApp',
          label: t('SIDEBAR.WHATSAPP'),
          to: accountScopedRoute('campaigns_whatsapp_index'),
        },
      ],
    },
    {
      name: 'Workflows',
      label: 'Workflows',
      icon: 'i-lucide-git-branch',
      to: accountScopedRoute('tolzar_workflows'),
      activeOn: ['tolzar_workflows'],
    },
    {
      name: 'Reports',
      label: t('SIDEBAR.REPORTS'),
      icon: 'i-lucide-chart-spline',
      children: [
        // Tolzar: leads, bookings, team speed + the AI scoreboard in one page.
        {
          name: 'Tolzar Reports',
          label: t('TOLZAR_REPORTS.NAV'),
          to: accountScopedRoute('tolzar_reports'),
        },
        // Tolzar: what Tolzar is worth (ROI), would-be values marked in Shadow.
        {
          name: 'Tolzar Results',
          label: t('TOLZAR_RESULTS.NAV'),
          to: accountScopedRoute('tolzar_results'),
        },
        {
          name: 'Report Overview',
          label: t('SIDEBAR.REPORTS_OVERVIEW'),
          to: accountScopedRoute('account_overview_reports'),
        },
        {
          name: 'Report Conversation',
          label: t('SIDEBAR.REPORTS_CONVERSATION'),
          to: accountScopedRoute('conversation_reports'),
        },
        ...reportRoutes.value,
        {
          name: 'Reports CSAT',
          label: t('SIDEBAR.CSAT'),
          to: accountScopedRoute('csat_reports'),
        },
        {
          name: 'Reports SLA',
          label: t('SIDEBAR.REPORTS_SLA'),
          to: accountScopedRoute('sla_reports'),
        },
        {
          name: 'Reports Bot',
          label: t('SIDEBAR.REPORTS_BOT'),
          to: accountScopedRoute('bot_reports'),
        },
        ...(isMonitorsAvailable.value
          ? [
              {
                name: 'Monitors',
                label: t('MONITORS.TITLE'),
                to: accountScopedRoute('monitor_reports_index'),
                activeOn: ['monitor_reports_show'],
              },
            ]
          : []),
      ],
    },
    {
      name: 'Settings',
      label: t('SIDEBAR.SETTINGS'),
      icon: 'i-lucide-bolt',
      children: [
        // Tolzar: usage, audit, export, AI features, growth tools in one hub (admins).
        {
          name: 'Settings Tolzar',
          label: t('TOLZAR_SETTINGS.NAV_LABEL'),
          icon: 'i-lucide-sliders-horizontal',
          to: accountScopedRoute('tolzar_settings'),
        },
        {
          name: 'Settings Tolzar Agency',
          label: t('TOLZAR_AGENCY.NAV'),
          icon: 'i-lucide-building-2',
          to: accountScopedRoute('tolzar_agency'),
        },
        {
          name: 'Settings Account Settings',
          label: t('SIDEBAR.ACCOUNT_SETTINGS'),
          icon: 'i-lucide-briefcase',
          to: accountScopedRoute('general_settings_index'),
        },
        // {
        //   name: 'Settings Captain',
        //   label: t('SIDEBAR.CAPTAIN_AI'),
        //   icon: 'i-woot-captain',
        //   to: accountScopedRoute('captain_settings_index'),
        // },
        {
          name: 'Settings Agents',
          label: t('SIDEBAR.AGENTS'),
          icon: 'i-lucide-square-user',
          to: accountScopedRoute('agent_list'),
        },
        {
          name: 'Settings Teams',
          label: t('SIDEBAR.TEAMS'),
          icon: 'i-lucide-users',
          activeOn: [
            'settings_teams_list',
            'settings_teams_new',
            'settings_teams_finish',
            'settings_teams_add_agents',
            'settings_teams_show',
            'settings_teams_edit',
            'settings_teams_edit_members',
            'settings_teams_edit_finish',
          ],
          to: accountScopedRoute('settings_teams_list'),
        },
        ...(hasAdvancedAssignment.value
          ? [
              {
                name: 'Settings Agent Assignment',
                label: t('SIDEBAR.AGENT_ASSIGNMENT'),
                icon: 'i-lucide-user-cog',
                activeOn: [
                  'assignment_policy_index',
                  'agent_assignment_policy_index',
                  'agent_assignment_policy_create',
                  'agent_assignment_policy_edit',
                  'agent_capacity_policy_index',
                  'agent_capacity_policy_create',
                  'agent_capacity_policy_edit',
                ],
                to: accountScopedRoute('assignment_policy_index'),
              },
            ]
          : []),
        {
          name: 'Settings Inboxes',
          label: t('SIDEBAR.INBOXES'),
          icon: 'i-lucide-inbox',
          activeOn: [
            'settings_inbox_list',
            'settings_inbox_show',
            'settings_inbox_new',
            'settings_inbox_finish',
            'settings_inboxes_page_channel',
            'settings_inboxes_add_agents',
          ],
          to: accountScopedRoute('settings_inbox_list'),
        },
        {
          name: 'Settings Templates',
          label: t('SIDEBAR.WHATSAPP_TEMPLATES'),
          icon: 'i-lucide-layout-template',
          to: accountScopedRoute('settings_templates'),
        },
        {
          name: 'Settings Labels',
          label: t('SIDEBAR.LABELS'),
          icon: 'i-lucide-tags',
          to: accountScopedRoute('labels_list'),
        },
        {
          name: 'Settings Custom Attributes',
          label: t('SIDEBAR.CUSTOM_ATTRIBUTES'),
          icon: 'i-lucide-code',
          to: accountScopedRoute('attributes_list'),
        },
        {
          name: 'Settings Automation',
          label: t('SIDEBAR.AUTOMATION'),
          icon: 'i-lucide-repeat',
          to: accountScopedRoute('automation_list'),
        },
        {
          name: 'Settings Agent Bots',
          label: t('SIDEBAR.AGENT_BOTS'),
          icon: 'i-lucide-bot',
          to: accountScopedRoute('agent_bots'),
        },
        {
          name: 'Settings Macros',
          label: t('SIDEBAR.MACROS'),
          icon: 'i-lucide-toy-brick',
          to: accountScopedRoute('macros_wrapper'),
        },
        {
          name: 'Settings Canned Responses',
          label: t('SIDEBAR.CANNED_RESPONSES'),
          icon: 'i-lucide-message-square-quote',
          to: accountScopedRoute('canned_list'),
        },
        {
          name: 'Settings Integrations',
          label: t('SIDEBAR.INTEGRATIONS'),
          icon: 'i-lucide-blocks',
          to: accountScopedRoute('settings_applications'),
        },
        ...(hasDataImport.value
          ? [
              {
                name: 'Settings Data',
                label: t('SIDEBAR.DATA'),
                icon: 'i-lucide-database',
                to: accountScopedRoute('settings_data_imports'),
              },
            ]
          : []),
        {
          name: 'Settings Audit Logs',
          label: t('SIDEBAR.AUDIT_LOGS'),
          icon: 'i-lucide-briefcase',
          to: accountScopedRoute('auditlogs_list'),
        },
        {
          name: 'Settings Custom Roles',
          label: t('SIDEBAR.CUSTOM_ROLES'),
          icon: 'i-lucide-shield-plus',
          to: accountScopedRoute('custom_roles_list'),
        },
        {
          name: 'Settings Sla',
          label: t('SIDEBAR.SLA'),
          icon: 'i-lucide-clock-alert',
          to: accountScopedRoute('sla_list'),
        },
        {
          name: 'Conversation Workflow',
          label: t('SIDEBAR.CONVERSATION_WORKFLOW'),
          icon: 'i-lucide-workflow',
          to: accountScopedRoute('conversation_workflow_index'),
        },
        {
          name: 'Settings Security',
          label: t('SIDEBAR.SECURITY'),
          icon: 'i-lucide-shield',
          to: accountScopedRoute('security_settings_index'),
        },
        {
          name: 'Settings Billing',
          label: t('SIDEBAR.BILLING'),
          icon: 'i-lucide-credit-card',
          to: accountScopedRoute('billing_settings_index'),
        },
      ],
    },
  ];
});

// ───────────────────────────────────────────────────────────────────────────
// Tolzar nav-IA (respond.io-style): a persistent icon rail (every top-level
// section) + a docked sub-sidebar showing the ACTIVE section's tree. Clicking a
// rail icon switches the docked panel and navigates into the section.
// ───────────────────────────────────────────────────────────────────────────
const route = useRoute();
const router = useRouter();
const { shouldShow } = usePolicy();
const { uiSettings, updateUISettings } = useUISettings();

const resolveMeta = (to, key, dflt) => {
  if (!to) return dflt;
  try {
    if (to.params?.navigationPath) {
      const r = router
        .getRoutes()
        .find(x => x.name === to.params.navigationPath);
      return r?.meta?.[key] ?? dflt;
    }
    return router.resolve(to)?.meta?.[key] ?? dflt;
  } catch (e) {
    return dflt;
  }
};

const isNavAllowed = to => {
  if (!to) return false;
  return shouldShow(
    resolveMeta(to, 'featureFlag', ''),
    resolveMeta(to, 'permissions', []),
    resolveMeta(to, 'installationTypes', [])
  );
};

// Flatten a section to its navigable leaves (children + grandchildren).
const leavesOf = item => {
  const out = [];
  (item.children || []).forEach(child => {
    if (child.children) child.children.forEach(g => out.push(g));
    else out.push(child);
  });
  return out;
};

const firstAccessibleLeaf = item =>
  leavesOf(item).find(l => l.to && isNavAllowed(l.to));

const sectionAccessible = item =>
  (item.to && isNavAllowed(item.to)) || !!firstAccessibleLeaf(item);

const visibleSections = computed(() =>
  menuItems.value.filter(sectionAccessible)
);

const matchesTo = to => {
  if (!to) return false;
  try {
    return route.path === router.resolve(to).path;
  } catch (e) {
    return false;
  }
};

const itemMatchesRoute = item => {
  if (item.activeOn?.includes(route.name)) return true;
  if (matchesTo(item.to)) return true;
  if ((item.children || []).some(c => c.activeOn?.includes(route.name)))
    return true;
  return leavesOf(item).some(
    l => l.activeOn?.includes(route.name) || matchesTo(l.to)
  );
};

const routeSectionName = computed(
  () =>
    (visibleSections.value.find(itemMatchesRoute) || visibleSections.value[0])
      ?.name
);

const activeSectionName = ref(null);
watch(
  routeSectionName,
  name => {
    if (name && name !== activeSectionName.value) {
      activeSectionName.value = name;
      expandedItem.value = name;
    }
  },
  { immediate: true }
);

const activeGroup = computed(() =>
  visibleSections.value.find(i => i.name === activeSectionName.value)
);

const isSectionActive = item => item.name === activeSectionName.value;

// Sub-sidebar visibility: only sections that have a tree get a docked panel;
// leaf sections (Dashboard, Pipeline, Workflows) just show their page.
const subNavCollapsed = ref(!!uiSettings.value.tz_subnav_collapsed);
const toggleSubNav = () => {
  subNavCollapsed.value = !subNavCollapsed.value;
  updateUISettings({ tz_subnav_collapsed: subNavCollapsed.value });
};
const activeHasTree = computed(
  () => (activeGroup.value?.children?.length || 0) > 0
);
const showSubSidebar = computed(
  () => activeHasTree.value && !subNavCollapsed.value
);

const selectSection = item => {
  activeSectionName.value = item.name;
  expandedItem.value = item.name;
  // reopen the panel if it was collapsed and this section has a tree
  if (item.children?.length && subNavCollapsed.value) {
    subNavCollapsed.value = false;
    updateUISettings({ tz_subnav_collapsed: false });
  }
  if (item.children?.length) {
    const first = firstAccessibleLeaf(item);
    if (first?.to) router.push(first.to).catch(() => {});
  } else if (item.to) {
    router.push(item.to).catch(() => {});
  }
};
</script>

<template>
  <aside
    v-on-click-outside="[
      closeMobileSidebar,
      {
        ignore: [
          '#mobile-sidebar-launcher',
          '[data-popover-content]',
          '[data-popover-backdrop]',
        ],
      },
    ]"
    class="bg-n-background flex text-sm fixed top-0 ltr:left-0 rtl:right-0 h-full z-40 md:relative md:flex-shrink-0 md:ltr:translate-x-0 md:rtl:translate-x-0 ltr:border-r rtl:border-l border-n-weak transition-transform duration-200 ease-out"
    :class="{
      'shadow-lg md:shadow-none': isMobileSidebarOpen,
      'ltr:-translate-x-full rtl:translate-x-full': !isMobileSidebarOpen,
    }"
  >
    <!-- Tolzar nav-IA: COL 1 — persistent icon rail (every top-level section) -->
    <div
      class="tz-rail flex flex-col flex-shrink-0 w-14 h-full ltr:border-r rtl:border-l border-n-weak"
    >
      <div class="flex flex-col gap-2 items-center pt-3 pb-2">
        <SidebarAccountSwitcher
          is-collapsed
          @show-create-account-modal="emit('showCreateAccountModal')"
        />
        <RouterLink
          :to="{ name: 'search' }"
          class="flex justify-center items-center rounded-lg outline outline-1 size-8 outline-n-weak bg-n-button-color hover:bg-n-alpha-2 dark:hover:bg-n-slate-9/30"
          :title="t('COMBOBOX.SEARCH_PLACEHOLDER')"
        >
          <span class="i-lucide-search size-4 text-n-slate-11" />
        </RouterLink>
        <ComposeConversation align="start">
          <template #trigger="{ isOpen }">
            <Button
              icon="i-lucide-pen-line"
              color="slate"
              size="sm"
              class="!size-8 !outline-n-weak !text-n-slate-11 dark:hover:!bg-n-slate-9/30"
              :class="{ '!bg-n-alpha-2 dark:!bg-n-slate-9/30': isOpen }"
            />
          </template>
        </ComposeConversation>
      </div>
      <nav
        class="flex flex-col flex-grow gap-1 items-center px-1 py-2 overflow-y-auto no-scrollbar"
      >
        <component
          :is="item.children && item.children.length ? 'button' : 'router-link'"
          v-for="item in visibleSections"
          :key="item.name"
          :to="item.children && item.children.length ? undefined : item.to"
          :title="item.label"
          class="tz-rail-ic flex relative justify-center items-center rounded-lg size-10"
          :class="
            isSectionActive(item)
              ? 'text-n-slate-12 bg-n-alpha-2'
              : 'text-n-slate-11 hover:bg-n-alpha-2'
          "
          @click="selectSection(item)"
        >
          <span
            v-if="isSectionActive(item)"
            class="absolute top-2 bottom-2 ltr:-left-1 rtl:-right-1 w-0.5 rounded-full bg-n-brand"
          />
          <Icon :icon="item.icon" class="size-5" />
        </component>
      </nav>
      <div
        class="flex flex-col flex-shrink-0 gap-1 items-center px-1 py-2 border-t border-n-weak"
      >
        <SidebarChangelogButton
          v-if="isOnChatwootCloud && !isACustomBrandedInstance"
        />
        <SidebarProfileMenu
          is-collapsed
          @open-key-shortcut-modal="emit('openKeyShortcutModal')"
        />
        <!-- Tolzar #11: notifications bell at the bottom of the rail -->
        <NotificationsBell is-collapsed />
      </div>
    </div>

    <!-- Tolzar nav-IA: COL 2 — docked sub-sidebar for the active section's tree -->
    <div
      v-if="showSubSidebar"
      class="tz-sub flex flex-col flex-shrink-0 w-60 h-full"
    >
      <div class="flex gap-1 items-center px-3 pt-4 pb-1">
        <h2
          class="flex-1 m-0 text-lg font-bold tracking-tight truncate text-n-slate-12"
        >
          {{ activeGroup.label }}
        </h2>
        <RouterLink
          :to="{ name: 'search' }"
          class="flex justify-center items-center rounded-md size-7 text-n-slate-11 hover:bg-n-alpha-2"
          :title="t('COMBOBOX.SEARCH_PLACEHOLDER')"
        >
          <span class="i-lucide-search size-4" />
        </RouterLink>
        <button
          type="button"
          class="flex justify-center items-center rounded-md size-7 text-n-slate-11 hover:bg-n-alpha-2"
          title="Collapse panel"
          @click="toggleSubNav"
        >
          <span class="i-lucide-panel-left-close size-4" />
        </button>
      </div>
      <nav class="overflow-y-auto flex-grow px-2 pb-5 no-scrollbar min-w-0">
        <ul class="flex flex-col gap-1 m-0 list-none min-w-0">
          <SidebarGroup :key="activeGroup.name" v-bind="activeGroup" docked />
        </ul>
      </nav>
    </div>
  </aside>
</template>
