import { onBeforeUnmount, onMounted } from 'vue';
import { onBeforeRouteLeave } from 'vue-router';

// Stable snapshot of a draft, so `dirty` is a plain string compare and key order can't fool it.
export const snapshot = value => {
  const sort = v => {
    if (Array.isArray(v)) return v.map(sort);
    if (v && typeof v === 'object') {
      return Object.keys(v)
        .sort()
        .reduce((o, k) => {
          if (v[k] !== undefined) o[k] = sort(v[k]);
          return o;
        }, {});
    }
    return v;
  };
  return JSON.stringify(sort(value ?? null));
};

// Protects a page with an editable draft from losing it silently.
//   isDirty: () => boolean
//   confirm: () => Promise<boolean>   (true = leave anyway; usually an UnsavedDialog's ask())
// Returns `guard()`, to call before any in-page navigation (Back, Cancel, picking another record):
//   if (await guard()) { ...leave... }
export function useUnsavedGuard({ isDirty, confirm }) {
  const beforeUnload = e => {
    if (!isDirty()) return undefined;
    e.preventDefault();
    e.returnValue = '';
    return '';
  };
  onMounted(() => window.addEventListener('beforeunload', beforeUnload));
  onBeforeUnmount(() => window.removeEventListener('beforeunload', beforeUnload));
  onBeforeRouteLeave(async () => {
    if (!isDirty()) return true;
    return (await confirm()) === true;
  });
  const guard = async () => !isDirty() || (await confirm()) === true;
  return { guard };
}
