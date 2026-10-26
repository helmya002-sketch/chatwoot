<script setup>
/**
 * Tolzar briefing strip — a slim, non-intrusive proactive line that greets the agent
 * and surfaces what needs them (hot leads, from the lead scores the brain writes as
 * contact custom_attributes). The pulsing "See briefing" invites the click, then quiets.
 * Real data only: when nothing is hot it says "all caught up" — never a fake number.
 */
import { computed, ref } from 'vue';
import { useRouter } from 'vue-router';
import { useMapGetter } from 'dashboard/composables/store';
import { frontendURL } from 'dashboard/helper/URLHelper';

const router = useRouter();
const currentUser = useMapGetter('getCurrentUser');
const accountId = useMapGetter('getCurrentAccountId');
const allConversations = useMapGetter('getAllConversations');

const dismissed = ref(false);
const open = ref(false);
const seen = ref(false);

const firstName = computed(
  () => (currentUser.value?.name || '').trim().split(' ')[0] || ''
);
const greeting = computed(() => {
  const h = new Date().getHours();
  const part =
    h < 12 ? 'Good morning' : h < 18 ? 'Good afternoon' : 'Good evening';
  return firstName.value ? `${part}, ${firstName.value}` : part;
});

const scoreOf = c => {
  const n = Number(c?.meta?.sender?.custom_attributes?.tolzar_lead_score);
  return Number.isFinite(n) ? n : 0;
};
const hotLeads = computed(() =>
  (allConversations.value || [])
    .filter(c => c.status === 'open' && scoreOf(c) >= 70)
    .map(c => ({
      id: c.id,
      name: c?.meta?.sender?.name || 'Guest',
      score: Math.round(scoreOf(c)),
      hint: c?.meta?.sender?.custom_attributes?.tolzar_lead_hint || '',
    }))
    .sort((a, b) => b.score - a.score)
    .slice(0, 5)
);
const hotCount = computed(() => hotLeads.value.length);

const toggle = () => {
  open.value = !open.value;
  seen.value = true;
};
const jump = id => {
  open.value = false;
  router.push(frontendURL(`accounts/${accountId.value}/conversations/${id}`));
};
</script>

<template>
  <div v-if="!dismissed && firstName" class="tz-brief">
    <span class="tz-m">T</span>
    <span class="tz-g">{{ greeting }} 👋</span>
    <span class="tz-sep" />
    <span v-if="hotCount" class="tz-nudge">
      <svg viewBox="0 0 24 24">
        <path d="M12 2l2.2 6.3L21 10l-6.8 1.7L12 18l-2.2-6.3L3 10z" />
      </svg>
      <b>{{ hotCount }} hot lead{{ hotCount > 1 ? 's' : '' }}</b>&nbsp;waiting
    </span>
    <span v-else class="tz-calm">You're all caught up ✨</span>

    <button
      class="tz-more"
      :class="{ pulse: hotCount && !seen }"
      type="button"
      @click="toggle"
    >
      See briefing
      <svg viewBox="0 0 24 24"><path d="M6 9l6 6 6-6" /></svg>
      <span v-if="hotCount && !seen" class="tz-dot" />
    </button>
    <button
      class="tz-x"
      type="button"
      aria-label="Dismiss briefing"
      @click="dismissed = true"
    >
      ✕
    </button>

    <div v-if="open" class="tz-pop">
      <div class="tz-pop-h">
        <span class="tz-m2">T</span>
        <b>What needs you</b>
        <button class="tz-x" type="button" aria-label="Close" @click="open = false">
          ✕
        </button>
      </div>
      <template v-if="hotCount">
        <button
          v-for="l in hotLeads"
          :key="l.id"
          class="tz-lead"
          type="button"
          @click="jump(l.id)"
        >
          <span class="tz-score">{{ l.score }}</span>
          <span class="tz-lead-t">
            <b>{{ l.name }}</b>
            <i v-if="l.hint">{{ l.hint }}</i>
          </span>
          <svg class="tz-arrow" viewBox="0 0 24 24">
            <path d="M5 12h14M13 6l6 6-6 6" />
          </svg>
        </button>
      </template>
      <div v-else class="tz-empty">
        No urgent leads right now — nice work. Tolzar will flag the moment a hot
        one comes in.
      </div>
    </div>
  </div>
</template>

