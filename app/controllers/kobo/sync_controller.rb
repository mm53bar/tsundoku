module Kobo
  # GET /kobo/:handle/v1/library/sync
  # The main sync endpoint. Returns a JSON array of entitlement entries
  # for every book in the user's syncable set. Phase B implementation:
  # always send everything as NewEntitlement (no synctoken cursor yet —
  # see design doc §4.3). The device dedupes by entitlement UUID so
  # re-sending the same books is idempotent.
  class SyncController < BaseController
    def sync
      books = syncable_books.includes(:authors, :publisher, :series).select(&:epub_downloadable?)
      synced_at_by_book = ensure_synced_records(books)

      # Build the book entitlements first, then append Tag blocks for any
      # shelves marked sync_to_kobo. Tag items are filtered to books that
      # are themselves in the sync payload — sending a Tag.Items reference
      # to a UUID the device doesn't have as an entitlement creates a
      # dangling shelf entry on-device.
      uuid_by_book_id = books.to_h { |b| [ b.id, b.kobo_uuid ] }
      shelves         = @kobo_user.shelves.syncing.includes(shelf_entries: :book).by_name

      payload  = books.map { |book| new_entitlement(book, synced_at_by_book[book.id]) }
      payload += shelves.map { |shelf| new_tag(shelf, uuid_by_book_id) }

      render json: payload
    end

    # GET /kobo/:handle/v1/library/:book_uuid/metadata
    # The device requests per-book metadata after sync before downloading.
    # Returning {} here causes the device to silently drop the entitlement
    # (it adds the book to the library list but never fetches the EPUB).
    def metadata
      uuid = params[:book_uuid]
      book = syncable_books.find { |b| b.kobo_uuid == uuid }
      return head :not_found unless book

      # Wrap in an array — calibre-web does this and the device errors
      # out on an unwrapped object.
      render json: [ book_metadata(book, uuid) ]
    end

    private

    # Make sure every syncable book has a KoboSyncedBook row for the
    # current user, creating new ones with Time.current. Returns a
    # {book_id => synced_at} map for use in entitlement Created fields.
    def ensure_synced_records(books)
      existing = @kobo_user.kobo_synced_books.where(book_id: books.map(&:id)).pluck(:book_id, :created_at).to_h
      books.each do |book|
        next if existing[book.id]
        record = @kobo_user.kobo_synced_books.create!(book: book)
        existing[book.id] = record.created_at
      end
      existing
    end

    def new_tag(shelf, uuid_by_book_id)
      items = shelf.shelf_entries.filter_map do |entry|
        uuid = uuid_by_book_id[entry.book_id]
        { "Type" => "ProductRevisionTagItem", "RevisionId" => uuid } if uuid
      end

      {
        "NewTag" => {
          "Tag" => {
            "Created"      => shelf.created_at.iso8601,
            "Id"           => shelf.kobo_uuid,
            "Items"        => items,
            "LastModified" => shelf.updated_at.iso8601,
            "Name"         => shelf.name,
            "Type"         => "UserTag"
          }
        }
      }
    end

    def new_entitlement(book, synced_at)
      uuid     = book.kobo_uuid
      created  = (synced_at || Time.current).iso8601
      modified = (book.last_modified || book.updated_at).iso8601

      {
        "NewEntitlement" => {
          "BookEntitlement" => {
            "Accessibility"       => "Full",
            "ActivePeriod"        => { "From" => created },
            "Created"             => created,
            "CrossRevisionId"     => uuid,
            "Id"                  => uuid,
            "IsRemoved"           => false,
            "IsHiddenFromArchive" => false,
            "IsLocked"            => false,
            "LastModified"        => modified,
            "OriginCategory"      => "Imported",
            "RevisionId"          => uuid,
            "Status"              => "Active"
          },
          "BookMetadata" => book_metadata(book, uuid)
        }
      }
    end

    def book_metadata(book, uuid)
      metadata = {
        "Categories"       => [ "00000000-0000-0000-0000-000000000001" ],
        "CoverImageId"     => uuid,
        "CrossRevisionId"  => uuid,
        "DownloadUrls"     => download_urls_for(book),
        "EntitlementId"    => uuid,
        "Language"         => "en",
        "Publisher"        => { "Imprint" => "", "Name" => book.publisher&.name.to_s },
        "RevisionId"       => uuid,
        "Title"            => book.title,
        "WorkId"           => uuid,
        "ContributorRoles" => book.authors.map { |a| { "Name" => a.name } },
        "Contributors"     => book.authors.map(&:name)
      }

      metadata["Description"]     = book.description if book.description.present?
      metadata["PublicationDate"] = book.pubdate.iso8601 if book.pubdate.present?

      if book.series.present?
        metadata["Series"] = {
          "Name"        => book.series.name,
          "Number"      => book.series_index.to_i,
          "NumberFloat" => book.series_index.to_f,
          "Id"          => book.series.kobo_uuid
        }
      end

      metadata
    end

    def download_urls_for(book)
      return [] unless book.epub_full_path && File.exist?(book.epub_full_path)

      size = File.size(book.epub_full_path)
      url  = "#{request.base_url}/kobo/#{params[:handle]}/download/#{book.id}/EPUB"

      [ { "Format" => "EPUB3", "Size" => size, "Url" => url, "Platform" => "Generic" } ]
    end
  end
end
