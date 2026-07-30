class BackupAndRemoveGroupConversations < ActiveRecord::Migration[7.1]
  def up
    create_table :group_data_backups, id: :uuid do |t|
      t.references :tenant, type: :uuid, null: false, foreign_key: true
      t.uuid :contact_id, null: false
      t.string :contact_name
      t.string :identifier
      t.integer :conversation_count, null: false, default: 0
      t.integer :message_count, null: false, default: 0
      t.integer :attachment_count, null: false, default: 0
      t.jsonb :payload, null: false, default: {}
      t.datetime :backed_up_at, null: false
      t.timestamps
    end
    add_index :group_data_backups, %i[tenant_id contact_id], unique: true

    Contact.reset_column_information
    contact_inbox_group_ids = ContactInbox.unscoped
                                            .where("source_id LIKE '%@g.us'")
                                            .select(:contact_id)
    conversation_group_ids = Conversation.unscoped
                                         .where("additional_attributes->>'evolution_chat_id' LIKE '%@g.us'")
                                         .select(:contact_id)
    contacts = Contact.unscoped
                      .where(type: 'group')
                      .or(Contact.unscoped.where("identifier LIKE '%@g.us'"))
                      .or(Contact.unscoped.where(id: contact_inbox_group_ids))
                      .or(Contact.unscoped.where(id: conversation_group_ids))

    contacts.find_each do |contact|
      conversations = Conversation.unscoped.where(contact_id: contact.id)
      messages = Message.unscoped.where(conversation_id: conversations.select(:id))
      attachments = Attachment.unscoped
                              .where(attachable_type: 'Message', attachable_id: messages.select(:id))
                              .includes(file_attachment: :blob)
      execute <<~SQL.squish
        INSERT INTO group_data_backups
          (id, tenant_id, contact_id, contact_name, identifier, conversation_count,
           message_count, attachment_count, payload, backed_up_at, created_at, updated_at)
        VALUES
          (gen_random_uuid(), #{quote(contact.tenant_id)}, #{quote(contact.id)},
           #{quote(contact.name)}, #{quote(contact.identifier)}, #{conversations.count},
           #{messages.count}, #{attachments.count}, #{quote({
             contact: contact.attributes,
             conversations: conversations.map(&:attributes),
             messages: messages.map(&:attributes),
             attachments: attachments.map do |attachment|
               attachment.attributes.merge(
                 'blob' => attachment.file.blob&.attributes&.slice(
                   'key', 'filename', 'content_type', 'metadata', 'byte_size', 'checksum'
                 )
               )
             end
           }.to_json)}::jsonb, NOW(), NOW(), NOW())
        ON CONFLICT (tenant_id, contact_id) DO NOTHING
      SQL
      contact.destroy!
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
          'Group records were deliberately removed; restore from group_data_backups or the database backup'
  end

  private

  def quote(value)
    connection.quote(value)
  end
end