<style scoped>
/* Slim, calm, theme-aware via Radix tokens. Accent only on the inviting CTA. */
.tz-brief {
  display: flex;
  align-items: center;
  gap: 11px;
  height: 38px;
  padding: 0 18px;
  position: relative;
  font-size: 12.5px;
  color: rgb(var(--slate-11));
  border-bottom: 1px solid rgb(var(--slate-5));
  background: linear-gradient(
      90deg,
      rgb(var(--blue-9) / 0.07),
      transparent 42%
    ),
    rgb(var(--surface-1));
  z-index: 5;
}
.tz-brief .tz-m {
  width: 19px;
  height: 19px;
  flex: 0 0 19px;
  border-radius: 6px;
  display: grid;
  place-items: center;
  color: #fff;
  font-weight: 800;
  font-size: 10px;
  background: linear-gradient(145deg, rgb(var(--blue-9) / 0.85), rgb(var(--blue-9)));
}
.tz-brief .tz-g {
  color: rgb(var(--slate-12));
  font-weight: 650;
  white-space: nowrap;
}
.tz-brief .tz-sep {
  width: 3px;
  height: 3px;
  border-radius: 50%;
  background: rgb(var(--slate-5));
  flex: 0 0 3px;
}
.tz-brief .tz-nudge {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  white-space: nowrap;
}
.tz-brief .tz-nudge svg {
  width: 13px;
  height: 13px;
  flex: 0 0 13px;
  fill: none;
  stroke: rgb(var(--amber-9, 224 168 78));
  stroke-width: 1.7;
}
.tz-brief .tz-nudge b {
  color: rgb(var(--slate-12));
  font-weight: 650;
}
.tz-brief .tz-calm {
  color: rgb(var(--slate-11));
  white-space: nowrap;
}
.tz-brief .tz-more {
  margin-left: auto;
  display: inline-flex;
  align-items: center;
  gap: 6px;
  font-size: 12px;
  font-weight: 650;
  color: #fff;
  background: linear-gradient(180deg, rgb(var(--blue-9) / 0.9), rgb(var(--blue-9)));
  border: 0;
  border-radius: 8px;
  padding: 5px 11px;
  cursor: pointer;
  white-space: nowrap;
  position: relative;
}
.tz-brief .tz-more svg {
  width: 12px;
  height: 12px;
  stroke: #fff;
  fill: none;
  stroke-width: 1.8;
}
.tz-brief .tz-more.pulse {
  animation: tzpulse 2.8s ease-out infinite;
}
@keyframes tzpulse {
  0% {
    box-shadow: 0 0 0 0 rgb(var(--blue-9) / 0.35);
  }
  60% {
    box-shadow: 0 0 0 8px transparent;
  }
  100% {
    box-shadow: 0 0 0 0 transparent;
  }
}
@media (prefers-reduced-motion: reduce) {
  .tz-brief .tz-more.pulse {
    animation: none;
  }
}
.tz-brief .tz-dot {
  position: absolute;
  top: -4px;
  right: -4px;
  width: 9px;
  height: 9px;
  border-radius: 50%;
  background: rgb(var(--amber-9, 224 168 78));
  border: 2px solid rgb(var(--surface-1));
}
.tz-brief .tz-x {
  color: rgb(var(--slate-11));
  background: 0;
  border: 0;
  cursor: pointer;
  font-size: 12px;
  line-height: 1;
  flex: 0 0 auto;
  padding: 2px;
}
.tz-brief .tz-x:hover {
  color: rgb(var(--slate-12));
}

/* popover */
.tz-pop {
  position: absolute;
  top: calc(100% + 8px);
  right: 16px;
  width: 320px;
  z-index: 30;
  border-radius: 14px;
  border: 1px solid rgb(var(--slate-5));
  background: rgb(var(--surface-1));
  box-shadow: 0 2px 6px rgb(0 0 0 / 0.14), 0 18px 44px -20px rgb(0 0 0 / 0.4);
  padding: 12px 13px;
}
.tz-pop .tz-pop-h {
  display: flex;
  align-items: center;
  gap: 8px;
  margin-bottom: 10px;
}
.tz-pop .tz-m2 {
  width: 20px;
  height: 20px;
  border-radius: 6px;
  display: grid;
  place-items: center;
  color: #fff;
  font-weight: 800;
  font-size: 10px;
  background: linear-gradient(145deg, rgb(var(--blue-9) / 0.85), rgb(var(--blue-9)));
}
.tz-pop .tz-pop-h b {
  font-size: 13px;
  color: rgb(var(--slate-12));
}
.tz-pop .tz-pop-h .tz-x {
  margin-left: auto;
}
.tz-pop .tz-lead {
  width: 100%;
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 8px;
  border: 0;
  border-radius: 9px;
  background: 0;
  cursor: pointer;
  text-align: left;
}
.tz-pop .tz-lead:hover {
  background: rgb(var(--blue-9) / 0.07);
}
.tz-pop .tz-score {
  min-width: 26px;
  height: 26px;
  flex: 0 0 26px;
  border-radius: 7px;
  display: grid;
  place-items: center;
  background: rgb(var(--blue-9));
  color: #fff;
  font-weight: 800;
  font-size: 12px;
}
.tz-pop .tz-lead-t {
  display: flex;
  flex-direction: column;
  line-height: 1.25;
  min-width: 0;
}
.tz-pop .tz-lead-t b {
  font-size: 12.5px;
  font-weight: 650;
  color: rgb(var(--slate-12));
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.tz-pop .tz-lead-t i {
  font-size: 11px;
  font-style: normal;
  color: rgb(var(--slate-11));
}
.tz-pop .tz-arrow {
  margin-left: auto;
  width: 14px;
  height: 14px;
  flex: 0 0 14px;
  fill: none;
  stroke: rgb(var(--blue-9));
  stroke-width: 1.8;
}
.tz-pop .tz-empty {
  font-size: 12.5px;
  color: rgb(var(--slate-11));
  line-height: 1.55;
  padding: 2px 4px 4px;
}

/* #3 fix — when the contact pane opens (push layout), the conversation column narrows.
   Let the greeting/status text shrink + truncate so the "See briefing" button always
   fits inside the column (never spilling past the right edge under the contact pane).
   No overflow:hidden on .tz-brief — that would clip the briefing popover below it. */
.tz-brief .tz-g,
.tz-brief .tz-calm,
.tz-brief .tz-nudge {
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
}
.tz-brief .tz-nudge {
  flex-shrink: 1;
}
.tz-brief .tz-nudge b {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.tz-brief .tz-more,
.tz-brief .tz-x,
.tz-brief .tz-m,
.tz-brief .tz-sep {
  flex-shrink: 0;
}
</style>
