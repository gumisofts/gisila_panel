// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'runtime_logs.dart';

// **************************************************************************
// ControllerGenerator
// **************************************************************************

// **************************************************
// gisila_doc: generated for RuntimeLogsApi
// **************************************************

extension RuntimeLogsApiGisilaDoc on RuntimeLogsApi {
  /// Registers every annotated route of this controller on
  /// [router] (through `gisilaRoute(...)` so the route runs
  /// through the same MVC pipeline as gisila core) and
  /// contributes the matching operations / schemas / tags
  /// to [spec].
  ///
  /// Pass [prefix] to mount the controller under an extra
  /// path segment (e.g. an `/api/v1` versioning prefix).
  void attachToApp(
    GisilaApp app,
    Router router,
    OpenApiSpec spec, {
    String prefix = '',
  }) {
    spec.putTag('Logs');
    {
      final basePath = '$prefix/apps/<appId>/runtime-logs/';
      final openApiPath = '$prefix/apps/{appId}/runtime-logs/';
      final RouteConfig __cfg =
          RouteConfig.empty.merge(const RouteConfig(requireAuth: true));
      final __route = gisilaRoute(
        app: app,
        config: __cfg,
        routeId: 'GET $basePath',
        handler: (RequestContext ctx) async {
          final request = ctx.request;
          final (appId, apps, lines) = await (() async {
            try {
              final appId =
                  coerce<int>(request.params['appId'], 'appId', required: true);
              final apps = ctx.service<AppsService>();
              final lines = coerce<int?>(
                  request.url.queryParameters['lines'], 'lines',
                  required: false);
              return (appId, apps, lines);
            } on TypeError catch (e) {
              throw BadRequestException('Invalid request payload ($e)');
            } on FormatException catch (e) {
              throw BadRequestException('Invalid request format: ${e.message}');
            }
          })();
          final result = await this.tail(appId, apps, ctx, lines: lines);
          return jsonResponse(body: result, statusCode: 200);
        },
      );
      router.get(basePath, __route);
      if (basePath.length > 1) {
        router.get(basePath.substring(0, basePath.length - 1), __route);
      }
      spec.putOperation(
          openApiPath,
          'get',
          Operation(
            summary: 'Recent runtime log lines of an app',
            tags: <String>['Logs'],
            parameters: <Parameter>[
              Parameter(
                name: 'appId',
                location: 'path',
                required: true,
                description: null,
                schema: <String, Object?>{'type': 'integer', 'format': 'int64'},
              ),
              Parameter(
                name: 'lines',
                location: 'query',
                required: false,
                description: null,
                schema: <String, Object?>{
                  'type': <Object?>['integer', 'null'],
                  'format': 'int64'
                },
              )
            ],
            responses: <String, ResponseSpec>{
              '200': ResponseSpec(description: 'OK', content: {
                'application/json': MediaType(schema: <String, Object?>{
                  'type': 'object',
                  'additionalProperties': <String, Object?>{}
                })
              }),
              '400': ResponseSpec(description: 'Bad Request', content: {
                'application/json': MediaType(schema: errorEnvelopeSchema)
              }),
              '401': ResponseSpec(description: 'Unauthorized', content: {
                'application/json': MediaType(schema: errorEnvelopeSchema)
              })
            },
            requiresAuth: true,
          ));
    }
  }
}
