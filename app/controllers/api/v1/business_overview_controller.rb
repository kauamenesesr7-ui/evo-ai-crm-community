class Api::V1::BusinessOverviewController < Api::V1::BaseController
  def show
    today = Date.current
    month = today.beginning_of_month..today.end_of_month

    success_response(
      data: {
        rentals: {
          upcoming: Rental.where(starts_at: Time.current..).count,
          this_month: Rental.where(starts_at: month.first.beginning_of_day..month.last.end_of_day).count,
          confirmed: Rental.where(status: 'confirmed').count
        },
        finance: {
          receivable: FinancialEntry.where(kind: 'receivable', status: %w[pending overdue]).sum(:amount).to_f,
          payable: FinancialEntry.where(kind: 'payable', status: %w[pending overdue]).sum(:amount).to_f,
          received_this_month: FinancialEntry.where(kind: 'receivable', status: 'paid', paid_on: month).sum(:amount).to_f,
          overdue: FinancialEntry.where(status: 'pending', due_on: ...today).sum(:amount).to_f
        },
        reminders: {
          due: BusinessReminder.where(status: 'pending', remind_at: ..Time.current).count,
          upcoming: BusinessReminder.where(status: 'pending', remind_at: Time.current..7.days.from_now).count
        },
        contracts: {
          draft: Contract.where(status: 'draft').count,
          signed: Contract.where(status: 'signed').count
        }
      },
      message: 'Business overview retrieved successfully'
    )
  end
end
