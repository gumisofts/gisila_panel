// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'stacks.dart';

// **************************************************************************
// ControllerGenerator
// **************************************************************************

// **************************************************
// gisila_doc: generated for StacksApi
// **************************************************

extension StacksApiGisilaDoc on StacksApi {
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
    spec.putSchema('CreateStackForm', <String, Object?>{
      'type': 'object',
      'properties': <String, Object?>{
        'projectId': <String, Object?>{'type': 'integer', 'format': 'int64'},
        'name': <String, Object?>{'type': 'string'},
        'description': <String, Object?>{'type': 'string'}
      }
    });
    spec.putSchema('UpdateStackForm', <String, Object?>{
      'type': 'object',
      'properties': <String, Object?>{
        'name': <String, Object?>{'type': 'string'},
        'description': <String, Object?>{'type': 'string'}
      }
    });
    spec.putSchema('EnvVarForm', <String, Object?>{
      'type': 'object',
      'properties': <String, Object?>{
        'name': <String, Object?>{'type': 'string'},
        'value': <String, Object?>{'type': 'string'},
        'isSecret': <String, Object?>{'type': 'boolean'}
      }
    });
    spec.putSchema('BulkEnvVarForm', <String, Object?>{
      'type': 'object',
      'properties': <String, Object?>{
        'entries': <String, Object?>{'type': 'object'}
      }
    });
    spec.putTag('Stacks');
    {
      final basePath = '$prefix/stacks/';
      final openApiPath = '$prefix/stacks/';
      final RouteConfig __cfg =
          RouteConfig.empty.merge(const RouteConfig(requireAuth: true));
      final __route = gisilaRoute(
        app: app,
        config: __cfg,
        routeId: 'GET $basePath',
        handler: (RequestContext ctx) async {
          final request = ctx.request;
          final (stacks, projectId) = await (() async {
            try {
              final stacks = ctx.service<StacksService>();
              final projectId = coerce<int?>(
                  request.url.queryParameters['projectId'], 'projectId',
                  required: false);
              return (stacks, projectId);
            } on TypeError catch (e) {
              throw BadRequestException('Invalid request payload ($e)');
            } on FormatException catch (e) {
              throw BadRequestException('Invalid request format: ${e.message}');
            }
          })();
          final result = await this.list(stacks, ctx, projectId);
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
            summary: 'List stacks, optionally for one project',
            tags: <String>['Stacks'],
            parameters: <Parameter>[
              Parameter(
                name: 'projectId',
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
    {
      final basePath = '$prefix/stacks/';
      final openApiPath = '$prefix/stacks/';
      final RouteConfig __cfg =
          RouteConfig.empty.merge(const RouteConfig(requireAuth: true));
      final __route = gisilaRoute(
        app: app,
        config: __cfg,
        routeId: 'POST $basePath',
        handler: (RequestContext ctx) async {
          final request = ctx.request;
          final (form, stacks) = await (() async {
            try {
              final form = await bindForm(request, CreateStackForm.new);
              final stacks = ctx.service<StacksService>();
              return (form, stacks);
            } on TypeError catch (e) {
              throw BadRequestException('Invalid request payload ($e)');
            } on FormatException catch (e) {
              throw BadRequestException('Invalid request format: ${e.message}');
            }
          })();
          final result = await this.create(form, stacks, ctx);
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
            summary: 'Create a stack in a project',
            tags: <String>['Stacks'],
            parameters: <Parameter>[],
            requestBody: RequestBody(required: true, content: {
              'application/json': MediaType(schema: <String, Object?>{
                r'$ref': '#/components/schemas/CreateStackForm'
              }),
              'application/x-www-form-urlencoded': MediaType(
                  schema: <String, Object?>{
                    r'$ref': '#/components/schemas/CreateStackForm'
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
      final basePath = '$prefix/stacks/<id>';
      final openApiPath = '$prefix/stacks/{id}';
      final RouteConfig __cfg =
          RouteConfig.empty.merge(const RouteConfig(requireAuth: true));
      final __route = gisilaRoute(
        app: app,
        config: __cfg,
        routeId: 'GET $basePath',
        handler: (RequestContext ctx) async {
          final request = ctx.request;
          final (id, stacks) = await (() async {
            try {
              final id =
                  coerce<int>(request.params['id'], 'id', required: true);
              final stacks = ctx.service<StacksService>();
              return (id, stacks);
            } on TypeError catch (e) {
              throw BadRequestException('Invalid request payload ($e)');
            } on FormatException catch (e) {
              throw BadRequestException('Invalid request format: ${e.message}');
            }
          })();
          final result = await this.retrieve(id, stacks, ctx);
          return jsonResponse(body: result, statusCode: 200);
        },
      );
      router.get(basePath, __route);
      spec.putOperation(
          openApiPath,
          'get',
          Operation(
            summary: 'Get a stack',
            tags: <String>['Stacks'],
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
      final basePath = '$prefix/stacks/<id>';
      final openApiPath = '$prefix/stacks/{id}';
      final RouteConfig __cfg =
          RouteConfig.empty.merge(const RouteConfig(requireAuth: true));
      final __route = gisilaRoute(
        app: app,
        config: __cfg,
        routeId: 'PATCH $basePath',
        handler: (RequestContext ctx) async {
          final request = ctx.request;
          final (id, form, stacks) = await (() async {
            try {
              final id =
                  coerce<int>(request.params['id'], 'id', required: true);
              final form = await bindForm(request, UpdateStackForm.new);
              final stacks = ctx.service<StacksService>();
              return (id, form, stacks);
            } on TypeError catch (e) {
              throw BadRequestException('Invalid request payload ($e)');
            } on FormatException catch (e) {
              throw BadRequestException('Invalid request format: ${e.message}');
            }
          })();
          final result = await this.update(id, form, stacks, ctx);
          return jsonResponse(body: result, statusCode: 200);
        },
      );
      router.patch(basePath, __route);
      spec.putOperation(
          openApiPath,
          'patch',
          Operation(
            summary: 'Rename or describe a stack',
            tags: <String>['Stacks'],
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
                r'$ref': '#/components/schemas/UpdateStackForm'
              }),
              'application/x-www-form-urlencoded': MediaType(
                  schema: <String, Object?>{
                    r'$ref': '#/components/schemas/UpdateStackForm'
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
      final basePath = '$prefix/stacks/<id>';
      final openApiPath = '$prefix/stacks/{id}';
      final RouteConfig __cfg =
          RouteConfig.empty.merge(const RouteConfig(requireAuth: true));
      final __route = gisilaRoute(
        app: app,
        config: __cfg,
        routeId: 'DELETE $basePath',
        handler: (RequestContext ctx) async {
          final request = ctx.request;
          final (id, stacks) = await (() async {
            try {
              final id =
                  coerce<int>(request.params['id'], 'id', required: true);
              final stacks = ctx.service<StacksService>();
              return (id, stacks);
            } on TypeError catch (e) {
              throw BadRequestException('Invalid request payload ($e)');
            } on FormatException catch (e) {
              throw BadRequestException('Invalid request format: ${e.message}');
            }
          })();
          final result = await this.delete(id, stacks, ctx);
          return jsonResponse(body: result, statusCode: 204);
        },
      );
      router.delete(basePath, __route);
      spec.putOperation(
          openApiPath,
          'delete',
          Operation(
            summary:
                'Delete a stack and its env vars; its apps are kept, ungrouped',
            tags: <String>['Stacks'],
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
      final basePath = '$prefix/stacks/<id>/apps';
      final openApiPath = '$prefix/stacks/{id}/apps';
      final RouteConfig __cfg =
          RouteConfig.empty.merge(const RouteConfig(requireAuth: true));
      final __route = gisilaRoute(
        app: app,
        config: __cfg,
        routeId: 'GET $basePath',
        handler: (RequestContext ctx) async {
          final request = ctx.request;
          final (id, stacks) = await (() async {
            try {
              final id =
                  coerce<int>(request.params['id'], 'id', required: true);
              final stacks = ctx.service<StacksService>();
              return (id, stacks);
            } on TypeError catch (e) {
              throw BadRequestException('Invalid request payload ($e)');
            } on FormatException catch (e) {
              throw BadRequestException('Invalid request format: ${e.message}');
            }
          })();
          final result = await this.apps(id, stacks, ctx);
          return jsonResponse(body: result, statusCode: 200);
        },
      );
      router.get(basePath, __route);
      spec.putOperation(
          openApiPath,
          'get',
          Operation(
            summary: 'List the apps in a stack',
            tags: <String>['Stacks'],
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
      final basePath = '$prefix/stacks/<id>/envs';
      final openApiPath = '$prefix/stacks/{id}/envs';
      final RouteConfig __cfg =
          RouteConfig.empty.merge(const RouteConfig(requireAuth: true));
      final __route = gisilaRoute(
        app: app,
        config: __cfg,
        routeId: 'GET $basePath',
        handler: (RequestContext ctx) async {
          final request = ctx.request;
          final (id, stacks) = await (() async {
            try {
              final id =
                  coerce<int>(request.params['id'], 'id', required: true);
              final stacks = ctx.service<StacksService>();
              return (id, stacks);
            } on TypeError catch (e) {
              throw BadRequestException('Invalid request payload ($e)');
            } on FormatException catch (e) {
              throw BadRequestException('Invalid request format: ${e.message}');
            }
          })();
          final result = await this.listEnvs(id, stacks, ctx);
          return jsonResponse(body: result, statusCode: 200);
        },
      );
      router.get(basePath, __route);
      spec.putOperation(
          openApiPath,
          'get',
          Operation(
            summary: 'List the env vars a stack shares with its apps',
            tags: <String>['Stacks'],
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
      final basePath = '$prefix/stacks/<id>/envs';
      final openApiPath = '$prefix/stacks/{id}/envs';
      final RouteConfig __cfg =
          RouteConfig.empty.merge(const RouteConfig(requireAuth: true));
      final __route = gisilaRoute(
        app: app,
        config: __cfg,
        routeId: 'POST $basePath',
        handler: (RequestContext ctx) async {
          final request = ctx.request;
          final (id, form, stacks) = await (() async {
            try {
              final id =
                  coerce<int>(request.params['id'], 'id', required: true);
              final form = await bindForm(request, EnvVarForm.new);
              final stacks = ctx.service<StacksService>();
              return (id, form, stacks);
            } on TypeError catch (e) {
              throw BadRequestException('Invalid request payload ($e)');
            } on FormatException catch (e) {
              throw BadRequestException('Invalid request format: ${e.message}');
            }
          })();
          final result = await this.setEnv(id, form, stacks, ctx);
          return jsonResponse(body: result, statusCode: 201);
        },
      );
      router.post(basePath, __route);
      spec.putOperation(
          openApiPath,
          'post',
          Operation(
            summary: 'Set a stack env var',
            tags: <String>['Stacks'],
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
                r'$ref': '#/components/schemas/EnvVarForm'
              }),
              'application/x-www-form-urlencoded': MediaType(
                  schema: <String, Object?>{
                    r'$ref': '#/components/schemas/EnvVarForm'
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
      final basePath = '$prefix/stacks/<id>/envs/bulk';
      final openApiPath = '$prefix/stacks/{id}/envs/bulk';
      final RouteConfig __cfg =
          RouteConfig.empty.merge(const RouteConfig(requireAuth: true));
      final __route = gisilaRoute(
        app: app,
        config: __cfg,
        routeId: 'POST $basePath',
        handler: (RequestContext ctx) async {
          final request = ctx.request;
          final (id, form, stacks) = await (() async {
            try {
              final id =
                  coerce<int>(request.params['id'], 'id', required: true);
              final form = await bindForm(request, BulkEnvVarForm.new);
              final stacks = ctx.service<StacksService>();
              return (id, form, stacks);
            } on TypeError catch (e) {
              throw BadRequestException('Invalid request payload ($e)');
            } on FormatException catch (e) {
              throw BadRequestException('Invalid request format: ${e.message}');
            }
          })();
          final result = await this.bulkEnvs(id, form, stacks, ctx);
          return jsonResponse(body: result, statusCode: 201);
        },
      );
      router.post(basePath, __route);
      spec.putOperation(
          openApiPath,
          'post',
          Operation(
            summary: 'Bulk-upsert stack env vars from a .env file',
            tags: <String>['Stacks'],
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
                r'$ref': '#/components/schemas/BulkEnvVarForm'
              }),
              'application/x-www-form-urlencoded': MediaType(
                  schema: <String, Object?>{
                    r'$ref': '#/components/schemas/BulkEnvVarForm'
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
      final basePath = '$prefix/stacks/<id>/envs/<envId>';
      final openApiPath = '$prefix/stacks/{id}/envs/{envId}';
      final RouteConfig __cfg =
          RouteConfig.empty.merge(const RouteConfig(requireAuth: true));
      final __route = gisilaRoute(
        app: app,
        config: __cfg,
        routeId: 'DELETE $basePath',
        handler: (RequestContext ctx) async {
          final request = ctx.request;
          final (id, envId, stacks) = await (() async {
            try {
              final id =
                  coerce<int>(request.params['id'], 'id', required: true);
              final envId =
                  coerce<int>(request.params['envId'], 'envId', required: true);
              final stacks = ctx.service<StacksService>();
              return (id, envId, stacks);
            } on TypeError catch (e) {
              throw BadRequestException('Invalid request payload ($e)');
            } on FormatException catch (e) {
              throw BadRequestException('Invalid request format: ${e.message}');
            }
          })();
          final result = await this.deleteEnv(id, envId, stacks, ctx);
          return jsonResponse(body: result, statusCode: 204);
        },
      );
      router.delete(basePath, __route);
      spec.putOperation(
          openApiPath,
          'delete',
          Operation(
            summary: 'Delete a stack env var',
            tags: <String>['Stacks'],
            parameters: <Parameter>[
              Parameter(
                name: 'id',
                location: 'path',
                required: true,
                description: null,
                schema: <String, Object?>{'type': 'integer', 'format': 'int64'},
              ),
              Parameter(
                name: 'envId',
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
