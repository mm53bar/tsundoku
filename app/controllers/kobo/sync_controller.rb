module Kobo
  # GET /kobo/:handle/v1/library/sync
  # Diff-based sync against the per-user KoboSyncedBook/KoboSyncedShelf
  # snapshot. Only emits Entitlements/Tags for things that have actually
  # changed since the last sync. Drop-outs become tombstones:
  # ChangedEntitlement {IsRemoved: true} for books, DeletedTag for shelves.
  class SyncController < BaseController
    def sync
      log_sync_request_diagnostics

      current_books            = syncable_books.includes(:authors, :publisher, :series).select { |b| b.assets.epub_downloadable? }
      current_book_ids         = current_books.map(&:id).to_set
      uuid_by_book_id          = current_books.to_h { |b| [ b.id, b.kobo_uuid ] }

      previously_synced_books  = @kobo_user.kobo_synced_books.where(book_id: current_book_ids).index_by(&:book_id)
      # Tombstones come from two places:
      #   * rows whose book is still around but no longer syncable
      #     (status changed, removed from a syncing shelf, etc.)
      #   * rows whose book was hard-destroyed; book_id is NULL and the
      #     kobo_uuid snapshot on the row is the only thing left.
      # SQL's NOT IN excludes NULLs, hence the explicit OR.
      removed_book_records = @kobo_user.kobo_synced_books
                                       .where("book_id IS NULL OR book_id NOT IN (?)", current_book_ids.to_a.presence || [ 0 ])

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
        # Use the snapshot kobo_uuid on the record so this works whether
        # the book still exists or was destroyed.
        payload << removed_entitlement(record.kobo_uuid, record.created_at)
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

      log_sync_response_diagnostics(payload)

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

    # DELETE /kobo/:handle/v1/library/:book_uuid
    # The device sends this for each book it has just removed from its
    # local library (e.g. when the user manually wipes books on the
    # Kobo, the device fires a burst of these — one per book it had).
    #
    # We treat the call as "this device no longer has this book." We
    # destroy the user's KoboSyncedBook row for that uuid so the next
    # sync's diff sees a missing snapshot and re-emits NewEntitlement
    # (assuming the book is still in syncable_books for this user).
    # That's auto-recovery for the manual-wipe scenario — no
    # Force-Full-Resync click needed.
    #
    # Idempotent: a DELETE for an unknown uuid returns 200 with no
    # state change. The device doesn't care about the response body;
    # it just wants a non-error status.
    def destroy_library_entry
      @kobo_user.kobo_synced_books.where(kobo_uuid: params[:book_uuid]).destroy_all
      render json: {}
    end

    private

    # Diagnostic log of inbound headers + current Tsundoku state so we
    # can correlate real device behavior (e.g. what the sync token looks
    # like after a manual wipe) with what we emit. INFO-level — adds two
    # log lines per sync, which is a few per day in normal use. Remove or
    # demote to DEBUG once we've collected enough empirical data to wire
    # up real sync-token handling.
    def log_sync_request_diagnostics
      headers = request.headers.env.select { |k, _| k.start_with?("HTTP_X_KOBO") || k == "HTTP_USER_AGENT" }
                                  .transform_keys { |k| k.sub("HTTP_", "").downcase.tr("_", "-") }

      Rails.logger.info(
        "Kobo sync REQUEST " \
        "user=#{@kobo_user.kobo_handle} " \
        "syncable_books=#{@kobo_user.on_kobo_books.count} " \
        "snapshot_rows=#{@kobo_user.kobo_synced_books.count} " \
        "headers=#{headers.to_json}"
      )
    end

    def log_sync_response_diagnostics(payload)
      counts = payload.each_with_object(Hash.new(0)) do |entry, acc|
        acc[entry.keys.first] += 1
      end

      Rails.logger.info(
        "Kobo sync RESPONSE " \
        "user=#{@kobo_user.kobo_handle} " \
        "total_entries=#{payload.size} " \
        "by_kind=#{counts.to_json}"
      )
    end

    def new_entitlement(book, synced_at)
      { "NewEntitlement" => entitlement_envelope(book, synced_at) }
    end

    def changed_entitlement(book, synced_at)
      { "ChangedEntitlement" => entitlement_envelope(book, synced_at) }
    end

    # Tombstone envelope — emitted for rows whose book is gone (or merely
    # no longer syncable). Takes the kobo_uuid directly because we may
    # not have a Book to read it from.
    def removed_entitlement(kobo_uuid, synced_at)
      created  = (synced_at || Time.current).iso8601
      envelope = {
        "BookEntitlement" => {
          "Accessibility"       => "Full",
          "ActivePeriod"        => { "From" => created },
          "Created"             => created,
          "CrossRevisionId"     => kobo_uuid,
          "Id"                  => kobo_uuid,
          "IsRemoved"           => true,
          "IsHiddenFromArchive" => false,
          "IsLocked"            => false,
          "LastModified"        => created,
          "OriginCategory"      => "Imported",
          "RevisionId"          => kobo_uuid,
          "Status"              => "Removed"
        },
        "BookMetadata" => {
          "CrossRevisionId" => kobo_uuid,
          "EntitlementId"   => kobo_uuid,
          "RevisionId"      => kobo_uuid,
          "WorkId"          => kobo_uuid
        }
      }
      { "ChangedEntitlement" => envelope }
    end

    # Live entitlement (New or Changed). Tombstones go through
    # #removed_entitlement directly since they don't have a Book to read.
    def entitlement_envelope(book, synced_at)
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

      reading = @kobo_user.readings.find_by(book_id: book.id)
      envelope["ReadingState"] = reading.kobo_state_payload(book) if reading

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
      assets = book.assets
      return [] unless assets.epub_downloadable?

      base = "#{request.base_url}/kobo/#{params[:handle]}/download/#{book.id}"

      # When KEPUB is available we emit it as the *only* DownloadUrl —
      # listing both KEPUB and EPUB causes the device to pick EPUB
      # (observed empirically; calibre-web's source does the same
      # KEPUB-only approach when KEPUB exists).
      if assets.kepub_available?
        [ {
          "Format"   => "KEPUB",
          "Size"     => File.size(assets.kepub_path),
          "Url"      => "#{base}/KEPUB",
          "Platform" => "Generic"
        } ]
      else
        [ {
          "Format"   => "EPUB3",
          "Size"     => File.size(assets.epub_full_path),
          "Url"      => "#{base}/EPUB",
          "Platform" => "Generic"
        } ]
      end
    end
  end
end
