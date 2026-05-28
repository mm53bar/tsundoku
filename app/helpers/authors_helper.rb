module AuthorsHelper
  def author_links(authors, separator: ", ", class_name: nil)
    rendered = authors.map { |a| render("authors/link", author: a, class_name: class_name) }
    safe_join(rendered, separator)
  end
end
