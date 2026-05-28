class User < ApplicationRecord
  enum :role, { reader: 0, admin: 1 }

  has_many :readings, dependent: :destroy
  has_many :read_books, through: :readings, source: :book

  has_many :shelves, dependent: :destroy
  has_many :kobo_synced_books, dependent: :destroy
  has_many :kobo_synced_shelves, dependent: :destroy
  has_many :kobo_devices, dependent: :destroy

  validates :username, presence: true, uniqueness: true

  KOBO_WORDLIST = File.readlines(Rails.root.join("lib/data/mnemonic_wordlist.txt")).map(&:strip).freeze

  def regenerate_kobo_handle!
    loop do
      candidate = KOBO_WORDLIST.sample
      next if User.where.not(id: id).exists?(kobo_handle: candidate)
      update!(kobo_handle: candidate)
      return candidate
    end
  end

  def self.find_or_provision_from_proxy(username:, email: nil, name: nil)
    user = find_or_create_by!(username: username) do |u|
      u.email = email
      u.name  = name.presence || username.to_s.titleize
      u.role  = User.none? ? :admin : :reader
    end

    updates = {}
    updates[:email] = email if email.present? && user.email != email
    updates[:name]  = name  if name.present?  && user.name  != name
    user.update!(updates) if updates.any?

    user
  end

  def display_name
    name.presence || username
  end
end
