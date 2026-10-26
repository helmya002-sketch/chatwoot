<script setup>
import { computed, ref, nextTick } from 'vue';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { formatNumber } from '@chatwoot/utils';
import wootConstants from 'dashboard/constants/globals';

import ConversationBasicFilter from './widgets/conversation/ConversationBasicFilter.vue';
import SwitchLayout from 'dashboard/routes/dashboard/conversation/search/SwitchLayout.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  pageTitle: { type: String, required: true },
  contactFilter: { type: Object, default: null },
  hasAppliedFilters: { type: Boolean, required: true },
  hasActiveFolders: { type: Boolean, required: true },
  activeStatus: { type: String, required: true },
  isOnExpandedLayout: { type: Boolean, required: true },
  conversationStats: { type: Object, required: true },
  isListLoading: { type: Boolean, required: true },
  // Tolzar #6b: the active quick-filter segment ('open' | 'unreplied' | 'resolved')
  statusSegment: { type: String, default: 'open' },
  // Tolzar #6b: the current list-scoped search text (client-side, the loaded list)
  searchQuery: { type: String, default: '' },
});

const emit = defineEmits([
  'addFolders',
  'deleteFolders',
  'resetFilters',
  'basicFilterChange',
  'filtersModal',
  // Tolzar #6b: top-bar quick filters + list search (no extra row)
  'statusSegment',
  'searchChange',
]);

// Tolzar #6b: Open / Unreplied / Closed as a compact segmented control on the
// existing top row. 'resolved' is labelled "Closed" to match team wording.
const TZ_SEGMENTS = [
  { key: 'open', label: 'Open' },
  { key: 'unreplied', label: 'Unreplied' },
  { key: 'resolved', label: 'Closed' },
];
const showSearch = ref(false);
const searchInputRef = ref(null);

const openSearch = async () => {
  showSearch.value = true;
  await nextTick();
  searchInputRef.value?.focus();
};
const closeSearch = () => {
  showSearch.value = false;
  if (props.searchQuery) emit('searchChange', '');
};
const onSearchInput = e => emit('searchChange', e.target.value);

const { uiSettings, updateUISettings } = useUISettings();

const onBasicFilterChange = (value, type) => {
  emit('basicFilterChange', value, type);
};

const hasAppliedFiltersOrActiveFolders = computed(() => {
  return props.hasAppliedFilters || props.hasActiveFolders;
});

const allCount = computed(() => props.conversationStats?.allCount || 0);
const formattedAllCount = computed(() => formatNumber(allCount.value));

// While filters narrow the list, the header names it and the back button exits.
const showFilterScope = computed(
  () => props.hasAppliedFilters && !props.hasActiveFolders
);

// The contact scope is set from the contact panel; it is exited, not edited.
const isContactScoped = computed(
  () => showFilterScope.value && !!props.contactFilter
);

const title = computed(
  () => (isContactScoped.value && props.contactFilter.name) || props.pageTitle
);

const toggleConversationLayout = () => {
  const { LAYOUT_TYPES } = wootConstants;
  const {
    conversation_display_type: conversationDisplayType = LAYOUT_TYPES.CONDENSED,
  } = uiSettings.value;
  const newViewType =
    conversationDisplayType === LAYOUT_TYPES.CONDENSED
      ? LAYOUT_TYPES.EXPANDED
      : LAYOUT_TYPES.CONDENSED;
  updateUISettings({
    conversation_display_type: newViewType,
    previously_used_conversation_display_type: newViewType,
  });
};
</script>

