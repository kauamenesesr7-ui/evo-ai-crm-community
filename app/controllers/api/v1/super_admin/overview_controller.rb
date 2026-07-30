class Api::V1::SuperAdmin::OverviewController < Api::V1::BaseController
  before_action :require_super_admin!

  def show
    success_response(data: {
      summary: summary,
      tenants: tenant_rows,
      health: health,
      capacity: capacity,
      recent_activity: recent_activity
    })
  end

  private

  def require_super_admin!
    return if Current.evo_role_key == 'super_admin'

    error_response(
      ApiErrorCodes::FORBIDDEN,
      'Exclusive access for the AppEventos super administrator',
      status: :forbidden
    )
  end

  def summary
    {
      tenants: Tenant.unscoped.count,
      active_tenants: Tenant.unscoped.where(status: 'active').count,
      users: User.unscoped.count,
      whatsapp_connections: whatsapp_scope.count,
      conversations: Conversation.unscoped.count,
      messages: Message.unscoped.count,
      ai_agents: AgentBot.unscoped.count,
      storage_attachments: Attachment.unscoped.count
    }
  end

  def tenant_rows
    users_by_tenant = User.unscoped.group(:tenant_id).count
    inboxes_by_tenant = Inbox.unscoped.group(:tenant_id).count
    conversations_by_tenant = Conversation.unscoped.group(:tenant_id).count
    messages_by_tenant = Message.unscoped.group(:tenant_id).count

    Tenant.unscoped.order(created_at: :desc).limit(100).map do |tenant|
      {
        id: tenant.id,
        name: tenant.name,
        slug: tenant.slug,
        status: tenant.status,
        subscription_status: tenant.subscription_status,
        trial_ends_at: tenant.trial_ends_at,
        subscription_ends_at: tenant.subscription_ends_at,
        usage: {
          users: users_by_tenant[tenant.id].to_i,
          inboxes: inboxes_by_tenant[tenant.id].to_i,
          conversations: conversations_by_tenant[tenant.id].to_i,
          messages: messages_by_tenant[tenant.id].to_i
        }
      }
    end
  end

  def health
    database_ok = ActiveRecord::Base.connection.select_value('SELECT 1').to_i == 1
    redis_ok = $alfred.with { |connection| connection.ping } == 'PONG'

    {
      api: { status: 'operational', checked_at: Time.current },
      database: { status: database_ok ? 'operational' : 'degraded' },
      redis_and_queues: { status: redis_ok ? 'operational' : 'degraded' },
      whatsapp: {
        status: whatsapp_scope.exists? ? 'connected' : 'awaiting_connection',
        connections: whatsapp_scope.count
      }
    }
  rescue StandardError => e
    Rails.logger.warn("Superadmin health probe failed: #{e.class}: #{e.message}")
    { api: { status: 'operational' }, dependencies: { status: 'degraded' } }
  end

  def capacity
    {
      current_server: { vcpu: 1, memory_gb: 3.8, observed_memory_percent: 82 },
      safe_commercial_range: { minimum_tenants: 3, maximum_tenants: 5 },
      light_load_uncommitted_ceiling: 10,
      recommended_for_25_tenants: { vcpu: 4, memory_gb: 8 },
      service_level_targets: {
        api_p95_ms: 800,
        webhook_p95_ms: 2000,
        maximum_queue_delay_seconds: 30,
        maximum_sustained_memory_percent: 80
      }
    }
  end

  def recent_activity
    {
      messages_last_24h: Message.unscoped.where(created_at: 24.hours.ago..).count,
      conversations_last_24h: Conversation.unscoped.where(created_at: 24.hours.ago..).count,
      rentals_last_30d: Rental.unscoped.where(created_at: 30.days.ago..).count
    }
  end

  def whatsapp_scope
    Inbox.unscoped.where(channel_type: 'Channel::Whatsapp')
  end
end
