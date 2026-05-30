class List < ApplicationRecord
  belongs_to :user
  has_many :list_entries, -> { order(:position) }, dependent: :destroy, inverse_of: :list

  validates :name, presence: true
  validate :source_url_must_be_http

  scope :by_name, -> { order(Arel.sql("name COLLATE NOCASE ASC")) }

  # Records this user may read in normal app flow: their own (any
  # sharing state) plus other users' lists that have been explicitly
  # marked `shared`. Per docs/architecture-principles.md §3, the `.for`
  # naming is the project-wide convention for user-relative read
  # access; owner-only writes use `current_user.lists.find(...)`
  # instead.
  scope :for, ->(user) {
    where(user_id: user&.id).or(where(shared: true))
  }

  def to_param
    "#{id}-#{name.parameterize}"
  end

  def matched_count
    list_entries.where.not(book_id: nil).count
  end

  def total_count
    list_entries.size
  end

  # Use this in views instead of `source_url` directly — strips anything
  # that's not an http(s) URL so we never render a javascript: or data: link
  # even if the format validation got bypassed (e.g. via direct DB write).
  def safe_source_url
    return nil if source_url.blank?
    uri = URI.parse(source_url)
    return nil unless %w[http https].include?(uri.scheme)
    source_url
  rescue URI::InvalidURIError
    nil
  end

  private

  def source_url_must_be_http
    return if source_url.blank?
    uri = URI.parse(source_url)
    unless %w[http https].include?(uri.scheme)
      errors.add(:source_url, "must be an http or https URL")
    end
  rescue URI::InvalidURIError
    errors.add(:source_url, "is not a valid URL")
  end
end
