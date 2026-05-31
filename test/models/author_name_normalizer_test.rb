require "test_helper"

class AuthorNameNormalizerTest < ActiveSupport::TestCase
  # Each test pins one observed dirty input to the cleaned output we
  # want. The fixture inputs all come from Sheila's actual library;
  # the heuristic was tuned against that distribution.

  # Clean inputs pass through unchanged.

  test "leaves a single well-formed name alone" do
    assert_equal [ "Frank Herbert" ], AuthorNameNormalizer.normalize("Frank Herbert")
  end

  test "preserves diacritics, periods, and middle initials" do
    assert_equal [ "Gabriel García Márquez" ], AuthorNameNormalizer.normalize("Gabriel García Márquez")
    assert_equal [ "J. D. Salinger" ],         AuthorNameNormalizer.normalize("J. D. Salinger")
    assert_equal [ "Ursula K. Le Guin" ],      AuthorNameNormalizer.normalize("Ursula K. Le Guin")
  end

  # Trailing-junk strip — Calibre concatenations leave `;`, `,`, etc.

  test "strips trailing semicolons" do
    assert_equal [ "Andy Weir" ],    AuthorNameNormalizer.normalize("Andy Weir;")
    assert_equal [ "Blake Crouch" ], AuthorNameNormalizer.normalize("Blake Crouch;")
  end

  test "strips trailing whitespace and commas" do
    assert_equal [ "Madeline Miller" ], AuthorNameNormalizer.normalize("Madeline Miller  ")
    assert_equal [ "Robin Hobb" ],      AuthorNameNormalizer.normalize("Robin Hobb,")
  end

  # `|` and `;` as multi-author separators when each part is a full name.

  test "splits `|` between multi-word author names" do
    assert_equal [ "Eric Freeman", "Elisabeth Robson", "Bert Bates" ],
      AuthorNameNormalizer.normalize("Eric Freeman| Elisabeth Robson| Bert Bates")
  end

  test "splits `|` between two multi-word names" do
    assert_equal [ "Jim Blandy", "Jason Orendorff" ],
      AuthorNameNormalizer.normalize("Jim Blandy| Jason Orendorff")
  end

  test "splits `;` between multi-word names" do
    assert_equal [ "Ryan Smith", "Tommy Denda", "Patrick Marshall" ],
      AuthorNameNormalizer.normalize("Ryan Smith;Tommy Denda;Patrick Marshall")
  end

  # `|` as a "Last| First" delimiter for a single author — pair-and-flip.

  test "reverses a `Last| First` single-author pair" do
    assert_equal [ "Laszlo Bock" ],  AuthorNameNormalizer.normalize("Bock| Laszlo")
    assert_equal [ "Jackson Wood" ], AuthorNameNormalizer.normalize("Wood| Jackson")
    assert_equal [ "Peter Owen" ],   AuthorNameNormalizer.normalize("Owen| Peter;")
  end

  test "reverses multiple `Last| First` pairs joined with `|`" do
    assert_equal [ "Michael Ignatieff", "Henry Hardy", "Isaiah Berlin" ],
      AuthorNameNormalizer.normalize("Ignatieff| Michael| Hardy| Henry| Berlin| Isaiah")
  end

  test "does not pair-flip when an odd count of tokens makes the pattern ambiguous" do
    # Three single-word tokens — treated as 3 mononyms, not a partial pair.
    assert_equal [ "Plato", "Aristotle", "Socrates" ],
      AuthorNameNormalizer.normalize("Plato | Aristotle | Socrates")
  end

  test "does not pair-flip when some tokens are multi-word" do
    # Mixed shape can't be Last/First pairs — treat as independent names.
    assert_equal [ "Sandi Metz", "Katrina Owen" ],
      AuthorNameNormalizer.normalize("Sandi Metz| Katrina Owen")
  end

  # Comma-form "Last, First" — common Calibre export shape.

  test "reverses `Last, First` to `First Last`" do
    assert_equal [ "Hannah Ritchie" ], AuthorNameNormalizer.normalize("Ritchie, Hannah")
    assert_equal [ "Frank Herbert" ],  AuthorNameNormalizer.normalize("Herbert, Frank")
  end

  test "leaves a name with multiple commas alone (degree suffixes etc.)" do
    # "Smith, John, MD" — we don't know if "MD" is meant as a degree;
    # safer to leave the name as-is than to silently destroy it.
    result = AuthorNameNormalizer.normalize("Smith, John, MD")
    assert_equal [ "Smith, John, MD" ], result
  end

  # Placeholders — drop unhelpful entries.

  test "drops Unknown / Desconocido / Unknown Author placeholders" do
    assert_equal [], AuthorNameNormalizer.normalize("Unknown")
    assert_equal [], AuthorNameNormalizer.normalize("Unknown Author")
    assert_equal [], AuthorNameNormalizer.normalize("Desconocido")
    assert_equal [], AuthorNameNormalizer.normalize("n/a")
  end

  test "drops placeholder names mixed with real names" do
    assert_equal [ "Real Author" ],
      AuthorNameNormalizer.normalize("Real Author| Unknown")
  end

  # Edge cases.

  test "empty / blank input returns empty array" do
    assert_equal [], AuthorNameNormalizer.normalize(nil)
    assert_equal [], AuthorNameNormalizer.normalize("")
    assert_equal [], AuthorNameNormalizer.normalize("   ")
  end

  test "deduplicates identical authors from a single string" do
    assert_equal [ "Robin Hobb" ],
      AuthorNameNormalizer.normalize("Robin Hobb| Robin Hobb")
  end
end
