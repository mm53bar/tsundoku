class Shelf < ApplicationRecord
  belongs_to :user
  has_many :shelf_entries, -> { order(:position) }, dependent: :destroy, inverse_of: :shelf
  has_many :books, through: :shelf_entries

  validates :name, presence: true, uniqueness: { scope: :user_id }

  scope :by_name, -> { order(Arel.sql("name COLLATE NOCASE ASC")) }
  scope :syncing, -> { where(sync_to_kobo: true) }

  def to_param
    "#{id}-#{name.parameterize}"
  end

  KOBO_UUID_NAMESPACE = Digest::UUID.uuid_v5(Digest::UUID::URL_NAMESPACE, "tsundoku-kobo-shelves").freeze

  def kobo_uuid
    Digest::UUID.uuid_v5(KOBO_UUID_NAMESPACE, id.to_s)
  end
end
