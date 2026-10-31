// Tolzar inbox density (owner's ask, 31 Oct: "everything is big so when it's busy you need to scroll a lot").
// Compact is the default: about twice the conversations per screen. The choice is remembered in this browser per
// signed-in user (tz-density:<user id>); "comfortable" brings back the roomier upstream spacing.
import { ref } from 'vue';

export const DENSITIES = ['compact', 'comfortable'];
const KEY_PREFIX = 'tz-density:';

const storageKey = () => {
  const id =
    window.chatwootConfig?.currentUserId || window.currentUser?.id || '';
  return `${KEY_PREFIX}${id}`;
};

const read = () => {
  try {
    const value = window.localStorage.getItem(storageKey());
    return DENSITIES.includes(value) ? value : 'compact';
  } catch (e) {
    return 'compact';
  }
};

export const density = ref(read());

export const setDensity = value => {
  if (!DENSITIES.includes(value)) return;
  density.value = value;
  try {
    window.localStorage.setItem(storageKey(), value);
  } catch (e) {
    // storage blocked: the choice lasts for this page only
  }
};

export const toggleDensity = () =>
  setDensity(density.value === 'compact' ? 'comfortable' : 'compact');
