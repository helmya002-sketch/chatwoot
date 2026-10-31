# Tolzar brain read user (round 4, c100; Server ops 31 Oct): the "Tolzar Brain" user the brain reads with
# (TOLZAR_BRAIN_USER_IDS, owner-approved; agent role, no usable password) needs to be a member of every inbox it
# reads, and must never be given a customer's conversation.
# - add_to_inbox(inbox): on a new inbox, each listed user who is in that workspace becomes an inbox member.
# - assignable?(user_id): false for a listed user, so round robin and the assignee list skip them.
# Unset (the default) = nothing happens.
module Tolzar::BrainUsers
  module_function

  def ids
    ENV.fetch('TOLZAR_BRAIN_USER_IDS', '').split(',').filter_map { |v| Integer(v.strip, exception: false) }
  end

  def assignable?(user_id)
    !ids.include?(user_id.to_i)
  end

  def add_to_inbox(inbox)
    wanted = ids
    return if wanted.empty?

    in_workspace = inbox.account.account_users.where(user_id: wanted).pluck(:user_id)
    (in_workspace - inbox.inbox_members.pluck(:user_id)).each do |user_id|
      inbox.inbox_members.create!(user_id: user_id)
    end
  rescue ActiveRecord::ActiveRecordError => e
    Rails.logger.error("[Tolzar] brain user: inbox #{inbox.id} membership failed: #{e.class}")
  end
end
