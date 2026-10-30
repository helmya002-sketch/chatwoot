import { frontendURL } from '../../../helper/URLHelper';
import TolzarDashboard from './TolzarDashboard.vue';
import TolzarPipeline from './TolzarPipeline.vue';
import TolzarAIAgents from './TolzarAIAgents.vue';
import TolzarWorkflows from './TolzarWorkflows.vue';
import TolzarReports from './TolzarReports.vue';
import TolzarSettingsHub from './TolzarSettingsHub.vue';
import TolzarOnboarding from './TolzarOnboarding.vue';
import TolzarAgency from './TolzarAgency.vue';
import TolzarResults from './TolzarResults.vue';

const PERMS = { permissions: ['administrator', 'agent', 'custom_role'] };
// AI Agents and Workflows: every write (and the test chat) is admin/Owner-only on the proxy, so the
// pages are admin-only too; the sidebar reads this meta and hides them for everyone else.
const ADMIN = { permissions: ['administrator'] };

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
    meta: ADMIN,
  },
  {
    path: frontendURL('accounts/:accountId/tolzar-reports'),
    name: 'tolzar_reports',
    component: TolzarReports,
    meta: ADMIN,
  },
  {
    path: frontendURL('accounts/:accountId/tolzar-results'),
    name: 'tolzar_results',
    component: TolzarResults,
    meta: ADMIN,
  },
  {
    path: frontendURL('accounts/:accountId/tolzar-settings'),
    name: 'tolzar_settings',
    component: TolzarSettingsHub,
    meta: ADMIN,
  },
  {
    path: frontendURL('accounts/:accountId/tolzar-onboarding'),
    name: 'tolzar_onboarding',
    component: TolzarOnboarding,
    meta: ADMIN,
  },
  {
    path: frontendURL('accounts/:accountId/tolzar-agency'),
    name: 'tolzar_agency',
    component: TolzarAgency,
    meta: ADMIN,
  },
  {
    path: frontendURL('accounts/:accountId/workflows'),
    name: 'tolzar_workflows',
    component: TolzarWorkflows,
    meta: ADMIN,
  },
];
