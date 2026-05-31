/// Generate URL-safe slugs from arbitrary input.
class Slug {
  static final _spaces = RegExp(r'\s+');
  static final _nonSlug = RegExp(r'[^a-z0-9\-]');
  static final _dashes = RegExp(r'-+');

  static String make(String input) {
    final base = input
        .toLowerCase()
        .trim()
        .replaceAll(_spaces, '-')
        .replaceAll(_nonSlug, '')
        .replaceAll(_dashes, '-');
    return base.isEmpty ? 'app' : base.replaceAll(RegExp(r'^-+|-+$'), '');
  }
}
