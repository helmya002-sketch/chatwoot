import { frontendURL } from '../../../helper/URLHelper';
import TolzarDashboard from './TolzarDashboard.vue';

export const routes = [
  {
    path: frontendURL('accounts/:accountId/tolzar-dashboard'),
    name: 'tolzar_dashboard',
    component: TolzarDashboard,
    meta: {
      permissions: ['administrator', 'agent', 'custom_role'],
    },
  },
];
