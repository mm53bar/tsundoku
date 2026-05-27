class Task < ApplicationRecord
  belongs_to :subject, polymorphic: true, optional: true

  enum :status, { queued: 0, running: 1, succeeded: 2, failed: 3 }, validate: true

  validates :kind, presence: true

  # Kinds that produce a proposal the user must review before changes apply.
  # Their reviewed_at stays nil until the user opens the edit form for the
  # subject; the banner keeps them visible until then.
  REVIEWABLE_KINDS = %w[metadata_enrichment].freeze

  scope :active, -> { where(status: [ :queued, :running ]) }

  scope :pending_review, -> {
    where(status: :succeeded, kind: REVIEWABLE_KINDS, reviewed_at: nil)
  }

  scope :recently_settled, -> {
    where(status: [ :succeeded, :failed ])
      .where("finished_at >= ?", 30.seconds.ago)
      .where.not(reviewed_at: nil)
  }

  scope :visible, -> { active.or(pending_review).or(recently_settled) }

  def progress_percentage
    return nil if progress_total.nil? || progress_total.zero?
    ((progress_current.to_f / progress_total) * 100).round
  end

  def reviewable?
    REVIEWABLE_KINDS.include?(kind)
  end

  def pending_review?
    succeeded? && reviewable? && reviewed_at.nil?
  end

  def friendly_title
    case kind
    when "calibre_import"
      "Importing books from Calibre"
    when "metadata_enrichment"
      if subject.nil?
        "Enriching metadata"
      elsif pending_review?
        "Review suggestions for #{subject.title}"
      else
        "Enriching #{subject.title}"
      end
    else
      kind.humanize
    end
  end

  def mark_running!
    update!(status: :running, started_at: started_at || Time.current, attempts: attempts + 1)
    broadcast_update
  end

  def mark_succeeded!(result_data: nil)
    attrs = { status: :succeeded, finished_at: Time.current, result: result_data }
    # Non-reviewable tasks complete their lifecycle immediately on success.
    # Reviewable ones stay pending until the user opens the edit form.
    attrs[:reviewed_at] = Time.current unless reviewable?
    update!(attrs)
    broadcast_update
  end

  def mark_failed!(error_message:)
    update!(status: :failed, finished_at: Time.current, error_message: error_message, reviewed_at: Time.current)
    broadcast_update
  end

  def mark_reviewed!
    return if reviewed_at.present?
    update!(reviewed_at: Time.current)
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
