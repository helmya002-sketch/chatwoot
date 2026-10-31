# Tolzar saved-reply starter set (round 4, c93), for TOLZAR_INBOX_TOOLS_ACCOUNTS workspaces: everyday replies any
# business can edit, with Chatwoot's own variables ({{contact.first_name}}, {{agent.name}}); [bracketed] parts are
# for the business to fill in once. Adding them is an administrator's click; a short code that already exists is
# never touched, so it can run twice safely.
module Tolzar::CannedStarters
  SET = {
    'hello' => 'Hi {{contact.first_name}}, thanks for getting in touch! How can I help you today?',
    'hours' => "We're open [your opening hours]. Outside these hours we read every message and reply first thing.",
    'prices' => 'Here are our current prices: [your price list]. Tell me what you need and I can put together a quote.',
    'followup' => 'Hi {{contact.first_name}}, just checking in: did you have a chance to look at this? Happy to help with any question.',
    'confirmed' => "Great news, {{contact.first_name}}: you're confirmed. You'll find all the details in the confirmation we sent.",
    'handover' => "I'm passing you to a colleague who knows this best. They'll reply here shortly.",
    'thanks' => 'Thank you, {{contact.first_name}}! If anything else comes up, just write to us here. {{agent.name}}'
  }.freeze

  module_function

  def enabled?(account_id)
    ENV.fetch('TOLZAR_INBOX_TOOLS_ACCOUNTS', '').split(',').filter_map { |v| Integer(v.strip, exception: false) }
       .include?(account_id.to_i)
  end

  # Adds the missing ones; returns the short codes added.
  def add_missing!(account)
    existing = account.canned_responses.pluck(:short_code).to_set
    SET.reject { |code, _| existing.include?(code) }.map do |code, content|
      account.canned_responses.create!(short_code: code, content: content)
      code
    end
  end
end
