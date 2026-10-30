<script setup>
// Tolzar Workflows: one list of steps on the canvas. A branch renders its Yes / No lists with
// this same component, so branches can nest (the brain runs any depth). Branch arms are
// normalised before render (tolzarWorkflows.normaliseBranches), never created here.
import { stepMeta, stepSummary } from './tolzarWorkflows';
import { TONE_WARN } from './settings/tzClasses';

defineProps({
  steps: { type: Array, required: true },
  selected: { type: Object, default: null },
  depth: { type: Number, default: 0 },
});
const emit = defineEmits(['select', 'add', 'remove']);
</script>

<template>
  <div class="flex flex-col items-center">
    <template v-for="(node, i) in steps" :key="node.id">
      <span class="tz-wire" />
      <button
        type="button"
        class="tz-add-dot text-n-brand"
        :title="$t('TOLZAR_WORKFLOWS.ADD_HERE')"
        :aria-label="$t('TOLZAR_WORKFLOWS.ADD_HERE')"
        @click="emit('add', steps, i)"
      >
        <span class="i-lucide-plus size-3" />
      </button>
      <span class="tz-wire" />
      <div
        role="button"
        tabindex="0"
        class="overflow-hidden rounded-xl border border-t-[3px] shadow-sm cursor-pointer bg-n-solid-1 focus-visible:ring-2 focus-visible:ring-n-brand outline-none"
        :class="[
          depth ? 'w-[210px]' : 'w-[250px]',
          stepMeta(node.type).top,
          selected === node ? 'border-n-brand ring-2 ring-n-brand/20' : 'border-n-weak',
        ]"
        :aria-pressed="selected === node"
        @click="emit('select', node)"
        @keydown.enter.prevent="emit('select', node)"
        @keydown.space.prevent="emit('select', node)"
      >
        <div class="flex gap-2 items-center px-3 py-2 border-b border-n-weak">
          <span :class="[stepMeta(node.type).icon, stepMeta(node.type).text]" class="size-4" />
          <span class="flex-1 text-[13px] font-bold truncate text-n-slate-12">{{
            $t(stepMeta(node.type).label)
          }}</span>
          <span
            v-if="node.type === 'send_message'"
            class="px-1.5 text-[10px] font-semibold rounded-full text-n-brand bg-n-brand/10"
          >
            {{ $t('TOLZAR_WORKFLOWS.SHADOW_NOTE') }}
          </span>
          <button
            type="button"
            class="grid place-content-center rounded transition-colors size-5 text-n-slate-9 hover:text-n-ruby-11 hover:bg-n-alpha-2"
            :aria-label="$t('TOLZAR_WORKFLOWS_UI.REMOVE_STEP')"
            :title="$t('TOLZAR_WORKFLOWS_UI.REMOVE_STEP')"
            @click.stop="emit('remove', steps, i)"
          >
            <span class="i-lucide-x size-3.5" />
          </button>
        </div>
        <div class="px-3 py-1.5 text-xs truncate text-n-slate-10" :title="stepSummary(node)">
          {{ stepSummary(node) || '—' }}
        </div>
      </div>
      <template v-if="node.type === 'branch'">
        <span class="w-0.5 h-3 bg-n-amber-9" />
        <div class="flex flex-wrap gap-4 justify-center items-start">
          <div
            v-for="arm in ['then', 'else']"
            :key="arm"
            class="flex flex-col items-center min-w-[200px]"
          >
            <span class="px-2.5 py-0.5 text-[11px] font-bold rounded-full" :class="TONE_WARN">{{
              arm === 'then' ? $t('TOLZAR_WORKFLOWS.YES') : $t('TOLZAR_WORKFLOWS.NO')
            }}</span>
            <WorkflowSteps
              :steps="node.config[arm]"
              :selected="selected"
              :depth="depth + 1"
              @select="n => emit('select', n)"
              @add="(list, at) => emit('add', list, at)"
              @remove="(list, at) => emit('remove', list, at)"
            />
          </div>
        </div>
      </template>
    </template>
    <span class="tz-wire" />
    <button
      type="button"
      class="inline-flex gap-1 items-center px-3 py-1.5 text-xs font-semibold rounded-lg border border-dashed transition-colors cursor-pointer border-n-strong text-n-brand bg-n-solid-1 hover:bg-n-alpha-1"
      @click="emit('add', steps, steps.length)"
    >
      <span class="i-lucide-plus size-3" /> {{ $t('TOLZAR_WORKFLOWS.ADD_STEP') }}
    </button>
  </div>
</template>

<style scoped>
.tz-wire {
  width: 2px;
  height: 0.75rem;
  background: rgb(var(--border-strong));
}
.tz-add-dot {
  display: grid;
  place-content: center;
  width: 20px;
  height: 20px;
  background: rgb(var(--solid-1));
  border: 1px dashed rgb(var(--border-strong));
  border-radius: 9999px;
  cursor: pointer;
}
</style>
