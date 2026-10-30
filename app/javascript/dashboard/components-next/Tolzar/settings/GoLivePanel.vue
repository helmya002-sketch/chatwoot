<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { useLocale } from 'shared/composables/useLocale';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import ConfirmDialog from '../ConfirmDialog.vue';
import ShadowBadge from '../ShadowBadge.vue';
import BrainNotice from './BrainNotice.vue';
import {
  BTN_DANGER,
  BTN_GHOST,
  INPUT,
  LABEL,
  TONE_WARN,
  TONE_OK,
  TONE_MUTED,
} from './tzClasses';
import { fmtAt } from '../tolzarTime';
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
const { resolvedLocale } = useLocale();
const store = useStore();
const accountId = useMapGetter('getCurrentAccountId');
const inboxes = useMapGetter('inboxes/getInboxes');

const view = ref(null);
const result = ref(null);
const saved = ref('');
const busy = ref(false);
const dialog = ref(null); // the inbox row being confirmed
const liveDialog = ref(null); // the Dialog component (focus trap, Esc, themed)
const confirmRef = ref(null); // ConfirmDialog for the kill switch and its release
const typed = ref('');
const refused = ref(null); // {inbox, reasons}

const owner = computed(() => isOwner(view.value));
// Going live is locked unless the install turned it on for this workspace (account setting
// tolzar_live_allowed, set from the console only). Back to Shadow and the kill switch always work.
const getAccount = useMapGetter('accounts/getAccount');
const liveAllowed = computed(
  () =>
    getAccount.value(accountId.value)?.settings?.tolzar_live_allowed === true
);
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
// One badge for the state everyone must read the same way: Shadow / Live / Off. The mirror
// (read-only) mode is not a Tolzar state, so it keeps a plain muted pill.
const badgeState = mode => {
  if (mode === 'live') return 'live';
  if (mode === 'off') return 'off';
  return 'shadow';
};
const at = s => fmtAt(s, resolvedLocale.value);

function openDialog(row) {
  dialog.value = row;
  typed.value = '';
  refused.value = null;
  result.value = null;
  saved.value = '';
  liveDialog.value?.open();
}
function closeDialog() {
  dialog.value = null;
  liveDialog.value?.close();
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
      closeDialog();
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
  if (!row || !canConfirm.value || busy.value) return undefined;
  return run(
    () => goLive(accountId.value, row.id, 'live', typed.value),
    () => {
      closeDialog();
      return t('TOLZAR_WORKSPACE.GO_LIVE.DONE_LIVE', { inbox: row.name });
    }
  );
};
const backToShadow = row =>
  run(
    () => goLive(accountId.value, row.id, 'shadow'),
    () => t('TOLZAR_WORKSPACE.GO_LIVE.DONE_SHADOW', { inbox: row.name })
  );
// The kill switch stays one click + one confirm: the confirm is the themed ConfirmDialog, never a
// native browser prompt (translatable, keyboard-reachable, does not block the tab).
async function kill() {
  const ok = await confirmRef.value?.ask({
    title: t('TOLZAR_SETTINGS_UI.GO_LIVE.KILL_TITLE'),
    description: t('TOLZAR_WORKSPACE.GO_LIVE.KILL_CONFIRM'),
    confirmLabel: t('TOLZAR_SETTINGS_UI.GO_LIVE.KILL_CONFIRM_BUTTON'),
    cancelLabel: t('TOLZAR_WORKSPACE.GO_LIVE.CANCEL'),
    danger: true,
  });
  if (!ok) return;
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

async function release() {
  const ok = await confirmRef.value?.ask({
    title: t('TOLZAR_SETTINGS_UI.GO_LIVE.RELEASE_TITLE'),
    description: t('TOLZAR_WORKSPACE.GO_LIVE.RELEASE_CONFIRM'),
    confirmLabel: t('TOLZAR_WORKSPACE.GO_LIVE.RELEASE'),
    cancelLabel: t('TOLZAR_WORKSPACE.GO_LIVE.CANCEL'),
    danger: true,
  });
  if (!ok) return;
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
          : `${TONE_OK} border-n-teal-6`
      "
      data-tz-live-state
    >
      <span
        class="size-5 shrink-0"
        :class="anyLive(rows) ? 'i-lucide-radio' : 'i-lucide-shield-check'"
        aria-hidden="true"
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
    <p v-if="view && !owner" class="p-2 mt-2 text-xs rounded-lg" :class="TONE_WARN">
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
            <ShadowBadge
              v-if="r.mode !== 'eval'"
              :state="badgeState(r.mode)"
              :hint="t(`TOLZAR_WORKSPACE.GO_LIVE.MODES.${r.mode}`)"
            />
            <span
              v-else
              class="inline-flex items-center px-2 py-0.5 text-[11px] font-semibold rounded-full"
              :class="TONE_MUTED"
            >
              {{ t('TOLZAR_WORKSPACE.GO_LIVE.MODES.eval') }}
            </span>
            <span
              v-if="r.mode === 'live' && r.since"
              class="ms-1 text-xs text-n-slate-10"
            >
              {{ t('TOLZAR_WORKSPACE.GO_LIVE.SINCE', { at: at(r.since.at) }) }}
            </span>
          </td>
          <td class="text-end">
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
            <span
              v-else-if="r.mode !== 'eval' && !liveAllowed"
              class="text-xs text-n-slate-10"
              data-tz-live-locked
            >
              {{ t('TOLZAR_WORKSPACE.GO_LIVE.LOCKED') }}
            </span>
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

    <!-- confirm dialog: the workspace name, typed exactly (the app's Dialog: focus trap, Esc) -->
    <Dialog
      ref="liveDialog"
      type="alert"
      :title="
        t('TOLZAR_WORKSPACE.GO_LIVE.CONFIRM_TITLE', {
          inbox: dialog ? dialog.name : '',
        })
      "
      :description="t('TOLZAR_WORKSPACE.GO_LIVE.CONFIRM_BODY')"
      :confirm-button-label="t('TOLZAR_WORKSPACE.GO_LIVE.CONFIRM_GO')"
      :cancel-button-label="t('TOLZAR_WORKSPACE.GO_LIVE.CANCEL')"
      :disable-confirm-button="!canConfirm"
      :is-loading="busy"
      @confirm="confirmLive"
      @close="dialog = null"
    >
      <div>
        <label :class="LABEL" class="!mt-0" for="tz-go-live-name">
          {{ t('TOLZAR_WORKSPACE.GO_LIVE.CONFIRM_PLACEHOLDER') }}
        </label>
        <input
          id="tz-go-live-name"
          v-model="typed"
          :class="INPUT"
          :placeholder="t('TOLZAR_WORKSPACE.GO_LIVE.CONFIRM_PLACEHOLDER')"
          autocomplete="off"
          data-tz-confirm-name
        />
      </div>
    </Dialog>

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
        <span class="me-2 i-lucide-power size-4" aria-hidden="true" />{{
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
          :class="BTN_GHOST"
          class="!mt-0"
          :disabled="!owner || busy"
          data-tz-kill-release
          @click="release"
        >
          {{ t('TOLZAR_WORKSPACE.GO_LIVE.RELEASE') }}
        </button>
      </div>
    </div>
    <ConfirmDialog ref="confirmRef" />
    <BrainNotice :result="result" :saved="saved" />
  </div>
</template>
