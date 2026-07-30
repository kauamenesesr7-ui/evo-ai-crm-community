class ApplicationJob < ActiveJob::Base
  attr_accessor :tenant_id

  before_enqueue do |job|
    job.tenant_id ||= Current.tenant_id
  end

  def serialize
    super.merge('tenant_id' => tenant_id)
  end

  def deserialize(job_data)
    super
    self.tenant_id = job_data['tenant_id']
  end

  # https://api.rubyonrails.org/v5.2.1/classes/ActiveJob/Exceptions/ClassMethods.html
  discard_on ActiveJob::DeserializationError do |job, error|
    Rails.logger.info("Skipping #{job.class} with #{
      job.instance_variable_get(:@serialized_arguments)
    } because of ActiveJob::DeserializationError (#{error.message})")
  end

  # EVO-1551 round 4 — root-cause fix.
  # `Current.account` is populated by `EvoAuthConcern` only on the HTTP
  # pipeline. Sidekiq threads inherit nothing, so any job that ends up
  # calling `ContactPiiMasker.account_flag_enabled?` (directly or via a
  # model's `push_event_data`) used to fail-open and ship raw PII.
  # `ContactPiiMasker` keeps a `RuntimeConfig.account` fallback as
  # defence-in-depth, but doing it here once per job avoids re-querying
  # `runtime_configs` on every broadcast inside a fan-out (e.g.
  # `ActionCableBroadcastJob#broadcast_to_members` looping over inbox
  # members) and gives any future code path that reads `Current.account`
  # the correct value for free.
  around_perform do |_job, block|
    needed_account = Current.account.nil?
    if tenant_id.present?
      Current.tenant_id = tenant_id
      Current.tenant = Tenant.find(tenant_id)
      Current.account = Current.tenant.account_payload
    elsif needed_account
      Current.account = RuntimeConfig.account
    end
    block.call
  ensure
    Current.reset
  end
end
