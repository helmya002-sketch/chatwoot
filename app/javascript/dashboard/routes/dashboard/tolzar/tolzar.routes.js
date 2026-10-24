import { frontendURL } from '../../../helper/URLHelper';
import TolzarDashboard from './TolzarDashboard.vue';
import TolzarAIAgents from './TolzarAIAgents.vue';
import TolzarWorkflows from './TolzarWorkflows.vue';

const PERMS = { permissions: ['administrator', 'agent', 'custom_role'] };

export const routes = [
  {
    path: frontendURL('accounts/:accountId/tolzar-dashboard'),
    name: 'tolzar_dashboard',
    component: TolzarDashboard,
    meta: PERMS,
  },
  {
    path: frontendURL('accounts/:accountId/ai-agents'),
    name: 'tolzar_ai_agents',
    component: TolzarAIAgents,
    meta: PERMS,
  },
  {
    path: frontendURL('accounts/:accountId/workflows'),
    name: 'tolzar_workflows',
    component: TolzarWorkflows,
    meta: PERMS,
  },
];
