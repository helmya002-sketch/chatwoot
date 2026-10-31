<script setup>
// Tolzar Contacts pass 1: a dense, scannable table instead of Chatwoot's one-card-per-contact
// list. Each row: channel badge, name, the brain's one-line summary, stage, lead score, place
// and last interaction. Clicking (or Enter / Space on) a row opens the preview pane; the checkbox
// drives bulk actions. Lead score and last interaction sort client-side on the loaded page.
import { useI18n } from 'vue-i18n';
import { computed, ref, watch } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { dynamicTime } from 'shared/helpers/timeHelper';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import ChannelIcon from 'dashboard/components-next/icon/ChannelIcon.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';
import {
  defaultStage,
  contactStage,
  leadScore,
  scoreBar,
  scoreTone,
  stageClass,
  stageOf,
} from './tolzarStages';
import { contactChannel } from './tolzarChannel';
import { EMPTY_PACK, contactPlace, fetchPack } from './tolzarPack';

const props = defineProps({
  contacts: { type: Array, required: true },
  selectedContactIds: { type: Array, default: () => [] },
  activeContactId: { type: Number, default: null },
});

const emit = defineEmits(['toggleContact', 'toggleAll', 'open']);

const store = useStore();
const { t } = useI18n();
// The place column: the workspace pack's own place field first, then the core place.
const accountId = useMapGetter('getCurrentAccountId');
const pack = ref(EMPTY_PACK);
watch(
  accountId,
  async id => {
    pack.value = await fetchPack(id);
  },
  { immediate: true }
);
const selected = computed(() => new Set(props.selectedContactIds));
const allSelected = computed(
  () =>
    props.contacts.length > 0 &&
    props.contacts.every(c => selected.value.has(c.id))
);
const someSelected = computed(
  () => !allSelected.value && props.contacts.some(c => selected.value.has(c.id))
);

// The list getter camelCases custom-attribute keys; read the raw record for those.
const rows = computed(() =>
  props.contacts.map(contact => {
    const raw = store.getters['contacts/getContact'](contact.id) || {};
    const attrs = raw.custom_attributes || {};
    const inbox = contactChannel(raw);
    const score = leadScore(attrs);
    const add = raw.additional_attributes || {};
    return {
      id: contact.id,
      name: contact.name || contact.email || contact.phoneNumber || '—',
      thumbnail: contact.thumbnail,
      status: contact.availabilityStatus,
      inbox,
      summary: (attrs.tolzar_summary || '').trim(),
      contactLine:
        [contact.phoneNumber, contact.email].filter(Boolean)[0] || '',
      stage: contactStage(attrs) || defaultStage(),
      score,
      place: contactPlace(pack.value, attrs, add),
      lastAt: raw.last_activity_at,
    };
  })
);

// Client-side sort of the loaded page: '' keeps the server order. Unscored contacts and
// contacts with no activity sort last whichever way the column points.
const SORTABLE = {
  score: { label: 'TOLZAR_CONTACTS.TABLE.LEAD_SCORE', value: r => r.score },
  lastAt: {
    label: 'TOLZAR_CONTACTS.TABLE.LAST_INTERACTION',
    value: r => (r.lastAt ? Number(r.lastAt) : null),
  },
};
const sort = ref({ key: '', dir: 'desc' });
const toggleSort = key => {
  if (sort.value.key !== key) sort.value = { key, dir: 'desc' };
  else if (sort.value.dir === 'desc') sort.value = { key, dir: 'asc' };
  else sort.value = { key: '', dir: 'desc' };
};
const ariaSort = key => {
  if (sort.value.key !== key) return 'none';
  return sort.value.dir === 'asc' ? 'ascending' : 'descending';
};
const sortTitle = key => {
  const column = t(SORTABLE[key].label);
  const state =
    sort.value.key === key
      ? t(`TOLZAR_CONTACTS.TABLE.SORTED_${sort.value.dir.toUpperCase()}`)
      : '';
  return [t('TOLZAR_CONTACTS.TABLE.SORT_BY', { column }), state]
    .filter(Boolean)
    .join(', ');
};
const sortedRows = computed(() => {
  const { key, dir } = sort.value;
  if (!key) return rows.value;
  const value = SORTABLE[key].value;
  const sign = dir === 'asc' ? 1 : -1;
  return [...rows.value].sort((a, b) => {
    const av = value(a);
    const bv = value(b);
    if (av === null && bv === null) return 0;
    if (av === null) return 1;
    if (bv === null) return -1;
    return (av - bv) * sign;
  });
});
</script>

