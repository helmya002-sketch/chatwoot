# Tolzar Control Center: the badge tone for a workspace's billing state (Tolzar::Subscription#state).
module Tolzar::ControlCenterHelper
  TONES = { 'trialing' => :info, 'active' => :success, 'paused' => :warning, 'purge_scheduled' => :danger,
            'purged' => :neutral, 'none' => :neutral }.freeze

  module_function

  def state_tone(state)
    TONES.fetch(state.to_s, :neutral)
  end
end
