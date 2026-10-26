import { ref, computed, onBeforeUnmount } from 'vue';
import { useUISettings } from 'dashboard/composables/useUISettings';

/**
 * Tolzar #2: a draggable resize handle that persists a pane width per user.
 *
 * `settingKey` is the UISettings key the width is stored under. `min`/`max`
 * clamp the width so the layout can never collapse. The returned `widthStyle`
 * is `{}` until a custom width exists (so the component keeps its default
 * Tailwind width class), then becomes an explicit fixed width.
 */
export function useResizablePane(settingKey, { min = 280, max = 560 } = {}) {
  const { uiSettings, updateUISettings } = useUISettings();

  // Width set live during (and kept after) a drag, for this session.
  const dragWidth = ref(null);

  // The persisted width, read reactively so it applies once UISettings load.
  const storedWidth = computed(() => {
    const s = Number(uiSettings.value?.[settingKey]);
    return Number.isFinite(s) && s >= min && s <= max ? s : null;
  });

  const effectiveWidth = computed(() => dragWidth.value ?? storedWidth.value);

  const widthStyle = computed(() => {
    if (!effectiveWidth.value) return {};
    const w = `${effectiveWidth.value}px`;
    return { width: w, minWidth: w, maxWidth: w, flex: '0 0 auto' };
  });

  let startX = 0;
  let startW = 0;
  let dir = 1; // +1 widen when dragging right (end edge); -1 for the start edge
  let active = false;

  const onMove = e => {
    if (!active) return;
    const next = startW + (e.clientX - startX) * dir;
    dragWidth.value = Math.max(min, Math.min(max, next));
  };

  const onUp = () => {
    if (!active) return;
    active = false;
    document.removeEventListener('pointermove', onMove);
    document.removeEventListener('pointerup', onUp);
    document.body.style.userSelect = '';
    document.body.style.cursor = '';
    if (dragWidth.value) {
      updateUISettings({ [settingKey]: Math.round(dragWidth.value) });
    }
  };

  const startDrag = (e, edge = 'end') => {
    e.preventDefault();
    dir = edge === 'start' ? -1 : 1;
    startX = e.clientX;
    const paneEl = e.currentTarget?.parentElement;
    startW =
      effectiveWidth.value ||
      paneEl?.getBoundingClientRect().width ||
      min;
    active = true;
    document.body.style.userSelect = 'none';
    document.body.style.cursor = 'col-resize';
    document.addEventListener('pointermove', onMove);
    document.addEventListener('pointerup', onUp);
  };

  // Double-click the handle to return to the default width.
  const reset = () => {
    dragWidth.value = null;
    updateUISettings({ [settingKey]: 0 });
  };

  onBeforeUnmount(() => {
    document.removeEventListener('pointermove', onMove);
    document.removeEventListener('pointerup', onUp);
  });

  return { widthStyle, startDrag, reset };
}
