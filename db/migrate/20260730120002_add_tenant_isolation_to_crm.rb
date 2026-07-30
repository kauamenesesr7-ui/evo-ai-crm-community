class AddTenantIsolationToCrm < ActiveRecord::Migration[7.1]
  DEFAULT_TENANT_ID = '00000000-0000-4000-8000-000000000001'

  TENANT_TABLES = %i[
    agent_bot_inboxes agent_bots ai_agent_products attachments
    automation_rule_runs automation_rules canned_responses
    channel_api channel_email channel_facebook_pages channel_instagram
    channel_line channel_sendgrid channel_sms channel_telegram
    channel_twilio_sms channel_twitter_profiles channel_web_widgets
    channel_whatsapp chat_pages contact_companies contact_inboxes contacts
    conversation_participants conversations crm_forms csat_survey_responses
    custom_attribute_definitions custom_filters dashboard_apps data_imports
    data_privacy_consents facebook_comment_moderations
    inactivity_action_executions inbox_members inboxes integrations_hooks
    labels macro_executions macros mentions message_templates messages notes
    notification_settings notification_subscriptions notifications
    pipeline_item_products pipeline_items pipeline_service_definitions
    pipeline_stages pipeline_tasks pipelines product_variants products
    reporting_events scheduled_action_execution_logs
    scheduled_action_notifications scheduled_action_templates
    scheduled_actions setup_survey_responses stage_inactivity_executions
    stage_movements taggings tags team_members teams telegram_bots
    user_tours webhooks working_hours
  ].freeze

  def up
    TENANT_TABLES.each do |table|
      next unless table_exists?(table)
      next if column_exists?(table, :tenant_id)

      add_column table, :tenant_id, :uuid
      execute <<~SQL.squish
        UPDATE #{quote_table_name(table)}
        SET tenant_id = #{quote(DEFAULT_TENANT_ID)}
        WHERE tenant_id IS NULL
      SQL
      change_column_null table, :tenant_id, false
      add_index table, :tenant_id
      add_foreign_key table, :tenants, column: :tenant_id
    end

    replace_unique_index :contacts, 'uniq_email_per_account_contact',
                         %i[tenant_id email], 'uniq_contacts_tenant_email'
    replace_unique_index :contacts, 'uniq_identifier_per_account_contact',
                         %i[tenant_id identifier], 'uniq_contacts_tenant_identifier'
    replace_unique_index :contacts, 'index_contacts_on_tax_id',
                         %i[tenant_id tax_id], 'uniq_contacts_tenant_tax_id',
                         where: 'tax_id IS NOT NULL'
    replace_unique_index :conversations, 'index_conversations_on_display_id',
                         %i[tenant_id display_id], 'uniq_conversations_tenant_display'
    replace_unique_index :crm_forms, 'index_crm_forms_on_slug',
                         %i[tenant_id slug], 'uniq_crm_forms_tenant_slug'
    replace_unique_index :chat_pages, 'index_chat_pages_on_slug',
                         %i[tenant_id slug], 'uniq_chat_pages_tenant_slug'
    replace_unique_index :custom_attribute_definitions, 'attribute_key_model_index',
                         %i[tenant_id attribute_key attribute_model], 'uniq_custom_attrs_tenant_key_model'
    replace_unique_index :labels, 'index_labels_on_title',
                         %i[tenant_id title], 'uniq_labels_tenant_title'
    replace_unique_index :message_templates, 'idx_message_templates_global_name',
                         %i[tenant_id name], 'uniq_message_templates_tenant_name',
                         where: 'channel_id IS NULL'
    replace_unique_index :pipelines, 'index_pipelines_on_name',
                         %i[tenant_id name], 'uniq_pipelines_tenant_name'
    replace_unique_index :products, 'index_products_on_sku',
                         %i[tenant_id sku], 'uniq_products_tenant_sku',
                         where: 'sku IS NOT NULL'
    replace_unique_index :product_variants, 'index_product_variants_on_sku',
                         %i[tenant_id sku], 'uniq_product_variants_tenant_sku',
                         where: 'sku IS NOT NULL'
    replace_unique_index :tags, 'index_tags_on_name',
                         %i[tenant_id name], 'uniq_tags_tenant_name'
    replace_unique_index :teams, 'index_teams_on_name',
                         %i[tenant_id name], 'uniq_teams_tenant_name'
    replace_unique_index :webhooks, 'index_webhooks_on_url',
                         %i[tenant_id url], 'uniq_webhooks_tenant_url'
  end

  def down
    raise ActiveRecord::IrreversibleMigration, 'Tenant isolation cannot be removed safely'
  end

  private

  def replace_unique_index(table, old_name, columns, new_name, where: nil)
    return unless table_exists?(table)

    remove_index table, name: old_name if index_name_exists?(table, old_name)
    add_index table, columns, unique: true, name: new_name, where: where
  end

  def quote(value)
    connection.quote(value)
  end
end
