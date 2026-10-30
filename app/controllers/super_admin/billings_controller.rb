# Tolzar billing v1 (manual until XPay checkout): every workspace's plan, state, trial end, paid-until and
# seats in one page. A super admin sets a paid plan until a date (resumes a paused workspace at once) or
# extends a trial. Every change is logged with the acting super admin. Generic: no business names in code.
class SuperAdmin::BillingsController < SuperAdmin::ApplicationController
  def show
    @rows = Account.order(:id).map { |account| [account, Tolzar::Subscription.for(account)] }
    @enforced = Tolzar::Subscription.enforced?
  end

  def set_plan
    subscription = Tolzar::Subscription.for(Account.find(params[:account_id]))
    plan = params[:plan].to_s
    paid_until = parse_date(params[:paid_until])
    unless Tolzar::Subscription::PAID.include?(plan) && paid_until
      return redirect_to super_admin_billing_path, alert: t('super_admin.billing.invalid')
    end

    subscription.activate!(plan: plan, paid_until: paid_until.end_of_day, by: nil,
                           seat_limit: params[:seat_limit].presence&.to_i, currency: params[:currency].presence)
    log_action("set plan #{plan} until #{paid_until} for account #{subscription.account_id}")
    redirect_to super_admin_billing_path, notice: t('super_admin.billing.saved')
  rescue ActiveRecord::RecordInvalid => e
    redirect_to super_admin_billing_path, alert: e.record.errors.full_messages.to_sentence
  end

  def extend_trial
    subscription = Tolzar::Subscription.for(Account.find(params[:account_id]))
    days = params[:days].to_i
    return redirect_to super_admin_billing_path, alert: t('super_admin.billing.invalid') unless days.between?(1, 60)

    subscription.extend_trial!(days: days)
    log_action("extended trial by #{days} days for account #{subscription.account_id}")
    redirect_to super_admin_billing_path, notice: t('super_admin.billing.saved')
  end

  private

  def parse_date(value)
    Date.iso8601(value.to_s)
  rescue ArgumentError
    nil
  end

  def log_action(message)
    Rails.logger.info("[SuperAdmin] billing #{message} (actor_id=#{current_super_admin.id})")
  end
end
