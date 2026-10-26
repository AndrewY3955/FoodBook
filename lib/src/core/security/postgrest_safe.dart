/// Guards for values that end up inside a PostgREST filter expression.
///
/// WHY THIS EXISTS
///
/// The Supabase SDK parameterises SQL, so classic SQL injection is not
/// reachable from this client. But `.or(...)` and the pattern argument
/// to `.ilike(...)` are not parameters — they are a small filter
/// grammar that PostgREST parses, where `,` separates terms, `.`
/// separates column-operator-value, `(` and `)` group, and `*` is the
/// wildcard. A value carrying those characters stops being data and
/// becomes syntax.
///
/// That is not SQL injection, and it cannot read another tenant's rows
/// on its own, because RLS is applied after the filter is parsed and a
/// policy predicate cannot be switched off by a query parameter. The
/// proof is in supabase/tests/rls_negative_control.sql section 10,
/// which runs a deliberately injected filter as an unrelated user and
/// asserts zero rows.
///
/// So this is defence in depth, not the defence. It stops a crafted
/// value from widening a query in ways we did not intend — returning a
/// user their *own* data under conditions the UI never offers, skewing
/// a count, or provoking an error that leaks a column name.
class PostgrestSafe {
  const PostgrestSafe._();

  static final RegExp _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
    r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  /// Every character with meaning in the PostgREST filter grammar, plus
  /// the LIKE wildcards.
  static final RegExp _filterMeta = RegExp(r'''[,.()*%\\"'\[\]{}:]''');

  /// Returns the id only if it is a well-formed UUID.
  ///
  /// Interpolating an id into `.or()` is safe exactly as long as the id
  /// is a UUID and nothing else. Rather than trusting that it came from
  /// our own state — which is true today and one refactor away from
  /// being false — the shape is checked at the point of use.
  static String? uuid(String? value) {
    if (value == null) return null;
    return _uuid.hasMatch(value) ? value : null;
  }

  /// Throws rather than silently querying the wrong thing. A malformed
  /// tenant id is a bug or an attack; neither should produce results.
  static String requireUuid(String? value, String label) {
    final String? checked = uuid(value);
    if (checked == null) {
      throw ArgumentError('$label is not a valid identifier');
    }
    return checked;
  }

  /// Strips every filter-grammar and wildcard character from free text
  /// before it is used as an ilike pattern.
  ///
  /// The cost is that a search for "St. John's" also matches
  /// "St John s" — acceptable for ingredient and recipe names, and the
  /// trigram index does not care about punctuation anyway.
  static String likeTerm(String value, {int maxLength = 60}) {
    final String stripped = value
        .replaceAll(_filterMeta, ' ')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();
    return stripped.length <= maxLength
        ? stripped
        : stripped.substring(0, maxLength).trim();
  }

  /// Builds `%term%` only when the term survived stripping.
  static String? likePattern(String value, {int maxLength = 60}) {
    final String term = likeTerm(value, maxLength: maxLength);
    return term.isEmpty ? null : '%$term%';
  }
}
