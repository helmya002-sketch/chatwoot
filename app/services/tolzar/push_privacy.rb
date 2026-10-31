# Tolzar push on the phone (round 4, c64), for TOLZAR_PWA_ACCOUNTS workspaces:
#   title   short and private: who it is about, never what they wrote ("New message from Mona"); no body text
#   quiet   each person's quiet hours (Profile > Notifications), in their own time zone: no push in between
# Other workspaces keep the existing pushes unchanged.
module Tolzar::PushPrivacy
  KEY = 'tolzar_quiet_hours'
  TIME = /\A([01]\d|2[0-3]):[0-5]\d\z/

  module_function

  def on?(account_id)
    ENV.fetch('TOLZAR_PWA_ACCOUNTS', '').split(',').filter_map { |v| Integer(v.strip, exception: false) }
       .include?(account_id.to_i)
  end

  def title(notification)
    conversation = notification.conversation
    who = conversation&.contact&.name.presence || I18n.t('tolzar.push.someone')
    case notification.notification_type
    when 'conversation_creation' then I18n.t('tolzar.push.new_conversation', name: who)
    when 'conversation_assignment' then I18n.t('tolzar.push.assigned', name: who)
    when 'conversation_mention' then I18n.t('tolzar.push.mention', name: mention_by(notification))
    when 'assigned_conversation_new_message', 'participating_conversation_new_message'
      I18n.t('tolzar.push.new_message', name: who)
    else I18n.t('tolzar.push.update', name: who)
    end
  end

  # The person who mentioned you: the sender of the message that carries the mention.
  def mention_by(notification)
    actor = notification.secondary_actor
    name = actor.respond_to?(:sender) ? actor.sender&.name : nil
    name.presence || I18n.t('tolzar.push.teammate')
  end

  # {on, from "HH:MM", to "HH:MM", tz IANA}; overnight ranges (22:00 to 07:00) work; anything malformed is not quiet.
  def quiet?(user, now = Time.current)
    q = (user.ui_settings || {})[KEY]
    return false unless q.is_a?(Hash) && ActiveModel::Type::Boolean.new.cast(q['on'])
    return false unless q['from'].to_s.match?(TIME) && q['to'].to_s.match?(TIME)

    zone = ActiveSupport::TimeZone[q['tz'].to_s] || Time.zone
    minute = ->(hhmm) { hhmm.split(':').map(&:to_i).then { |h, m| (h * 60) + m } }
    local = now.in_time_zone(zone)
    current = (local.hour * 60) + local.min
    from = minute.call(q['from'])
    to = minute.call(q['to'])
    return false if from == to

    from < to ? current.between?(from, to - 1) : (current >= from || current < to)
  end
end
