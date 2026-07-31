// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'applications.dart';

// **************************************************************************
// ControllerGenerator
// **************************************************************************

// **************************************************
// gisila_doc: generated for ApplicationsApi
// **************************************************

extension ApplicationsApiGisilaDoc on ApplicationsApi {
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
    spec.putSchema('InstallApplicationForm', <String, Object?>{
      'type': 'object',
      'properties': <String, Object?>{
        'key': <String, Object?>{'type': 'string'},
        'version': <String, Object?>{'type': 'string'}
      }
    });
    spec.putSchema('UpdateApplicationForm', <String, Object?>{
      'type': 'object',
      'properties': <String, Object?>{
        'defaultVersion': <String, Object?>{'type': 'string'},
        'defaultDeployMode': <String, Object?>{'type': 'string'},
        'defaultBuildCommand': <String, Object?>{'type': 'string'},
        'defaultStartCommand': <String, Object?>{'type': 'string'}
      }
    });
    spec.putTag('Applications');
    {
      final basePath = '$prefix/applications/catalog';
      final openApiPath = '$prefix/applications/catalog';
      final RouteConfig __cfg =
          RouteConfig.empty.merge(const RouteConfig(requireAuth: true));
      router.get(
          basePath,
          gisilaRoute(
            app: app,
            config: __cfg,
            handler: (RequestContext ctx) async {
              try {
                final svc = ctx.service<ApplicationService>();
                final result = await this.catalog(svc);
                return jsonResponse(body: result, statusCode: 200);
              } on TypeError catch (e) {
                throw BadRequestException('Invalid request payload ($e)');
              } on FormatException catch (e) {
                throw BadRequestException(
                    'Invalid request format: ${e.message}');
              }
            },
          ));
      spec.putOperation(
          openApiPath,
          'get',
          Operation(
            summary: 'List builtin Application definitions',
            tags: <String>['Applications'],
            parameters: <Parameter>[],
            responses: <String, ResponseSpec>{
              '200': ResponseSpec(description: 'OK', content: {
                'application/json': MediaType(schema: <String, Object?>{
                  'type': 'object',
                  'additionalProperties': <String, Object?>{}
                })
              })
            },
          ));
    }
    {
      final basePath = '$prefix/applications/';
      final openApiPath = '$prefix/applications/';
      final RouteConfig __cfg =
          RouteConfig.empty.merge(const RouteConfig(requireAuth: true));
      router.get(
          basePath,
          gisilaRoute(
            app: app,
            config: __cfg,
            handler: (RequestContext ctx) async {
              try {
                final svc = ctx.service<ApplicationService>();
                final result = await this.list(svc);
                return jsonResponse(body: result, statusCode: 200);
              } on TypeError catch (e) {
                throw BadRequestException('Invalid request payload ($e)');
              } on FormatException catch (e) {
                throw BadRequestException(
                    'Invalid request format: ${e.message}');
              }
            },
          ));
      spec.putOperation(
          openApiPath,
          'get',
          Operation(
            summary: 'List installed Applications',
            tags: <String>['Applications'],
            parameters: <Parameter>[],
            responses: <String, ResponseSpec>{
              '200': ResponseSpec(description: 'OK', content: {
                'application/json': MediaType(schema: <String, Object?>{
                  'type': 'object',
                  'additionalProperties': <String, Object?>{}
                })
              })
            },
          ));
    }
    {
      final basePath = '$prefix/applications/';
      final openApiPath = '$prefix/applications/';
      final RouteConfig __cfg =
          RouteConfig.empty.merge(const RouteConfig(requireAuth: true));
      router.post(
          basePath,
          gisilaRoute(
            app: app,
            config: __cfg,
            handler: (RequestContext ctx) async {
              try {
                final request = ctx.request;
                final form =
                    await bindForm(request, InstallApplicationForm.new);
                final svc = ctx.service<ApplicationService>();
                final result = await this.install(form, svc, ctx);
                return jsonResponse(body: result, statusCode: 201);
              } on TypeError catch (e) {
                throw BadRequestException('Invalid request payload ($e)');
              } on FormatException catch (e) {
                throw BadRequestException(
                    'Invalid request format: ${e.message}');
              }
            },
          ));
      spec.putOperation(
          openApiPath,
          'post',
          Operation(
            summary: 'Install an Application',
            tags: <String>['Applications'],
            parameters: <Parameter>[],
            requestBody: RequestBody(required: true, content: {
              'application/json': MediaType(schema: <String, Object?>{
                r'$ref': '#/components/schemas/InstallApplicationForm'
              })
            }),
            responses: <String, ResponseSpec>{
              '201': ResponseSpec(description: 'Created', content: {
                'application/json': MediaType(schema: <String, Object?>{
                  'type': 'object',
                  'additionalProperties': <String, Object?>{}
                })
              })
            },
          ));
    }
    {
      final basePath = '$prefix/applications/<id>';
      final openApiPath = '$prefix/applications/{id}';
      final RouteConfig __cfg =
          RouteConfig.empty.merge(const RouteConfig(requireAuth: true));
      router.get(
          basePath,
          gisilaRoute(
            app: app,
            config: __cfg,
            handler: (RequestContext ctx) async {
              try {
                final request = ctx.request;
                final id =
                    coerce<int>(request.params['id'], 'id', required: true);
                final svc = ctx.service<ApplicationService>();
                final result = await this.retrieve(id, svc);
                return jsonResponse(body: result, statusCode: 200);
              } on TypeError catch (e) {
                throw BadRequestException('Invalid request payload ($e)');
              } on FormatException catch (e) {
                throw BadRequestException(
                    'Invalid request format: ${e.message}');
              }
            },
          ));
      spec.putOperation(
          openApiPath,
          'get',
          Operation(
            summary: 'Get an Application',
            tags: <String>['Applications'],
            parameters: <Parameter>[
              Parameter(
                name: 'id',
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
              })
            },
          ));
    }
    {
      final basePath = '$prefix/applications/<id>';
      final openApiPath = '$prefix/applications/{id}';
      final RouteConfig __cfg =
          RouteConfig.empty.merge(const RouteConfig(requireAuth: true));
      router.patch(
          basePath,
          gisilaRoute(
            app: app,
            config: __cfg,
            handler: (RequestContext ctx) async {
              try {
                final request = ctx.request;
                final id =
                    coerce<int>(request.params['id'], 'id', required: true);
                final form = await bindForm(request, UpdateApplicationForm.new);
                final svc = ctx.service<ApplicationService>();
                final result = await this.update(id, form, svc, ctx);
                return jsonResponse(body: result, statusCode: 200);
              } on TypeError catch (e) {
                throw BadRequestException('Invalid request payload ($e)');
              } on FormatException catch (e) {
                throw BadRequestException(
                    'Invalid request format: ${e.message}');
              }
            },
          ));
      spec.putOperation(
          openApiPath,
          'patch',
          Operation(
            summary: 'Update an Application\'s deployment defaults',
            tags: <String>['Applications'],
            parameters: <Parameter>[
              Parameter(
                name: 'id',
                location: 'path',
                required: true,
                description: null,
                schema: <String, Object?>{'type': 'integer', 'format': 'int64'},
              )
            ],
            requestBody: RequestBody(required: true, content: {
              'application/json': MediaType(schema: <String, Object?>{
                r'$ref': '#/components/schemas/UpdateApplicationForm'
              })
            }),
            responses: <String, ResponseSpec>{
              '200': ResponseSpec(description: 'OK', content: {
                'application/json': MediaType(schema: <String, Object?>{
                  'type': 'object',
                  'additionalProperties': <String, Object?>{}
                })
              })
            },
          ));
    }
    {
      final basePath = '$prefix/applications/<id>';
      final openApiPath = '$prefix/applications/{id}';
      final RouteConfig __cfg =
          RouteConfig.empty.merge(const RouteConfig(requireAuth: true));
      router.delete(
          basePath,
          gisilaRoute(
            app: app,
            config: __cfg,
            handler: (RequestContext ctx) async {
              try {
                final request = ctx.request;
                final id =
                    coerce<int>(request.params['id'], 'id', required: true);
                final svc = ctx.service<ApplicationService>();
                final result = await this.remove(id, svc, ctx);
                return jsonResponse(body: result, statusCode: 204);
              } on TypeError catch (e) {
                throw BadRequestException('Invalid request payload ($e)');
              } on FormatException catch (e) {
                throw BadRequestException(
                    'Invalid request format: ${e.message}');
              }
            },
          ));
      spec.putOperation(
          openApiPath,
          'delete',
          Operation(
            summary: 'Remove an Application',
            tags: <String>['Applications'],
            parameters: <Parameter>[
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
              })
            },
          ));
    }
  }
}
