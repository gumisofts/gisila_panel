// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'webhooks.dart';

// **************************************************************************
// ControllerGenerator
// **************************************************************************

// **************************************************
// gisila_doc: generated for AppWebhookApi
// **************************************************

extension AppWebhookApiGisilaDoc on AppWebhookApi {
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
    spec.putSchema('StatusTokenForm', <String, Object?>{
      'type': 'object',
      'properties': <String, Object?>{
        'token': <String, Object?>{'type': 'string'}
      }
    });
    spec.putTag('Webhooks');
    {
      final basePath = '$prefix/apps/<appId>/webhook/';
      final openApiPath = '$prefix/apps/{appId}/webhook/';
      final RouteConfig __cfg =
          RouteConfig.empty.merge(const RouteConfig(requireAuth: true));
      final __route = gisilaRoute(
        app: app,
        config: __cfg,
        routeId: 'GET $basePath',
        handler: (RequestContext ctx) async {
          final request = ctx.request;
          final (appId, hooks) = await (() async {
            try {
              final appId =
                  coerce<int>(request.params['appId'], 'appId', required: true);
              final hooks = ctx.service<WebhooksService>();
              return (appId, hooks);
            } on TypeError catch (e) {
              throw BadRequestException('Invalid request payload ($e)');
            } on FormatException catch (e) {
              throw BadRequestException('Invalid request format: ${e.message}');
            }
          })();
          final result = await this.status(appId, hooks, ctx);
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
            summary: 'Push-to-deploy webhook status',
            tags: <String>['Webhooks'],
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
      final basePath = '$prefix/apps/<appId>/webhook/';
      final openApiPath = '$prefix/apps/{appId}/webhook/';
      final RouteConfig __cfg =
          RouteConfig.empty.merge(const RouteConfig(requireAuth: true));
      final __route = gisilaRoute(
        app: app,
        config: __cfg,
        routeId: 'POST $basePath',
        handler: (RequestContext ctx) async {
          final request = ctx.request;
          final (appId, hooks) = await (() async {
            try {
              final appId =
                  coerce<int>(request.params['appId'], 'appId', required: true);
              final hooks = ctx.service<WebhooksService>();
              return (appId, hooks);
            } on TypeError catch (e) {
              throw BadRequestException('Invalid request payload ($e)');
            } on FormatException catch (e) {
              throw BadRequestException('Invalid request format: ${e.message}');
            }
          })();
          final result = await this.enable(appId, hooks, ctx);
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
            summary: 'Create the webhook or rotate its secret',
            tags: <String>['Webhooks'],
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
      final basePath = '$prefix/apps/<appId>/webhook/';
      final openApiPath = '$prefix/apps/{appId}/webhook/';
      final RouteConfig __cfg =
          RouteConfig.empty.merge(const RouteConfig(requireAuth: true));
      final __route = gisilaRoute(
        app: app,
        config: __cfg,
        routeId: 'DELETE $basePath',
        handler: (RequestContext ctx) async {
          final request = ctx.request;
          final (appId, hooks) = await (() async {
            try {
              final appId =
                  coerce<int>(request.params['appId'], 'appId', required: true);
              final hooks = ctx.service<WebhooksService>();
              return (appId, hooks);
            } on TypeError catch (e) {
              throw BadRequestException('Invalid request payload ($e)');
            } on FormatException catch (e) {
              throw BadRequestException('Invalid request format: ${e.message}');
            }
          })();
          final result = await this.disable(appId, hooks, ctx);
          return jsonResponse(body: result, statusCode: 204);
        },
      );
      router.delete(basePath, __route);
      if (basePath.length > 1) {
        router.delete(basePath.substring(0, basePath.length - 1), __route);
      }
      spec.putOperation(
          openApiPath,
          'delete',
          Operation(
            summary: 'Remove the webhook',
            tags: <String>['Webhooks'],
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
    {
      final basePath = '$prefix/apps/<appId>/webhook/status-token';
      final openApiPath = '$prefix/apps/{appId}/webhook/status-token';
      final RouteConfig __cfg =
          RouteConfig.empty.merge(const RouteConfig(requireAuth: true));
      final __route = gisilaRoute(
        app: app,
        config: __cfg,
        routeId: 'PUT $basePath',
        handler: (RequestContext ctx) async {
          final request = ctx.request;
          final (appId, form, hooks) = await (() async {
            try {
              final appId =
                  coerce<int>(request.params['appId'], 'appId', required: true);
              final form = await bindForm(request, StatusTokenForm.new);
              final hooks = ctx.service<WebhooksService>();
              return (appId, form, hooks);
            } on TypeError catch (e) {
              throw BadRequestException('Invalid request payload ($e)');
            } on FormatException catch (e) {
              throw BadRequestException('Invalid request format: ${e.message}');
            }
          })();
          final result = await this.setStatusToken(appId, form, hooks, ctx);
          return jsonResponse(body: result, statusCode: 200);
        },
      );
      router.put(basePath, __route);
      spec.putOperation(
          openApiPath,
          'put',
          Operation(
            summary: 'Set the token for commit statuses',
            tags: <String>['Webhooks'],
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
                r'$ref': '#/components/schemas/StatusTokenForm'
              }),
              'application/x-www-form-urlencoded': MediaType(
                  schema: <String, Object?>{
                    r'$ref': '#/components/schemas/StatusTokenForm'
                  })
            }),
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
      final basePath = '$prefix/apps/<appId>/webhook/status-token';
      final openApiPath = '$prefix/apps/{appId}/webhook/status-token';
      final RouteConfig __cfg =
          RouteConfig.empty.merge(const RouteConfig(requireAuth: true));
      final __route = gisilaRoute(
        app: app,
        config: __cfg,
        routeId: 'DELETE $basePath',
        handler: (RequestContext ctx) async {
          final request = ctx.request;
          final (appId, hooks) = await (() async {
            try {
              final appId =
                  coerce<int>(request.params['appId'], 'appId', required: true);
              final hooks = ctx.service<WebhooksService>();
              return (appId, hooks);
            } on TypeError catch (e) {
              throw BadRequestException('Invalid request payload ($e)');
            } on FormatException catch (e) {
              throw BadRequestException('Invalid request format: ${e.message}');
            }
          })();
          final result = await this.clearStatusToken(appId, hooks, ctx);
          return jsonResponse(body: result, statusCode: 204);
        },
      );
      router.delete(basePath, __route);
      spec.putOperation(
          openApiPath,
          'delete',
          Operation(
            summary: 'Stop reporting commit statuses',
            tags: <String>['Webhooks'],
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

// **************************************************
// gisila_doc: generated for WebhookDeliveryApi
// **************************************************

extension WebhookDeliveryApiGisilaDoc on WebhookDeliveryApi {
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
    spec.putTag('Webhooks');
    {
      final basePath = '$prefix/webhooks/apps/<appId>';
      final openApiPath = '$prefix/webhooks/apps/{appId}';
      final RouteConfig __cfg = RouteConfig.empty
          .merge(const RouteConfig(isPublic: true))
          .merge(const RouteConfig(
              rateLimit: const RateLimitConfig(requestsPerMinute: 120),
              maxBodyBytes: 5242880));
      final __route = gisilaRoute(
        app: app,
        config: __cfg,
        routeId: 'POST $basePath',
        handler: (RequestContext ctx) async {
          final request = ctx.request;
          final (appId, hooks) = await (() async {
            try {
              final appId =
                  coerce<int>(request.params['appId'], 'appId', required: true);
              final hooks = ctx.service<WebhooksService>();
              return (appId, hooks);
            } on TypeError catch (e) {
              throw BadRequestException('Invalid request payload ($e)');
            } on FormatException catch (e) {
              throw BadRequestException('Invalid request format: ${e.message}');
            }
          })();
          final response = await this.deliver(appId, request, hooks);
          return response;
        },
      );
      router.post(basePath, __route);
      spec.putOperation(
          openApiPath,
          'post',
          Operation(
            summary: 'Receive a push and deploy it',
            tags: <String>['Webhooks'],
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
              '201': ResponseSpec(description: 'Created'),
              '400': ResponseSpec(description: 'Bad Request', content: {
                'application/json': MediaType(schema: errorEnvelopeSchema)
              })
            },
          ));
    }
  }
}
