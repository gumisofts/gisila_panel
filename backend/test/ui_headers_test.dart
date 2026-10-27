import 'package:gisila_panel/infra/ui_headers.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

Request _get(String path, {String? host}) =>
    Request('GET', Uri.parse('http://panel.test$path'),
        headers: {if (host != null) 'host': host});

void main() {
  test('scripts only from the panel, never framed', () {
    final csp = panelUiHeaders(_get('/'))['content-security-policy']!;
    expect(csp, contains("script-src 'self';"));
    expect(csp, isNot(contains('unsafe-eval')));
    expect(csp, contains("frame-ancestors 'none'"));
    expect(csp, contains("object-src 'none'"));
  });

  test('allows the log sockets on the same host only', () {
    final csp = panelUiHeaders(
        _get('/', host: 'panel.example.com'))['content-security-policy']!;
    expect(
        csp,
        contains(
            "connect-src 'self' wss://panel.example.com ws://panel.example.com;"));
  });

  test('a malformed Host header cannot add sources', () {
    final csp = panelUiHeaders(
        _get('/', host: "x; script-src *"))['content-security-policy']!;
    expect(csp, contains("connect-src 'self';"));
    expect(csp, isNot(contains('script-src *')));
  });

  test('only HTML responses get the headers', () async {
    final handler = withPanelUiHeaders((r) => r.url.path.endsWith('.js')
        ? Response.ok('x', headers: {'content-type': 'text/javascript'})
        : Response.ok('<html>',
            headers: {'content-type': 'text/html; charset=utf-8'}));
    final html = await handler(_get('/apps'));
    final js = await handler(_get('/assets/a.js'));
    expect(html.headers['content-security-policy'], isNotNull);
    expect(html.headers['x-frame-options'], 'DENY');
    expect(js.headers['content-security-policy'], isNull);
  });
}
