# Tolzar's own help (round 4, c67: never depend on Chatwoot). Every "Learn more" link points at /tz/help/<topic>,
# which opens our help-centre article for it (help/en, imported into the TOLZAR_HELP_PORTAL portal, default "help").
# Articles are found by their title, because an imported article's slug carries a timestamp. A topic without a
# published article, or a portal that is not there, opens the help centre's home instead. Only our own paths are
# returned, never another host.
module Tolzar::HelpTopics
  TOPICS = {
    'getting_started' => 'Getting started with Tolzar',
    'shadow' => 'How Shadow mode works',
    'ai_agents' => 'Create an AI agent from a template',
    'workflows' => 'Workflows: the basics',
    'broadcasts' => 'Broadcasts',
    'sla' => 'Response times (SLA)',
    'languages' => 'Languages and translation',
    'roles' => 'Roles: Owner, Manager, Agent',
    'audit' => 'Audit log and exporting your data',
    'security' => 'Two-factor sign-in and security',
    'telegram_line' => 'Telegram and LINE',
    'import' => 'Import your contacts (CSV)',
    'workspace' => 'Workspace settings',
    'results' => 'Results: what the AI is doing for you',
    'going_live' => 'Going live and the kill switch',
    'documents' => 'Vouchers, quotes and booking confirmations',
    'bookings' => 'Bookings',
    'top_bar' => 'The top bar and "My day"',
    'phone' => 'Tolzar on your phone',
    'widget' => 'The website chat widget',
    'reply_windows' => 'Replying on Messenger and Instagram: the 24-hour and 7-day windows'
  }.freeze

  module_function

  def portal_slug
    slug = ENV.fetch('TOLZAR_HELP_PORTAL', 'help').to_s
    slug.match?(/\A[a-z0-9_-]{1,60}\z/i) ? slug : 'help'
  end

  def home
    "/hc/#{portal_slug}/en"
  end

  def path_for(topic)
    title = TOPICS[topic.to_s]
    return home if title.nil?

    portal = Portal.find_by(slug: portal_slug)
    article = portal&.articles&.published&.where(locale: 'en')&.find_by(title: title)
    article ? "/hc/#{portal.slug}/articles/#{article.slug}" : home
  end
end
