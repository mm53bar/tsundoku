class Reading < ApplicationRecord
  belongs_to :user
  belongs_to :book

  enum :status, {
    want_to_read:      0,
    currently_reading: 1,
    read:              2
  }, validate: true

  # Statuses that contribute to sync_to_kobo by default. See the design
  # notes for the rule: status drives the per-book sync default; shelves
  # marked sync_to_kobo can additionally include books regardless of
  # status.
  SYNCABLE_STATUSES = %w[want_to_read currently_reading].freeze

  validates :user_id, uniqueness: { scope: :book_id }

  def sync_to_kobo?
    SYNCABLE_STATUSES.include?(status)
  end

  def self.status_label(status)
    {
      "want_to_read"      => "Want to Read",
      "currently_reading" => "Currently Reading",
      "read"              => "Read"
    }[status.to_s]
  end
end
