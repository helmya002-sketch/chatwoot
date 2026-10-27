import { frontendURL } from '../../../helper/URLHelper';
import TolzarDashboard from './TolzarDashboard.vue';
import TolzarPipeline from './TolzarPipeline.vue';
import TolzarAIAgents from './TolzarAIAgents.vue';
import TolzarWorkflows from './TolzarWorkflows.vue';
import TolzarReports from './TolzarReports.vue';

const PERMS = { permissions: ['administrator', 'agent', 'custom_role'] };

export const routes = [
  {
    path: frontendURL('accounts/:accountId/tolzar-dashboard'),
    name: 'tolzar_dashboard',
    component: TolzarDashboard,
    meta: PERMS,
  },
  {
    path: frontendURL('accounts/:accountId/pipeline'),
    name: 'tolzar_pipeline',
    component: TolzarPipeline,
    meta: PERMS,
  },
  {
    path: frontendURL('accounts/:accountId/ai-agents'),
    name: 'tolzar_ai_agents',
    component: TolzarAIAgents,
    meta: PERMS,
  },
  {
    path: frontendURL('accounts/:accountId/tolzar-reports'),
    name: 'tolzar_reports',
    component: TolzarReports,
    meta: { permissions: ['administrator'] },
  },
  {
    path: frontendURL('accounts/:accountId/workflows'),
    name: 'tolzar_workflows',
    component: TolzarWorkflows,
    meta: PERMS,
  },
];
