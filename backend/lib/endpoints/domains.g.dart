// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'domains.dart';

// **************************************************************************
// ControllerGenerator
// **************************************************************************

// **************************************************
// gisila_doc: generated for DomainsApi
// **************************************************

extension DomainsApiGisilaDoc on DomainsApi {
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
    spec.putSchema('AddDomainForm', <String, Object?>{
      'type': 'object',
      'properties': <String, Object?>{
        'hostname': <String, Object?>{'type': 'string'},
        'isPrimary': <String, Object?>{'type': 'boolean'}
      }
    });
    spec.putTag('Domains');
    {
      final basePath = '$prefix/apps/<appId>/domains/';
      final openApiPath = '$prefix/apps/{appId}/domains/';
      final RouteConfig __cfg =
          RouteConfig.empty.merge(const RouteConfig(requireAuth: true));
      final __route = gisilaRoute(
        app: app,
        config: __cfg,
        routeId: 'GET $basePath',
        handler: (RequestContext ctx) async {
          final request = ctx.request;
          final (appId, domains) = await (() async {
            try {
              final appId =
                  coerce<int>(request.params['appId'], 'appId', required: true);
              final domains = ctx.service<DomainsService>();
              return (appId, domains);
            } on TypeError catch (e) {
              throw BadRequestException('Invalid request payload ($e)');
            } on FormatException catch (e) {
              throw BadRequestException('Invalid request format: ${e.message}');
            }
          })();
          final result = await this.list(appId, domains, ctx);
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
            summary: 'List domains',
            tags: <String>['Domains'],
            parameters: <Parameter>[
              Parameter(
                name: 'appId',
                location: 'path',
                required: true,
                description: null,
                schema: <String, Object?>{'type': 'integer', 'format': 'int64'},
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
    {
      final basePath = '$prefix/apps/<appId>/domains/';
      final openApiPath = '$prefix/apps/{appId}/domains/';
      final RouteConfig __cfg =
          RouteConfig.empty.merge(const RouteConfig(requireAuth: true));
      final __route = gisilaRoute(
        app: app,
        config: __cfg,
        routeId: 'POST $basePath',
        handler: (RequestContext ctx) async {
          final request = ctx.request;
          final (appId, form, domains) = await (() async {
            try {
              final appId =
                  coerce<int>(request.params['appId'], 'appId', required: true);
              final form = await bindForm(request, AddDomainForm.new);
              final domains = ctx.service<DomainsService>();
              return (appId, form, domains);
            } on TypeError catch (e) {
              throw BadRequestException('Invalid request payload ($e)');
            } on FormatException catch (e) {
              throw BadRequestException('Invalid request format: ${e.message}');
            }
          })();
          final result = await this.add(appId, form, domains, ctx);
          return jsonResponse(body: result, statusCode: 201);
        },
      );
      router.post(basePath, __route);
      if (basePath.length > 1) {
        router.post(basePath.substring(0, basePath.length - 1), __route);
      }
      spec.putOperation(
          openApiPath,
          'post',
          Operation(
            summary: 'Attach a custom domain',
            tags: <String>['Domains'],
            parameters: <Parameter>[
              Parameter(
                name: 'appId',
                location: 'path',
                required: true,
                description: null,
                schema: <String, Object?>{'type': 'integer', 'format': 'int64'},
              )
            ],
            requestBody: RequestBody(required: true, content: {
              'application/json': MediaType(schema: <String, Object?>{
                r'$ref': '#/components/schemas/AddDomainForm'
              }),
              'application/x-www-form-urlencoded': MediaType(
                  schema: <String, Object?>{
                    r'$ref': '#/components/schemas/AddDomainForm'
                  })
            }),
            responses: <String, ResponseSpec>{
              '201': ResponseSpec(description: 'Created', content: {
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
    {
      final basePath = '$prefix/apps/<appId>/domains/<id>/ssl';
      final openApiPath = '$prefix/apps/{appId}/domains/{id}/ssl';
      final RouteConfig __cfg =
          RouteConfig.empty.merge(const RouteConfig(requireAuth: true));
      final __route = gisilaRoute(
        app: app,
        config: __cfg,
        routeId: 'POST $basePath',
        handler: (RequestContext ctx) async {
          final request = ctx.request;
          final (appId, id, domains) = await (() async {
            try {
              final appId =
                  coerce<int>(request.params['appId'], 'appId', required: true);
              final id =
                  coerce<int>(request.params['id'], 'id', required: true);
              final domains = ctx.service<DomainsService>();
              return (appId, id, domains);
            } on TypeError catch (e) {
              throw BadRequestException('Invalid request payload ($e)');
            } on FormatException catch (e) {
              throw BadRequestException('Invalid request format: ${e.message}');
            }
          })();
          final result = await this.issueCert(appId, id, domains, ctx);
          return jsonResponse(body: result, statusCode: 201);
        },
      );
      router.post(basePath, __route);
      spec.putOperation(
          openApiPath,
          'post',
          Operation(
            summary: 'Issue or renew a Let\'s Encrypt certificate',
            tags: <String>['Domains'],
            parameters: <Parameter>[
              Parameter(
                name: 'appId',
                location: 'path',
                required: true,
                description: null,
                schema: <String, Object?>{'type': 'integer', 'format': 'int64'},
              ),
              Parameter(
                name: 'id',
                location: 'path',
                required: true,
                description: null,
                schema: <String, Object?>{'type': 'integer', 'format': 'int64'},
              )
            ],
            responses: <String, ResponseSpec>{
              '201': ResponseSpec(description: 'Created', content: {
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
    {
      final basePath = '$prefix/apps/<appId>/domains/<id>';
      final openApiPath = '$prefix/apps/{appId}/domains/{id}';
      final RouteConfig __cfg =
          RouteConfig.empty.merge(const RouteConfig(requireAuth: true));
      final __route = gisilaRoute(
        app: app,
        config: __cfg,
        routeId: 'DELETE $basePath',
        handler: (RequestContext ctx) async {
          final request = ctx.request;
          final (appId, id, domains) = await (() async {
            try {
              final appId =
                  coerce<int>(request.params['appId'], 'appId', required: true);
              final id =
                  coerce<int>(request.params['id'], 'id', required: true);
              final domains = ctx.service<DomainsService>();
              return (appId, id, domains);
            } on TypeError catch (e) {
              throw BadRequestException('Invalid request payload ($e)');
            } on FormatException catch (e) {
              throw BadRequestException('Invalid request format: ${e.message}');
            }
          })();
          final result = await this.remove(appId, id, domains, ctx);
          return jsonResponse(body: result, statusCode: 204);
        },
      );
      router.delete(basePath, __route);
      spec.putOperation(
          openApiPath,
          'delete',
          Operation(
            summary: 'Remove a domain',
            tags: <String>['Domains'],
            parameters: <Parameter>[
              Parameter(
                name: 'appId',
                location: 'path',
                required: true,
                description: null,
                schema: <String, Object?>{'type': 'integer', 'format': 'int64'},
              ),
              Parameter(
                name: 'id',
                location: 'path',
                required: true,
                description: null,
                schema: <String, Object?>{'type': 'integer', 'format': 'int64'},
              )
            ],
            responses: <String, ResponseSpec>{
              '204': ResponseSpec(description: 'No Content', content: {
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
