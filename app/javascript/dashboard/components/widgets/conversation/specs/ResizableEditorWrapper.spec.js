import { mount } from '@vue/test-utils';
import { nextTick } from 'vue';
import ResizableEditorWrapper from '../ResizableEditorWrapper.vue';

vi.mock('@vueuse/core', () => ({
  useEventListener: (target, event, handler, options) =>
    target.addEventListener(event, handler, options),
}));

// Tolzar (owner's ask, 31 Oct): the composer starts at ~3 lines, its max is 40% of the pane, a drag never
// collapses it, and the dragged height is remembered.
const CONTAINER_HEIGHT = 800;
const DEFAULT_HEIGHT = 72;
const MIN_HEIGHT = 48;
const MAX_HEIGHT = CONTAINER_HEIGHT * 0.4;
const START_Y = 500;

const mountWrapper = () =>
  mount(ResizableEditorWrapper, {
    props: { containerHeight: CONTAINER_HEIGHT },
    slots: { default: '<div class="resizable-editor-body" />' },
    attachTo: document.body,
  });

const editorHeight = wrapper =>
  parseInt(wrapper.element.style.getPropertyValue('--editor-height'), 10);
const maxAllowed = wrapper =>
  parseInt(wrapper.element.style.getPropertyValue('--editor-max-allowed'), 10);

// Positive distance drags the handle down, shrinking the editor.
const dragBy = async (wrapper, distance) => {
  document.dispatchEvent(
    new MouseEvent('mousemove', { clientY: START_Y + distance })
  );
  await nextTick();
};

const releaseDrag = async () => {
  document.dispatchEvent(new MouseEvent('mouseup'));
  await nextTick();
};

describe('ResizableEditorWrapper', () => {
  let wrapper;

  beforeEach(async () => {
    window.localStorage.clear();
    wrapper = mountWrapper();
    await wrapper
      .find('.cursor-row-resize')
      .trigger('mousedown', { clientY: START_Y });
  });

  afterEach(() => {
    wrapper.unmount();
  });

  it('starts at about three lines and stops shrinking at the minimum', async () => {
    expect(editorHeight(wrapper)).toBe(DEFAULT_HEIGHT);
    await dragBy(wrapper, 400);
    expect(editorHeight(wrapper)).toBe(MIN_HEIGHT);
  });

  it('never collapses on a drag, however far it is pulled', async () => {
    await dragBy(wrapper, 2000);
    await releaseDrag();
    expect(wrapper.emitted('collapse')).toBeUndefined();
    expect(editorHeight(wrapper)).toBe(MIN_HEIGHT);
  });

  it('grows up to 40% of the pane, no further', async () => {
    await dragBy(wrapper, -2000);
    expect(editorHeight(wrapper)).toBeLessThanOrEqual(MAX_HEIGHT);
    expect(maxAllowed(wrapper)).toBeLessThanOrEqual(MAX_HEIGHT);
  });

  it('remembers the dragged height', async () => {
    await dragBy(wrapper, -60);
    await releaseDrag();
    expect(Number(window.localStorage.getItem('tz-editor-height'))).toBe(
      DEFAULT_HEIGHT + 60
    );
    wrapper.unmount();
    wrapper = mountWrapper();
    await nextTick();
    expect(editorHeight(wrapper)).toBe(DEFAULT_HEIGHT + 60);
  });

  it('collapses only through the explicit collapse action', async () => {
    await releaseDrag();
    wrapper.vm.collapseEditor();
    expect(wrapper.emitted('collapse')).toHaveLength(1);
  });
});
