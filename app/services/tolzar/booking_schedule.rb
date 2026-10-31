# Tolzar bookings schedule (round 4, c102): who and what is busy per day, from the "resource" each booking line names
# (a boat, a room, a guide; free text, staff-entered). Today and the next 14 days, draft and confirmed bookings
# (cancelled and completed left out). A resource used by two different bookings on the same day is a clash: it is
# flagged for staff to look at, never changed by itself.
class Tolzar::BookingSchedule
  DAYS = 14

  def initialize(account, today: Date.current)
    @account = account
    @today = today
  end

  def report
    uses = bookings.flat_map { |booking| uses_of(booking) }
    days = (@today..(@today + DAYS)).map do |day|
      on_day = uses.select { |u| u[:from] <= day && u[:until] >= day }
      by_resource = on_day.group_by { |u| u[:resource].downcase }.values.map do |list|
        { resource: list.first[:resource], clash: list.map { |u| u[:booking_id] }.uniq.size > 1,
          items: list.map { |u| u.slice(:booking_id, :status, :description) } }
      end
      { date: day.iso8601, resources: by_resource.sort_by { |r| r[:resource].downcase } }
    end
    { days: days, clashes: days.sum { |d| d[:resources].count { |r| r[:clash] } } }
  end

  private

  def bookings
    Tolzar::Booking.where(account_id: @account.id, status: %w[draft confirmed])
                   .where(starts_on: ..(@today + DAYS)).where('COALESCE(ends_on, starts_on) >= ?', @today).order(:id).limit(2000)
  end

  def uses_of(booking)
    Array(booking.data['lines']).filter_map do |line|
      next unless line.is_a?(Hash) && line['resource'].to_s.strip.present?

      from = parse(line['date']) || booking.starts_on
      next unless from

      { booking_id: booking.id, status: booking.status, description: line['description'].to_s.first(80),
        resource: line['resource'].to_s.strip.first(60), from: from, until: [parse(line['until']) || from, from].max }
    end
  end

  def parse(value)
    Date.iso8601(value.to_s) if value.present?
  rescue ArgumentError
    nil
  end
end
