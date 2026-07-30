require 'json'

namespace :buffet_crm do
  desc 'Import an idempotent LokAgenda JSON export into a tenant'
  task import_lokagenda: :environment do
    source_file = ENV.fetch('IMPORT_FILE')
    payload = JSON.parse(File.read(source_file))
    result = Imports::LokagendaImporter.new(
      payload,
      tenant_id: ENV.fetch('TENANT_ID', Imports::LokagendaImporter::DEFAULT_TENANT_ID),
      dry_run: ActiveModel::Type::Boolean.new.cast(ENV.fetch('DRY_RUN', 'false'))
    ).call

    puts JSON.pretty_generate(result)
  end
end
