<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import BrainNotice from './BrainNotice.vue';
import { BTN_DANGER, BTN_GHOST, INPUT } from './tzClasses';
import {
  getWorkspaceSettings,
  goLive,
  killSwitch,
  releaseKillSwitch,
  inboxModes,
  anyLive,
  confirmMatches,
  parseReasons,
  isOwner,
} from '../tolzarWorkspace';

// Settings hub → Go live (Owner only): every inbox's current mode, Shadow by default. Going live
// needs the workspace name typed exactly, and the brain refuses (422) unless every live check is
// clear; its reasons are shown in plain words. The kill switch puts everything back to Shadow.
const { t } = useI18n();
const store = useStore();
const accountId = useMapGetter('getCurrentAccountId');
const inboxes = useMapGetter('inboxes/getInboxes');

const view = ref(null);
const result = ref(null);
const saved = ref('');
const busy = ref(false);
const dialog = ref(null); // the inbox row being confirmed
const typed = ref('');
const refused = ref(null); // {inbox, reasons}

const owner = computed(() => isOwner(view.value));
const rows = computed(() =>
  view.value ? inboxModes(view.value, inboxes.value || []) : []
);
const live = computed(() => rows.value.filter(r => r.mode === 'live'));
const refusedTitle = computed(() => {
  const what = t('TOLZAR_WORKSPACE.GO_LIVE.REFUSED');
  return refused.value && refused.value.inbox
    ? `${refused.value.inbox.name}: ${what}`
    : what;
});
const canConfirm = computed(() => confirmMatches(typed.value, view.value));

async function load() {
  const v = await getWorkspaceSettings(accountId.value);
  if (v && v.ok !== false) view.value = v;
  else result.value = v;
}

function reasonText(r) {
  const base = r.known
    ? t(`TOLZAR_WORKSPACE.GO_LIVE.REASON.${r.code}`)
    : r.code;
  if (r.team === null) return base;
  return r.team
    ? t('TOLZAR_WORKSPACE.GO_LIVE.TEAM_REASON', { team: r.team, reason: base })
    : t('TOLZAR_WORKSPACE.GO_LIVE.TEAM_AGENT_REASON', { reason: base });
}
const MODE_CLASS = {
  live: 'text-white bg-n-ruby-9',
  eval: 'text-n-slate-11 bg-n-alpha-2',
};
const modeClass = mode => MODE_CLASS[mode] || 'text-amber-700 bg-amber-500/10';
const at = s =>
  String(s || '')
    .slice(0, 16)
    .replace('T', ' ');

function openDialog(row) {
  dialog.value = row;
  typed.value = '';
  refused.value = null;
  result.value = null;
  saved.value = '';
}
async function run(fn, after) {
  busy.value = true;
  result.value = null;
  saved.value = '';
  try {
    const r = await fn();
    if (r && r.ok) {
      saved.value = after(r);
      await load();
    } else if (r && r.error === 'not_live_ready') {
      refused.value = { inbox: dialog.value, reasons: parseReasons(r) };
      dialog.value = null;
    } else {
      result.value = r;
    }
  } catch (e) {
    result.value = { ok: false, error: 'brain_unreachable' };
  } finally {
    busy.value = false;
  }
}
const confirmLive = () => {
  const row = dialog.value;
  return run(
    () => goLive(accountId.value, row.id, 'live', typed.value),
    () => {
      dialog.value = null;
      return t('TOLZAR_WORKSPACE.GO_LIVE.DONE_LIVE', { inbox: row.name });
    }
  );
};
const backToShadow = row =>
  run(
    () => goLive(accountId.value, row.id, 'shadow'),
    () => t('TOLZAR_WORKSPACE.GO_LIVE.DONE_SHADOW', { inbox: row.name })
  );
function kill() {
  // eslint-disable-next-line no-alert
  if (!window.confirm(t('TOLZAR_WORKSPACE.GO_LIVE.KILL_CONFIRM'))) return;
  const none = t('TOLZAR_WORKSPACE.GO_LIVE.NONE');
  run(
    () => killSwitch(accountId.value),
    r =>
      t('TOLZAR_WORKSPACE.GO_LIVE.KILL_DONE', {
        were: (r.were_live || []).join(', ') || none,
        now: (r.live_inboxes || []).join(', ') || none,
      })
  );
}