<template>
  <div class="overflow-hidden border rounded-xl border-n-weak bg-n-background">
    <table class="tz-contacts-table w-full text-sm border-collapse table-fixed">
      <colgroup>
        <col class="w-10" />
        <col />
        <col class="w-28" />
        <col class="w-28" />
        <col class="hidden w-40 2xl:table-column" />
        <col v-if="!activeContactId" class="w-36" />
      </colgroup>
      <thead>
        <tr class="text-xs text-n-slate-10 border-b border-n-weak">
          <th class="px-3 py-2.5 font-normal text-start">
            <!-- Checkbox renders a bare input; the wrapping label names it for screen readers. -->
            <label class="flex items-center cursor-pointer">
              <Checkbox
                :model-value="allSelected"
                :indeterminate="someSelected"
                @change="e => emit('toggleAll', e.target.checked)"
              />
              <span class="sr-only">{{
                t('TOLZAR_CONTACTS.TABLE.SELECT_ALL')
              }}</span>
            </label>
          </th>
          <th class="px-2 py-2.5 font-normal text-start">
            {{ t('TOLZAR_CONTACTS.TABLE.CONTACT') }}
          </th>
          <th class="px-2 py-2.5 font-normal text-start">
            {{ t('TOLZAR_CONTACTS.TABLE.STAGE') }}
          </th>
          <th
            class="px-2 py-2.5 font-normal text-start"
            :aria-sort="ariaSort('score')"
          >
            <button
              type="button"
              class="inline-flex items-center gap-1 rounded hover:text-n-slate-12 focus-visible:outline focus-visible:outline-1 focus-visible:outline-n-brand"
              :class="{ 'text-n-slate-12': sort.key === 'score' }"
              :title="sortTitle('score')"
              @click="toggleSort('score')"
            >
              {{ t('TOLZAR_CONTACTS.TABLE.LEAD_SCORE') }}
              <span
                class="size-3"
                :class="
                  sort.key !== 'score'
                    ? 'i-lucide-chevrons-up-down opacity-60'
                    : sort.dir === 'asc'
                      ? 'i-lucide-chevron-up'
                      : 'i-lucide-chevron-down'
                "
                aria-hidden="true"
              />
            </button>
          </th>
          <th class="hidden px-2 py-2.5 font-normal text-start 2xl:table-cell">
            {{ t('TOLZAR_CONTACTS.TABLE.PLACE') }}
          </th>
          <th
            v-if="!activeContactId"
            class="px-2 py-2.5 font-normal text-start"
            :aria-sort="ariaSort('lastAt')"
          >
            <button
              type="button"
              class="inline-flex items-center gap-1 rounded hover:text-n-slate-12 focus-visible:outline focus-visible:outline-1 focus-visible:outline-n-brand"
              :class="{ 'text-n-slate-12': sort.key === 'lastAt' }"
              :title="sortTitle('lastAt')"
              @click="toggleSort('lastAt')"
            >
              {{ t('TOLZAR_CONTACTS.TABLE.LAST_INTERACTION') }}
              <span
                class="size-3"
                :class="
                  sort.key !== 'lastAt'
                    ? 'i-lucide-chevrons-up-down opacity-60'
                    : sort.dir === 'asc'
                      ? 'i-lucide-chevron-up'
                      : 'i-lucide-chevron-down'
                "
                aria-hidden="true"
              />
            </button>
          </th>
        </tr>
      </thead>
      <tbody>
        <tr
          v-for="row in sortedRows"
          :key="row.id"
          class="border-b cursor-pointer border-n-weak last:border-b-0 hover:bg-n-slate-2 focus-visible:outline focus-visible:outline-1 focus-visible:-outline-offset-1 focus-visible:outline-n-brand"
          :class="{
            '!bg-n-blue-2': row.id === activeContactId,
            'bg-n-slate-2': selected.has(row.id) && row.id !== activeContactId,
          }"
          role="button"
          tabindex="0"
          :aria-label="t('TOLZAR_CONTACTS.TABLE.OPEN_ROW', { name: row.name })"
          :aria-pressed="row.id === activeContactId ? 'true' : 'false'"
          @click="emit('open', row.id)"
          @keydown.enter.prevent="emit('open', row.id)"
          @keydown.space.prevent="emit('open', row.id)"
        >
          <td class="px-3 py-2.5 align-top" @click.stop @keydown.stop>
            <label class="flex items-center cursor-pointer">
              <Checkbox
                :model-value="selected.has(row.id)"
                @change="
                  e =>
                    emit('toggleContact', {
                      id: row.id,
                      value: e.target.checked,
                    })
                "
              />
              <span class="sr-only">{{ row.name }}</span>
            </label>
          </td>
          <td class="px-2 py-2 align-top">
            <div class="flex min-w-0 gap-2.5">
              <div class="relative flex-shrink-0">
                <Avatar
                  :name="row.name"
                  :src="row.thumbnail"
                  :size="32"
                  :status="row.status"
                  hide-offline-status
                />
                <span
                  v-if="row.inbox && row.inbox.channel_type"
                  v-tooltip.top="row.inbox.name"
                  class="absolute -bottom-1 -end-1 flex items-center justify-center size-[15px] rounded-full bg-n-background ring-2 ring-n-background"
                >
                  <ChannelIcon :inbox="row.inbox" class="size-[13px]" />
                </span>
              </div>
              <div class="min-w-0">
                <div class="font-medium truncate text-n-slate-12">
                  {{ row.name }}
                </div>
                <div
                  v-if="row.summary"
                  class="text-xs truncate text-n-slate-11"
                  :title="row.summary"
                >
                  <span class="text-n-blue-11">{{
                    t('TOLZAR_CONTACTS.TABLE.SUMMARY_MARK')
                  }}</span>
                  {{ row.summary }}
                </div>
                <div v-else class="text-xs truncate text-n-slate-10">
                  {{ row.contactLine }}
                </div>
              </div>
            </div>
          </td>
          <td class="px-2 py-2.5 align-top">
            <span
              class="inline-flex items-center gap-1.5 px-2 py-0.5 text-xs font-semibold rounded-full whitespace-nowrap"
              :class="stageClass(row.stage)"
            >
              <span class="rounded-full size-1.5 bg-current" />
              {{ stageOf(row.stage).label }}
            </span>
          </td>
          <td class="px-2 py-2.5 align-top">
            <div v-if="row.score !== null" class="flex items-center gap-2">
              <span class="text-xs font-semibold" :class="scoreTone(row.score)">
                {{ row.score }}
              </span>
              <span class="w-10 h-1 overflow-hidden rounded bg-n-slate-4">
                <span
                  class="block h-full rounded"
                  :class="scoreBar(row.score)"
                  :style="{ width: `${row.score}%` }"
                />
              </span>
            </div>
            <span v-else class="text-xs text-n-slate-10">—</span>
          </td>
          <td class="hidden px-2 py-2.5 align-top 2xl:table-cell">
            <span class="block text-xs truncate text-n-slate-11">
              {{ row.place || '—' }}
            </span>
          </td>
          <!-- With the preview pane open, the pane shows this; give the name the room. -->
          <td v-if="!activeContactId" class="px-2 py-2.5 align-top">
            <div class="text-xs text-n-slate-12 whitespace-nowrap">
              {{ row.lastAt ? dynamicTime(row.lastAt) : '—' }}
            </div>
            <div
              v-if="row.inbox"
              class="text-xs truncate text-n-slate-10"
              :title="row.inbox.name"
            >
              {{ row.inbox.name }}
            </div>
          </td>
        </tr>
      </tbody>
    </table>
  </div>
</template>
