# Tolzar booking-system connector: a workspace's external booking system (adapter + API base + token). Only for
# TOLZAR_BOOKING_CONNECTOR workspaces. Tolzar reads (catalog, schedule, a guest's bookings) and, on a staff
# member's click, creates a DRAFT booking there; it never confirms, prices or charges. The token is encrypted and
# write-only. Calls go through SafeFetch (no private-network targets).
class Tolzar::BookingConnector < ApplicationRecord
  self.table_name = 'tolzar_booking_connectors'

  ADAPTERS = { 'dwt' => 'Tolzar::BookingConnectors::Dwt' }.freeze

  belongs_to :account
  encrypts :token

  validates :adapter, inclusion: { in: ADAPTERS.keys }
  validates :base_url, format: { with: %r{\Ahttps://[a-z0-9.-]+(:\d+)?(/[\w./-]*)?(\?[\w=&.-]*)?\z}i, message: 'must be an https URL' }
  validates :token, presence: true

  def self.enabled?(account_id)
    ENV.fetch('TOLZAR_BOOKING_CONNECTOR', '').split(',').filter_map { |v| Integer(v.strip, exception: false) }
       .include?(account_id.to_i)
  end

  def client
    ADAPTERS.fetch(adapter).constantize.new(base_url: base_url, token: token)
  end

  # A read call that proves the base and token (the catalog); the outcome is kept, never the token.
  def test!(now: Time.current)
    items = client.catalog
    update!(last_test_at: now, last_test_ok: true, last_error: nil)
    { ok: true, catalog: items.size }
  rescue StandardError => e
    update!(last_test_at: now, last_test_ok: false, last_error: e.message.to_s.first(200))
    { ok: false, error: last_error }
  end

  def view
    { adapter: adapter, base_url: base_url, token: token.present? ? 'set' : 'not set', last_test_at: last_test_at,
      last_test_ok: last_test_ok, last_error: last_error }
  end
end
