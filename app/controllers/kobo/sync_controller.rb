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
      render json: books.map { |book| new_entitlement(book) }
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

    def new_entitlement(book)
      uuid     = book.kobo_uuid
      created  = (book.added_at || book.created_at).iso8601
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
