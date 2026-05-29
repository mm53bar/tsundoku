namespace :kepub do
  desc "Enqueue KEPUB conversion for every book that has an EPUB but no KEPUB"
  task backfill: :environment do
    queued = 0
    Book.find_each do |book|
      next unless book.epub_downloadable?
      next if book.kepub_available?

      ConvertToKepubJob.perform_later(book.id)
      queued += 1
    end
    puts "Queued #{queued} #{'book'.pluralize(queued)} for KEPUB conversion."
  end

  desc "Force re-convert every book's KEPUB (use after a kepubify version bump)"
  task reconvert_all: :environment do
    queued = 0
    Book.find_each do |book|
      next unless book.epub_downloadable?

      ConvertToKepubJob.perform_later(book.id, force: true)
      queued += 1
    end
    puts "Queued #{queued} #{'book'.pluralize(queued)} for forced KEPUB re-conversion."
  end
end
