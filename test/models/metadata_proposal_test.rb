require "test_helper"

class MetadataProposalTest < ActiveSupport::TestCase
  setup do
    @book = Book.create!(
      title:       "Original Title",
      path:        "test/path",
      file_name:   "book",
      file_format: "EPUB",
      imported_at: Time.current
    )
  end

  teardown do
    @book.destroy if @book.persisted?
    Publisher.where(name: [ "New Pub", "Same Pub" ]).destroy_all
    Author.where(name: [ "Test Author", "James S.A. Corey", "James S. A. Corey", "New Author One", "New Author Two" ]).destroy_all
  end

  # ActionController::Parameters-shaped attributes for the strong-param
  # path. Tests build them as plain hashes — Rails accepts both shapes
  # for update!.
  def attrs(overrides = {})
    { title: "New Title" }.merge(overrides)
  end

  def make_choices(overrides = {})
    defaults = MetadataProposal::Choices.new(
      book_attributes:            attrs,
      publisher_name:             nil,
      author_names_text:          nil,
      accepted_identifier_tokens: [],
      accept_cover:               false
    )
    overrides.each { |k, v| defaults[k] = v }
    defaults
  end

  def apply(task: nil, **choice_overrides)
    MetadataProposal.new(book: @book, task: task, choices: make_choices(choice_overrides)).apply!
  end

  # Book attributes — the simplest path.

  test "apply! updates the book's permitted attributes" do
    apply
    assert_equal "New Title", @book.reload.title
  end

  # Publisher — find-or-create, dedupe by exact name.

  test "apply_publisher creates a publisher when none matches" do
    apply(publisher_name: "New Pub")
    assert_equal "New Pub", @book.reload.publisher&.name
  end

  test "apply_publisher reuses an existing publisher with the same name" do
    existing = Publisher.create!(name: "Same Pub")
    apply(publisher_name: "Same Pub")
    assert_equal existing.id, @book.reload.publisher_id
  end

  test "apply_publisher does nothing when blank" do
    @book.update!(publisher: Publisher.find_or_create_by!(name: "Same Pub"))
    apply(publisher_name: "")
    assert_equal "Same Pub", @book.reload.publisher&.name
  end

  test "apply_publisher does nothing when the name matches the current publisher" do
    pub = Publisher.find_or_create_by!(name: "Same Pub")
    @book.update!(publisher: pub)
    apply(publisher_name: "Same Pub")
    assert_equal pub.id, @book.reload.publisher_id
  end

  # Authors — parse, normalize, dedupe, rebuild in order.

  test "apply_authors creates and links new authors in order" do
    apply(author_names_text: "New Author One, New Author Two")
    names = @book.reload.book_authors.order(:position).map { |ba| ba.author.name }
    assert_equal [ "New Author One", "New Author Two" ], names
  end

  test "apply_authors reuses existing authors whose names normalize identically" do
    existing = Author.create!(name: "James S. A. Corey")
    apply(author_names_text: "James S.A. Corey")
    assert_equal [ existing.id ], @book.reload.book_authors.map(&:author_id)
  end

  test "apply_authors leaves authors alone when the field is nil" do
    Author.create!(name: "Test Author").tap do |a|
      @book.book_authors.create!(author: a, position: 0)
    end
    apply(author_names_text: nil)
    assert_equal 1, @book.reload.book_authors.count
  end

  test "apply_authors clears authors when the field is blank string" do
    Author.create!(name: "Test Author").tap do |a|
      @book.book_authors.create!(author: a, position: 0)
    end
    apply(author_names_text: "")
    assert_empty @book.reload.book_authors
  end

  # Accepted identifiers — only tokens that match the proposal are applied.

  test "apply_accepted_identifiers creates identifiers from the proposal" do
    task = build_task(identifiers: [ { "kind" => "isbn13", "value" => "9780000000001" } ])
    apply(task: task, accepted_identifier_tokens: [ "isbn13|9780000000001" ])
    assert @book.reload.book_identifiers.exists?(kind: "isbn13", value: "9780000000001")
  end

  test "apply_accepted_identifiers refuses tokens not in the proposal" do
    task = build_task(identifiers: [ { "kind" => "isbn13", "value" => "9780000000001" } ])
    apply(task: task, accepted_identifier_tokens: [ "isbn13|injected-by-attacker" ])
    refute @book.reload.book_identifiers.exists?(value: "injected-by-attacker")
  end

  test "apply_accepted_identifiers skips identifiers that already exist on the book" do
    @book.book_identifiers.create!(kind: "isbn13", value: "9780000000001")
    task = build_task(identifiers: [ { "kind" => "isbn13", "value" => "9780000000001" } ])
    assert_no_difference -> { @book.book_identifiers.count } do
      apply(task: task, accepted_identifier_tokens: [ "isbn13|9780000000001" ])
    end
  end

  test "apply_accepted_identifiers does nothing without a task" do
    apply(task: nil, accepted_identifier_tokens: [ "isbn13|9780000000001" ])
    assert_empty @book.reload.book_identifiers
  end

  # Accepted cover — opt-in via accept_cover, URL comes from the task.

  test "apply_accepted_cover does nothing when accept_cover is false" do
    task = build_task(cover: { "url" => "https://example.com/cover.jpg" })
    apply(task: task, accept_cover: false)
    assert_nil @book.reload.enriched_cover_path
  end

  test "apply_accepted_cover does nothing when proposal has no cover" do
    task = build_task(cover: nil)
    apply(task: task, accept_cover: true)
    assert_nil @book.reload.enriched_cover_path
  end

  test "apply_accepted_cover refuses non-http schemes" do
    # The proposal carries a javascript: URL; the PORO refuses to fetch
    # it. Belt-and-suspenders alongside the LinkToHref check in views.
    task = build_task(cover: { "url" => "javascript:alert(1)" })
    apply(task: task, accept_cover: true)
    assert_nil @book.reload.enriched_cover_path
  end

  # Atomicity — failures roll back everything in the transaction.

  test "apply! rolls back when the book update fails validation" do
    # title is required; updating to blank triggers RecordInvalid
    proposal = MetadataProposal.new(
      book: @book,
      task: nil,
      choices: make_choices(book_attributes: { title: "" }, publisher_name: "Should Not Persist")
    )
    assert_raises(ActiveRecord::RecordInvalid) { proposal.apply! }
    refute Publisher.exists?(name: "Should Not Persist")
  end

  private

  def build_task(payload)
    Task.create!(
      kind:    "metadata_enrichment",
      subject: @book,
      status:  :succeeded,
      result:  payload.stringify_keys
    )
  end
end
