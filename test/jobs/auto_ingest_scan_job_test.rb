require "test_helper"
require "fileutils"
require "tmpdir"

class AutoIngestScanJobTest < ActiveJob::TestCase
  # Each test re-roots INGEST_PATH at a fresh tmpdir so the scan walks
  # a controlled tree, not whatever's in storage/ingest_dev/.
  setup do
    @tmp = Dir.mktmpdir("auto_ingest_test")
    @original_ingest_path = Rails.configuration.x.ingest_path
    Rails.configuration.x.ingest_path = @tmp
    Task.delete_all
  end

  teardown do
    Rails.configuration.x.ingest_path = @original_ingest_path
    FileUtils.remove_entry(@tmp) if @tmp && File.directory?(@tmp)
  end

  # Empty / no-op cases — silent, no task, no log.

  test "no-op when the ingest directory is empty" do
    assert_no_difference -> { Task.count } do
      AutoIngestScanJob.perform_now
    end
  end

  test "no-op when the ingest directory doesn't exist" do
    Rails.configuration.x.ingest_path = "/nonexistent/path/xyz"
    assert_no_difference -> { Task.count } do
      AutoIngestScanJob.perform_now
    end
  end

  test "no-op when the configured path is blank" do
    Rails.configuration.x.ingest_path = ""
    assert_no_difference -> { Task.count } do
      AutoIngestScanJob.perform_now
    end
  end

  # Found work — queues per-file jobs + summary task.

  test "queues an IngestFileJob per EPUB" do
    File.write(File.join(@tmp, "foo.epub"), "")
    File.write(File.join(@tmp, "bar.epub"), "")

    assert_enqueued_jobs 2, only: IngestFileJob do
      AutoIngestScanJob.perform_now
    end
  end

  test "creates a book_ingest task per queued file" do
    File.write(File.join(@tmp, "foo.epub"), "")
    File.write(File.join(@tmp, "bar.epub"), "")

    assert_difference -> { Task.where(kind: "book_ingest").count }, 2 do
      AutoIngestScanJob.perform_now
    end
  end

  test "creates a single auto_ingest_scan summary task with the queued count" do
    File.write(File.join(@tmp, "foo.epub"), "")
    File.write(File.join(@tmp, "bar.epub"), "")

    assert_difference -> { Task.where(kind: "auto_ingest_scan").count }, 1 do
      AutoIngestScanJob.perform_now
    end

    summary = Task.where(kind: "auto_ingest_scan").last
    assert summary.succeeded?
    assert_equal 2, summary.result["queued_count"]
    assert_equal %w[bar.epub foo.epub], summary.result["files"].sort
  end

  test "non-EPUB files are ignored" do
    File.write(File.join(@tmp, "foo.epub"), "")
    File.write(File.join(@tmp, "notes.txt"), "ignore me")
    File.write(File.join(@tmp, "cover.jpg"), "ignore me")

    assert_difference -> { Task.where(kind: "book_ingest").count }, 1 do
      AutoIngestScanJob.perform_now
    end
  end

  test "recurses into subdirectories" do
    FileUtils.mkdir_p(File.join(@tmp, "subdir/nested"))
    File.write(File.join(@tmp, "subdir/nested/deep.epub"), "")

    assert_difference -> { Task.where(kind: "book_ingest").count }, 1 do
      AutoIngestScanJob.perform_now
    end
  end

  # Idempotency — skip files that already have an in-flight task.

  test "skips files with an existing queued book_ingest task" do
    path = File.join(@tmp, "foo.epub")
    File.write(path, "")
    Task.create!(kind: "book_ingest", status: :queued, result: { "file_path" => path })

    assert_no_difference -> { Task.where(kind: "book_ingest").count } do
      AutoIngestScanJob.perform_now
    end
    # No summary task either — nothing fresh was queued.
    assert_equal 0, Task.where(kind: "auto_ingest_scan").count
  end

  test "skips files with an existing running book_ingest task" do
    path = File.join(@tmp, "foo.epub")
    File.write(path, "")
    Task.create!(kind: "book_ingest", status: :running, result: { "file_path" => path })

    assert_no_difference -> { Task.where(kind: "book_ingest").count } do
      AutoIngestScanJob.perform_now
    end
  end

  test "does not skip files when the prior task is succeeded or failed" do
    # A previous failed attempt shouldn't block a retry. The recurring
    # scan acts as the retry mechanism.
    path = File.join(@tmp, "foo.epub")
    File.write(path, "")
    Task.create!(kind: "book_ingest", status: :failed, finished_at: Time.current,
                 result: { "file_path" => path })

    assert_difference -> { Task.where(kind: "book_ingest", status: :queued).count }, 1 do
      AutoIngestScanJob.perform_now
    end
  end
end
