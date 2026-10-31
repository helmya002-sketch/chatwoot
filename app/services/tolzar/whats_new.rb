# Tolzar "What's new" (round 4, c90): the release notes in config/tolzar/whats_new.yml, filtered for one workspace: an
# item with a `switch` is shown only where that TOLZAR_*_ACCOUNTS switch lists the workspace. Releases left with no
# item are dropped.
module Tolzar::WhatsNew
  FILE = Rails.root.join('config/tolzar/whats_new.yml')

  module_function

  def for(account_id, entries = YAML.safe_load(FILE.read))
    Array(entries).filter_map do |release|
      items = Array(release['items']).select { |item| visible?(item['switch'], account_id) }
                                     .map { |item| item.slice('title', 'text') }
      { release: release['release'].to_s, date: release['date'].to_s, items: items } if items.any?
    end
  end

  def visible?(switch, account_id)
    return true if switch.blank?
    return false unless switch.to_s.match?(/\ATOLZAR_[A-Z0-9_]+_ACCOUNTS\z/)

    ENV.fetch(switch.to_s, '').split(',').filter_map { |v| Integer(v.strip, exception: false) }.include?(account_id.to_i)
  end
end