function release() {
  // eslint-disable-next-line no-alert
  if (!window.confirm(t('TOLZAR_WORKSPACE.GO_LIVE.RELEASE_CONFIRM'))) return;
  run(
    () => releaseKillSwitch(accountId.value),
    () => t('TOLZAR_WORKSPACE.GO_LIVE.RELEASE_DONE')
  );
}

onMounted(() => {
  store.dispatch('inboxes/get');
  load();
});
</script>

<template>
  <div data-tz-go-live>
    <!-- the state, first and unmissable -->
    <div
      class="flex gap-3 items-center p-4 rounded-xl border border-solid"
      :class="
        anyLive(rows)
          ? 'text-white bg-n-ruby-9 border-n-ruby-9'
          : 'text-emerald-800 bg-emerald-500/10 border-emerald-500/30'
      "
      data-tz-live-state
    >
      <span
        class="size-5 shrink-0"
        :class="anyLive(rows) ? 'i-lucide-radio' : 'i-lucide-shield-check'"
      />
      <b class="text-[14px]">{{
        anyLive(rows)
          ? t('TOLZAR_WORKSPACE.GO_LIVE.BANNER_LIVE', { n: live.length })
          : t('TOLZAR_WORKSPACE.GO_LIVE.BANNER_SHADOW')
      }}</b>
    </div>
    <p class="p-2 mt-3 text-xs rounded-lg text-n-ruby-11 bg-n-ruby-9/10">
      {{ t('TOLZAR_WORKSPACE.GO_LIVE.WARNING') }}
    </p>
    <p
      v-if="view && !owner"
      class="p-2 mt-2 text-xs rounded-lg text-amber-700 bg-amber-500/10"
    >
      {{ t('TOLZAR_WORKSPACE.GO_LIVE.OWNER_ONLY') }}
    </p>

    <table v-if="rows.length" class="mt-3 w-full text-[13px]">
      <thead>
        <tr class="text-left text-xs text-n-slate-10">
          <th class="py-1 font-semibold">
            {{ t('TOLZAR_WORKSPACE.GO_LIVE.INBOX') }}
          </th>
          <th class="font-semibold">
            {{ t('TOLZAR_WORKSPACE.GO_LIVE.MODE') }}
          </th>
          <th />
        </tr>
      </thead>
      <tbody>
        <tr v-for="r in rows" :key="r.id" class="border-t border-n-weak">
          <td class="py-2">
            {{ r.name }}
            <span class="text-xs text-n-slate-10">#{{ r.id }}</span>
          </td>
          <td>
            <span
              class="inline-flex items-center px-2 py-0.5 text-[11px] font-semibold rounded-full"
              :class="modeClass(r.mode)"
            >
              {{ t(`TOLZAR_WORKSPACE.GO_LIVE.MODES.${r.mode}`) }}
            </span>
            <span
              v-if="r.mode === 'live' && r.since"
              class="ml-1 text-xs text-n-slate-10"
            >
              {{ t('TOLZAR_WORKSPACE.GO_LIVE.SINCE', { at: at(r.since.at) }) }}
            </span>
          </td>
          <td class="text-right">
            <button
              v-if="r.mode === 'live'"
              type="button"
              :class="BTN_GHOST"
              class="!mt-0 !h-8"
              :disabled="!owner || busy"
              @click="backToShadow(r)"
            >
              {{ t('TOLZAR_WORKSPACE.GO_LIVE.BACK') }}
            </button>
            <button
              v-else-if="r.mode !== 'eval'"
              type="button"
              :class="BTN_DANGER"
              class="!mt-0 !h-8"
              :disabled="!owner || busy"
              @click="openDialog(r)"
            >
              {{ t('TOLZAR_WORKSPACE.GO_LIVE.GO') }}
            </button>
          </td>
        </tr>
      </tbody>
    </table>
    <p v-else-if="view" class="mt-3 text-[13px] text-n-slate-10">
      {{ t('TOLZAR_WORKSPACE.GO_LIVE.NO_INBOXES') }}
    </p>

    <div
      v-if="refused"
      class="p-3 mt-3 text-[13px] rounded-lg border border-solid text-n-ruby-11 bg-n-ruby-9/10 border-n-ruby-9/30"
      data-tz-live-refused
    >
      <b>{{ refusedTitle }}</b>
      <ul class="pl-5 mt-1 mb-0">
        <li v-for="r in refused.reasons" :key="r.raw">{{ reasonText(r) }}</li>
      </ul>
    </div>

    <!-- confirm dialog: the workspace name, typed exactly -->
    <div
      v-if="dialog"
      class="flex fixed inset-0 z-50 justify-center items-center p-4 bg-black/50"
      @click.self="dialog = null"
    >
      <div
        class="p-5 w-full max-w-[440px] rounded-2xl border-2 border-solid shadow-xl bg-n-solid-1 border-n-ruby-9"
        role="dialog"
        aria-modal="true"
      >
        <h3 class="m-0 text-[16px] font-bold text-n-ruby-11">
          {{
            t('TOLZAR_WORKSPACE.GO_LIVE.CONFIRM_TITLE', { inbox: dialog.name })
          }}
        </h3>
        <p class="mt-2 text-[13px] text-n-slate-12">
          {{ t('TOLZAR_WORKSPACE.GO_LIVE.CONFIRM_BODY') }}
        </p>
        <input
          v-model="typed"
          :class="INPUT"
          :placeholder="t('TOLZAR_WORKSPACE.GO_LIVE.CONFIRM_PLACEHOLDER')"
          autocomplete="off"
          data-tz-confirm-name
          @keyup.enter="canConfirm && !busy && confirmLive()"
        />
        <div class="flex gap-2 justify-end">
          <button type="button" :class="BTN_GHOST" @click="dialog = null">
            {{ t('TOLZAR_WORKSPACE.GO_LIVE.CANCEL') }}
          </button>
          <button
            type="button"
            :class="BTN_DANGER"
            :disabled="!canConfirm || busy"
            @click="confirmLive"
          >
            {{ t('TOLZAR_WORKSPACE.GO_LIVE.CONFIRM_GO') }}
          </button>
        </div>
      </div>
    </div>

    <!-- kill switch -->
    <div class="p-4 mt-6 rounded-xl border-2 border-dashed border-n-ruby-9/50">
      <button
        type="button"
        :class="BTN_DANGER"
        class="!mt-0 !h-11 !px-5 !text-[15px]"
        :disabled="!owner || busy"
        data-tz-kill-switch
        @click="kill"
      >
        <span class="mr-2 i-lucide-power size-4" />{{
          t('TOLZAR_WORKSPACE.GO_LIVE.KILL')
        }}
      </button>
      <p class="mt-2 mb-0 text-xs text-n-slate-11">
        {{ t('TOLZAR_WORKSPACE.GO_LIVE.KILL_HINT') }}
      </p>
      <p
        v-if="view && view.kill_switch"
        class="mt-1 mb-0 text-xs text-n-slate-10"
      >
        {{
          t('TOLZAR_WORKSPACE.GO_LIVE.LAST_KILL', {
            at: at(view.kill_switch.at),
            by: String(view.kill_switch.by || '')
              .split(':')
              .pop(),
          })
        }}
      </p>
      <div
        v-if="view && view.kill_switch_on"
        class="flex flex-wrap items-center gap-3 mt-3"
        data-tz-kill-locked
      >
        <p class="m-0 text-xs text-n-ruby-11">
          {{ t('TOLZAR_WORKSPACE.GO_LIVE.LOCKED') }}
        </p>
        <button
          type="button"
          class="!mt-0 !h-9 !px-4 text-sm rounded-lg border border-n-weak"
          :disabled="!owner || busy"
          data-tz-kill-release
          @click="release"
        >
          {{ t('TOLZAR_WORKSPACE.GO_LIVE.RELEASE') }}
        </button>
      </div>
    </div>
    <BrainNotice :result="result" :saved="saved" />
  </div>
</template>
