<script setup>
// Tolzar: "Why the AI said this" under the copilot draft. On demand it reads the brain's explanation of
// the latest decision in this conversation (brain /explain, built from the decision log, never invented
// afterwards): where it routed and how sure it was, what the reply is based on (cited facts and prices,
// with links), and which checks passed or replaced the reply. The model's name is never shown.
import { computed, ref, watch } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { brainGet } from './tolzarBrainApi';

const props = defineProps({
  conversationId: { type: Number, required: true },
});

const accountId = useMapGetter('getCurrentAccountId');
const open = ref(false);
const loading = ref(false);
const failed = ref(false);
const data = ref(null);

const CHECKS = [
  'price_guard',
  'grounding',
  'output_policy',
  'language',
  'consistency',
];
const checks = computed(() =>
  (data.value?.checks || []).filter(c => CHECKS.includes(c.check))
);
const basedOn = computed(() => data.value?.based_on || []);
const confidence = computed(() => {
  const c = Number(data.value?.confidence);
  return Number.isFinite(c) ? Math.round(c * 100) : null;
});
const decidedAt = computed(() => {
  const at = data.value?.decided_at;
  return at ? new Date(at).toLocaleString() : '';
});

const load = async () => {
  loading.value = true;
  failed.value = false;
  try {
    const res = await brainGet(accountId.value, 'explain', {
      conversation_id: props.conversationId,
    });
    data.value = res?.ok ? res.explanation : null;
    failed.value = !res?.ok;
  } catch (e) {
    failed.value = true;
  } finally {
    loading.value = false;
  }
};

const toggle = () => {
  open.value = !open.value;
  if (open.value) load();
};

watch(
  () => props.conversationId,
  () => {
    open.value = false;
    data.value = null;
  }
);
</script>

<template>
  <div class="tz-why">
    <button
      type="button"
      class="tz-why-toggle"
      :aria-expanded="open"
      @click="toggle"
    >
      {{ open ? $t('TOLZAR_WHY.HIDE') : $t('TOLZAR_WHY.SHOW') }}
    </button>
    <div v-if="open" class="tz-why-body">
      <p v-if="loading" class="tz-why-muted">{{ $t('TOLZAR_WHY.LOADING') }}</p>
      <p v-else-if="failed || !data" class="tz-why-muted">
        {{ $t('TOLZAR_WHY.NONE') }}
      </p>
      <template v-else>
        <p class="tz-why-line">
          {{ $t('TOLZAR_WHY.DECIDED', { at: decidedAt }) }}
          <template v-if="data.route">
            · {{ $t('TOLZAR_WHY.ROUTE', { team: data.route }) }}
          </template>
          <template v-if="confidence !== null">
            · {{ $t('TOLZAR_WHY.SURE', { pct: confidence }) }}
          </template>
        </p>
        <p class="tz-why-h">{{ $t('TOLZAR_WHY.BASED_ON') }}</p>
        <p v-if="!basedOn.length" class="tz-why-muted">
          {{ $t('TOLZAR_WHY.NO_SOURCE') }}
        </p>
        <ul v-else class="tz-why-list">
          <li v-for="src in basedOn" :key="src.ref">
            <span class="tz-why-ref">{{ src.ref }}</span>
            <a
              v-if="src.url && src.url.startsWith('http')"
              :href="src.url"
              target="_blank"
              rel="noopener noreferrer nofollow"
              >{{ src.title || src.snippet }}</a
            >
            <span v-else>{{ src.title || src.snippet }}</span>
            <span v-if="src.snippet && src.title" class="tz-why-muted">
              — {{ src.snippet }}
            </span>
          </li>
        </ul>
        <p class="tz-why-h">{{ $t('TOLZAR_WHY.CHECKS') }}</p>
        <ul class="tz-why-list">
          <li v-for="c in checks" :key="c.check">
            <span :class="c.passed ? 'tz-why-ok' : 'tz-why-bad'">
              {{ c.passed ? '✓' : '✗' }}
            </span>
            {{ $t(`TOLZAR_WHY.CHECK.${c.check.toUpperCase()}`) }}
          </li>
        </ul>
        <p v-if="data.replaced_by_safe_reply" class="tz-why-muted">
          {{ $t('TOLZAR_WHY.REPLACED') }}
        </p>
      </template>
    </div>
  </div>
</template>

<style scoped>
.tz-why {
  margin-top: 8px;
}
.tz-why-toggle {
  font-size: 12px;
  font-weight: 500;
  color: rgb(var(--blue-9));
}
.tz-why-toggle:hover {
  text-decoration: underline;
}
.tz-why-body {
  margin-top: 6px;
  padding: 8px 10px;
  border-radius: 8px;
  background: rgb(var(--slate-3));
  font-size: 12px;
  line-height: 1.5;
}
.tz-why-h {
  margin: 8px 0 2px;
  font-weight: 600;
}
.tz-why-line {
  margin: 0;
}
.tz-why-list {
  margin: 0;
  padding: 0;
  list-style: none;
}
.tz-why-list li {
  margin: 2px 0;
  word-break: break-word;
}
.tz-why-ref {
  display: inline-block;
  min-width: 26px;
  font-weight: 600;
}
.tz-why-muted {
  opacity: 0.7;
  margin: 0;
}
.tz-why-ok {
  color: rgb(var(--teal-11));
  font-weight: 700;
}
.tz-why-bad {
  color: rgb(var(--ruby-11));
  font-weight: 700;
}
</style>
