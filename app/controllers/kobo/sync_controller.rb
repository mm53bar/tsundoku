module Kobo
  # GET /kobo/:handle/v1/library/sync
  # Diff-based sync against the per-user KoboSyncedBook/KoboSyncedShelf
  # snapshot. Only emits Entitlements/Tags for things that have actually
  # changed since the last sync. Drop-outs become tombstones:
  # ChangedEntitlement {IsRemoved: true} for books, DeletedTag for shelves.
  class SyncController < BaseController
    def sync
      current_books            = syncable_books.includes(:authors, :publisher, :series).select(&:epub_downloadable?)
      current_book_ids         = current_books.map(&:id).to_set
      uuid_by_book_id          = current_books.to_h { |b| [ b.id, b.kobo_uuid ] }

      previously_synced_books  = @kobo_user.kobo_synced_books.where(book_id: current_book_ids).index_by(&:book_id)
      removed_book_records     = @kobo_user.kobo_synced_books.where.not(book_id: current_book_ids).includes(:book)

      payload = []

      current_books.each do |book|
        record = previously_synced_books[book.id]
        if record.nil?
          record = @kobo_user.kobo_synced_books.create!(book: book)
          payload << new_entitlement(book, record.created_at)
        elsif book.updated_at > record.updated_at
          record.touch
          payload << changed_entitlement(book, record.created_at)
        end
      end

      removed_book_records.each do |record|
        # The Book record still exists (it just dropped out of the
        # syncable set) so kobo_uuid is still valid for the tombstone.
        payload << removed_entitlement(record.book, record.created_at)
      end
      removed_book_records.destroy_all

      current_shelves            = @kobo_user.shelves.syncing.includes(:shelf_entries).by_name.to_a
      current_shelf_ids          = current_shelves.map(&:id).to_set
      previously_synced_shelves  = @kobo_user.kobo_synced_shelves.where(shelf_id: current_shelf_ids).index_by(&:shelf_id)
      removed_shelf_records      = @kobo_user.kobo_synced_shelves.where.not(shelf_id: current_shelf_ids)

      current_shelves.each do |shelf|
        record = previously_synced_shelves[shelf.id]
        if record.nil?
          @kobo_user.kobo_synced_shelves.create!(shelf_id: shelf.id, kobo_uuid: shelf.kobo_uuid)
          payload << new_tag(shelf, uuid_by_book_id)
        elsif shelf.updated_at > record.updated_at
          record.touch
          payload << changed_tag(shelf, uuid_by_book_id)
        end
      end

      removed_shelf_records.each do |record|
        payload << deleted_tag(record.kobo_uuid)
      end
      removed_shelf_records.destroy_all

      render json: payload
    end

    # GET /kobo/:handle/v1/library/:book_uuid/metadata
    # The device requests per-book metadata after sync before downloading.
    # Returning {} here causes the device to silently drop the entitlement
    # (it adds the book to the library list but never fetches the EPUB).
    def metadata
      book = find_book_by_kobo_uuid(params[:book_uuid])
      return head :not_found unless book

      # Wrap in an array — calibre-web does this and the device errors
      # out on an unwrapped object.
      render json: [ book_metadata(book, book.kobo_uuid) ]
    end

    private

    def new_entitlement(book, synced_at)
      { "NewEntitlement" => entitlement_envelope(book, synced_at, is_removed: false) }
    end

    def changed_entitlement(book, synced_at)
      { "ChangedEntitlement" => entitlement_envelope(book, synced_at, is_removed: false) }
    end

    def removed_entitlement(book, synced_at)
      { "ChangedEntitlement" => entitlement_envelope(book, synced_at, is_removed: true) }
    end

    def entitlement_envelope(book, synced_at, is_removed:)
      uuid     = book.kobo_uuid
      created  = (synced_at || Time.current).iso8601
      modified = (book.last_modified || book.updated_at).iso8601

      envelope = {
        "BookEntitlement" => {
          "Accessibility"       => "Full",
          "ActivePeriod"        => { "From" => created },
          "Created"             => created,
          "CrossRevisionId"     => uuid,
          "Id"                  => uuid,
          "IsRemoved"           => is_removed,
          "IsHiddenFromArchive" => false,
          "IsLocked"            => false,
          "LastModified"        => modified,
          "OriginCategory"      => "Imported",
          "RevisionId"          => uuid,
          "Status"              => is_removed ? "Removed" : "Active"
        },
        "BookMetadata" => book_metadata(book, uuid)
      }

      unless is_removed
        reading = @kobo_user.readings.find_by(book_id: book.id)
        envelope["ReadingState"] = reading.kobo_state_payload(book) if reading
      end

      envelope
    end

    def new_tag(shelf, uuid_by_book_id)
      { "NewTag" => { "Tag" => tag_envelope(shelf, uuid_by_book_id) } }
    end

    def changed_tag(shelf, uuid_by_book_id)
      { "ChangedTag" => { "Tag" => tag_envelope(shelf, uuid_by_book_id) } }
    end

    def deleted_tag(uuid)
      # Tombstone — only the Id matters, but include the minimum the
      # device will accept.
      { "DeletedTag" => { "Tag" => { "Id" => uuid } } }
    end

    def tag_envelope(shelf, uuid_by_book_id)
      items = shelf.shelf_entries.filter_map do |entry|
        uuid = uuid_by_book_id[entry.book_id]
        { "Type" => "ProductRevisionTagItem", "RevisionId" => uuid } if uuid
      end

      {
        "Created"      => shelf.created_at.iso8601,
        "Id"           => shelf.kobo_uuid,
        "Items"        => items,
        "LastModified" => shelf.updated_at.iso8601,
        "Name"         => shelf.name,
        "Type"         => "UserTag"
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
      return [] unless book.epub_downloadable?

      base = "#{request.base_url}/kobo/#{params[:handle]}/download/#{book.id}"

      # When KEPUB is available we emit it as the *only* DownloadUrl —
      # listing both KEPUB and EPUB causes the device to pick EPUB
      # (observed empirically; calibre-web's source does the same
      # KEPUB-only approach when KEPUB exists).
      if book.kepub_available?
        [ {
          "Format"   => "KEPUB",
          "Size"     => File.size(book.kepub_path),
          "Url"      => "#{base}/KEPUB",
          "Platform" => "Generic"
        } ]
      else
        [ {
          "Format"   => "EPUB3",
          "Size"     => File.size(book.epub_full_path),
          "Url"      => "#{base}/EPUB",
          "Platform" => "Generic"
        } ]
      end
    end
  end
end
