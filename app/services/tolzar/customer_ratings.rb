# Tolzar Results → Customer ratings (round 4, G1): the workspace's CSAT answers over 7 / 30 / 90 days.
#   average / count:  over every rating (1-5) given in the period
#   distribution:     how many of each rating, 1 to 5, zeros included
#   comments:         the latest 10 written comments, with the conversation's number for a link only
# No contact names or contact details leave this service.
class Tolzar::CustomerRatings
  DAYS = [7, 30, 90].freeze
  COMMENTS = 10

  def initialize(account, days: 30, now: Time.current)
    @account = account
    @days = DAYS.include?(days.to_i) ? days.to_i : 30
    @from = now - @days.days
  end

  def report
    counts = responses.group(:rating).count
    total = counts.values.sum
    average = total.zero? ? nil : (counts.sum { |rating, n| rating * n }.to_f / total).round(2)
    { days: @days, average: average, count: total, distribution: (1..5).map { |r| { rating: r, count: counts[r].to_i } },
      comments: comments }
  end

  private

  def responses
    CsatSurveyResponse.where(account_id: @account.id, created_at: @from.., rating: 1..5)
  end

  def comments
    # Joined with conversations, so every column names its table (both have created_at).
    responses.where.not(feedback_message: [nil, '']).joins(:conversation)
             .order('csat_survey_responses.created_at DESC').limit(COMMENTS)
             .pluck('csat_survey_responses.rating', 'csat_survey_responses.feedback_message', 'conversations.display_id',
                    'csat_survey_responses.created_at')
             .map { |rating, text, display_id, at| { rating: rating, text: text, conversation: display_id, at: at.iso8601 } }
  end
end
