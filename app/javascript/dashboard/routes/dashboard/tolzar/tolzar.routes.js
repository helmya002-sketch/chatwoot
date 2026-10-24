import { frontendURL } from '../../../helper/URLHelper';
import TolzarDashboard from './TolzarDashboard.vue';
import TolzarAIAgents from './TolzarAIAgents.vue';

export const routes = [
  {
    path: frontendURL('accounts/:accountId/tolzar-dashboard'),
    name: 'tolzar_dashboard',
    component: TolzarDashboard,
    meta: {
      permissions: ['administrator', 'agent', 'custom_role'],
    },
  },
  {
    path: frontendURL('accounts/:accountId/ai-agents'),
    name: 'tolzar_ai_agents',
    component: TolzarAIAgents,
    meta: {
      permissions: ['administrator', 'agent', 'custom_role'],
    },
  },
];
