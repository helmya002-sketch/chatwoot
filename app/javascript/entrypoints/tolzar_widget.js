// Tolzar widget: the iframe app's entry (WidgetsController renders widgets/tolzar for TOLZAR_OWN_WIDGET_ACCOUNTS).
// The page puts the visitor's config in a JSON script tag (never inline JS), read here.
import '../tolzar-widget/widget.css';
import { WidgetApp } from '../tolzar-widget/app';

const node = document.getElementById('tz-widget-config');
const root = document.getElementById('tz-widget');
if (node && root) {
  const config = JSON.parse(node.textContent || '{}');
  new WidgetApp({ config, root }).start();
}
