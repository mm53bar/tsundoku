class Task < ApplicationRecord
  belongs_to :subject, polymorphic: true, optional: true

  enum :status, { queued: 0, running: 1, succeeded: 2, failed: 3 }, validate: true

  validates :kind, presence: true

  scope :active,              -> { where(status: [ :queued, :running ]) }
  scope :recently_completed,  -> { where(status: [ :succeeded, :failed ]).where("finished_at >= ?", 30.seconds.ago) }
  scope :visible,             -> { active.or(recently_completed) }

  def progress_percentage
    return nil if progress_total.nil? || progress_total.zero?
    ((progress_current.to_f / progress_total) * 100).round
  end

  def friendly_title
    case kind
    when "calibre_import"
      "Importing books from Calibre"
    when "metadata_enrichment"
      subject ? "Enriching #{subject.title}" : "Enriching metadata"
    else
      kind.humanize
    end
  end

  def mark_running!
    update!(status: :running, started_at: started_at || Time.current, attempts: attempts + 1)
    broadcast_update
  end

  def mark_succeeded!(result_data: nil)
    update!(status: :succeeded, finished_at: Time.current, result: result_data)
    broadcast_update
  end

  def mark_failed!(error_message:)
    update!(status: :failed, finished_at: Time.current, error_message: error_message)
    broadcast_update
  end

  def update_progress!(current, total)
    update!(progress_current: current, progress_total: total)
    broadcast_update
  end

  def broadcast_update
    Turbo::StreamsChannel.broadcast_replace_to(
      "tasks:active",
      target: "active_tasks",
      partial: "tasks/active_list",
      locals: { tasks: Task.visible.order(:created_at) }
    )
  end
end
