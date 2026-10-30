// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'system.dart';

// **************************************************************************
// ControllerGenerator
// **************************************************************************

// **************************************************
// gisila_doc: generated for SystemApi
// **************************************************

extension SystemApiGisilaDoc on SystemApi {
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
    spec.putTag('System');
    {
      final basePath = '$prefix/system/info';
      final openApiPath = '$prefix/system/info';
      final RouteConfig __cfg =
          RouteConfig.empty.merge(const RouteConfig(requireAuth: true));
      final __route = gisilaRoute(
        app: app,
        config: __cfg,
        routeId: 'GET $basePath',
        handler: (RequestContext ctx) async {
          final result = await this.info(ctx);
          return jsonResponse(body: result, statusCode: 200);
        },
      );
      router.get(basePath, __route);
      spec.putOperation(
          openApiPath,
          'get',
          Operation(
            summary: 'Server addresses and the running Gisila version',
            tags: <String>['System'],
            parameters: <Parameter>[],
            responses: <String, ResponseSpec>{
              '200': ResponseSpec(description: 'OK', content: {
                'application/json': MediaType(schema: <String, Object?>{
                  'type': 'object',
                  'additionalProperties': <String, Object?>{}
                })
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
