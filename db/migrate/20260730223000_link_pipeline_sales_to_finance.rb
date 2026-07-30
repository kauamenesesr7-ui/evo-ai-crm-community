class LinkPipelineSalesToFinance < ActiveRecord::Migration[7.1]
  def up
    add_reference :financial_entries, :pipeline_item, type: :uuid,
                  foreign_key: { on_delete: :nullify }, index: true

    # Repair old cards that still point at a rental already deleted. They remain
    # available in history, but must no longer inflate sold revenue.
    PipelineItem.reset_column_information
    PipelineStage.reset_column_information
    Rental.reset_column_information

    PipelineStage.unscoped.where("LOWER(name) IN ('concluído', 'concluido', 'ganho', 'won')")
                 .update_all(stage_type: PipelineStage.stage_types[:completed], updated_at: Time.current)
    PipelineStage.unscoped.where("LOWER(name) IN ('cancelado', 'cancelada', 'perdido', 'lost')")
                 .update_all(stage_type: PipelineStage.stage_types[:cancelled], updated_at: Time.current)

    PipelineItem.unscoped.where("custom_fields ? 'rental_id'").find_each do |item|
      rental_id = item.custom_fields['rental_id']
      next if rental_id.blank? || Rental.unscoped.exists?(id: rental_id)

      cancelled_stage = PipelineStage.unscoped.find_by(
        pipeline_id: item.pipeline_id,
        stage_type: PipelineStage.stage_types[:cancelled]
      )
      next unless cancelled_stage

      item.update_columns(
        pipeline_stage_id: cancelled_stage.id,
        completed_at: item.completed_at || Time.current,
        updated_at: Time.current
      )
    end
  end

  def down
    remove_reference :financial_entries, :pipeline_item, foreign_key: true
  end
end