<template>
  <div
    class="flex items-center justify-between gap-2 px-3 h-[3.25rem]"
    :class="{
      'border-b border-n-strong': hasAppliedFiltersOrActiveFolders,
    }"
  >
    <!-- Tolzar #6b: list-scoped search overlays the title area when active -->
    <div v-if="showSearch" class="flex items-center flex-1 min-w-0 gap-1">
      <input
        ref="searchInputRef"
        type="text"
        :value="searchQuery"
        placeholder="Search this list"
        class="flex-1 min-w-0 bg-transparent border-0 outline-none text-sm text-n-slate-12 placeholder:text-n-slate-10"
        @input="onSearchInput"
        @keydown.esc="closeSearch"
      />
      <NextButton
        v-tooltip.top="'Close search'"
        icon="i-lucide-x"
        slate
        xs
        faded
        class="shrink-0"
        @click="closeSearch"
      />
    </div>
    <div v-else class="flex items-center min-w-0">
      <NextButton
        v-if="showFilterScope"
        v-tooltip.right="$t('FILTER.CLEAR_BUTTON_LABEL')"
        :aria-label="$t('FILTER.CLEAR_BUTTON_LABEL')"
        icon="i-lucide-chevron-left"
        class="shrink-0 -ms-2 !h-6 !w-6 me-1"
        slate
        sm
        ghost
        @click="emit('resetFilters')"
      />
      <h1
        class="text-base font-medium truncate text-n-slate-12 shrink"
        :title="title"
      >
        {{ title }}
      </h1>
      <span
        v-if="
          allCount > 0 && hasAppliedFiltersOrActiveFolders && !isListLoading
        "
        class="px-2 py-1 my-0.5 mx-1 rounded-md capitalize bg-n-slate-3 text-xxs text-n-slate-12 shrink-0"
        :title="allCount"
      >
        {{ formattedAllCount }}
      </span>
      <!-- Tolzar #6b: Open / Unreplied / Closed quick filter (replaces the status chip) -->
      <div
        v-if="!hasAppliedFiltersOrActiveFolders"
        class="tz-seg shrink-0"
        role="tablist"
      >
        <button
          v-for="s in TZ_SEGMENTS"
          :key="s.key"
          type="button"
          role="tab"
          class="tz-seg-btn"
          :class="{ 'tz-seg-on': statusSegment === s.key }"
          @click="emit('statusSegment', s.key)"
        >
          {{ s.label }}
        </button>
      </div>
    </div>
    <div class="flex items-center gap-1">
      <!-- Tolzar #6b: toggle the list-scoped search -->
      <NextButton
        v-if="!isContactScoped"
        v-tooltip.top="'Search this list'"
        :aria-label="'Search this list'"
        :icon="showSearch ? 'i-lucide-x' : 'i-lucide-search'"
        slate
        xs
        faded
        class="shrink-0"
        @click="showSearch ? closeSearch() : openSearch()"
      />
      <template v-if="hasAppliedFilters && !hasActiveFolders">
        <div class="relative">
          <NextButton
            v-tooltip.top-end="$t('FILTER.CUSTOM_VIEWS.ADD.SAVE_BUTTON')"
            icon="i-lucide-save"
            slate
            xs
            faded
            @click="emit('addFolders')"
          />
          <div
            id="saveFilterTeleportTarget"
            class="absolute z-50 mt-2"
            :class="{ 'ltr:right-0 rtl:left-0': isOnExpandedLayout }"
          />
        </div>
      </template>
      <template v-if="hasActiveFolders">
        <div class="relative">
          <NextButton
            id="toggleConversationFilterButton"
            v-tooltip.top-end="$t('FILTER.CUSTOM_VIEWS.EDIT.EDIT_BUTTON')"
            icon="i-lucide-pen-line"
            slate
            xs
            faded
            @click="emit('filtersModal')"
          />
          <div
            id="conversationFilterTeleportTarget"
            class="absolute z-50 mt-2"
            :class="{ 'ltr:right-0 rtl:left-0': isOnExpandedLayout }"
          />
        </div>
        <NextButton
          id="toggleConversationFilterButton"
          v-tooltip.top-end="$t('FILTER.CUSTOM_VIEWS.DELETE.DELETE_BUTTON')"
          icon="i-lucide-trash-2"
          ruby
          xs
          faded
          @click="emit('deleteFolders')"
        />
      </template>
      <div v-else-if="!isContactScoped" class="relative">
        <NextButton
          id="toggleConversationFilterButton"
          v-tooltip.right="$t('FILTER.TOOLTIP_LABEL')"
          icon="i-lucide-list-filter"
          slate
          xs
          faded
          @click="emit('filtersModal')"
        />
        <div
          id="conversationFilterTeleportTarget"
          class="absolute z-50 mt-2"
          :class="{ 'ltr:right-0 rtl:left-0': isOnExpandedLayout }"
        />
      </div>
      <ConversationBasicFilter
        v-if="!isContactScoped"
        :is-on-expanded-layout="isOnExpandedLayout"
        :show-status-filter="!hasAppliedFiltersOrActiveFolders"
        @change-filter="onBasicFilterChange"
      />
      <SwitchLayout
        :is-on-expanded-layout="isOnExpandedLayout"
        @toggle="toggleConversationLayout"
      />
    </div>
  </div>
</template>

<style scoped>
/* Tolzar #6b: compact Open / Unreplied / Closed quick-filter on the top row */
.tz-seg {
  display: inline-flex;
  align-items: center;
  gap: 2px;
  margin: 0 2px;
  padding: 2px;
  border-radius: 7px;
  background: rgb(var(--slate-3));
}
.tz-seg-btn {
  padding: 2px 7px;
  border-radius: 5px;
  font-size: 11px;
  font-weight: 600;
  line-height: 1.4;
  color: rgb(var(--slate-11));
  white-space: nowrap;
  transition:
    background 0.12s ease,
    color 0.12s ease;
}
.tz-seg-btn:hover {
  color: rgb(var(--slate-12));
}
.tz-seg-on {
  background: rgb(var(--surface-1));
  color: rgb(var(--blue-11));
  box-shadow: 0 1px 2px rgb(0 0 0 / 0.06);
}
</style>
