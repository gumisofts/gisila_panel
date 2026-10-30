// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'apps.dart';

// **************************************************************************
// ControllerGenerator
// **************************************************************************

// **************************************************
// gisila_doc: generated for AppsApi
// **************************************************

extension AppsApiGisilaDoc on AppsApi {
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
    spec.putSchema('CreateAppForm', <String, Object?>{
      'type': 'object',
      'properties': <String, Object?>{
        'projectId': <String, Object?>{'type': 'integer', 'format': 'int64'},
        'name': <String, Object?>{'type': 'string'},
        'applicationId': <String, Object?>{
          'type': 'integer',
          'format': 'int64'
        },
        'runtime': <String, Object?>{'type': 'string'},
        'deploymentMode': <String, Object?>{'type': 'string'},
        'sourceType': <String, Object?>{'type': 'string'},
        'gitUrl': <String, Object?>{'type': 'string'},
        'gitBranch': <String, Object?>{'type': 'string'},
        'sourceSubdir': <String, Object?>{'type': 'string'},
        'buildCommand': <String, Object?>{'type': 'string'},
        'startCommand': <String, Object?>{'type': 'string'},
        'healthCheckPath': <String, Object?>{'type': 'string'},
        'memoryMbLimit': <String, Object?>{
          'type': 'integer',
          'format': 'int64'
        },
        'cpuQuotaPercent': <String, Object?>{
          'type': 'integer',
          'format': 'int64'
        },
        'tasksLimit': <String, Object?>{'type': 'integer', 'format': 'int64'},
        'pythonVersion': <String, Object?>{'type': 'string'},
        'pythonMode': <String, Object?>{'type': 'string'},
        'wsgiApp': <String, Object?>{'type': 'string'},
        'gunicornWorkers': <String, Object?>{
          'type': 'integer',
          'format': 'int64'
        },
        'gunicornThreads': <String, Object?>{
          'type': 'integer',
          'format': 'int64'
        },
        'gunicornTimeout': <String, Object?>{
          'type': 'integer',
          'format': 'int64'
        },
        'gunicornBind': <String, Object?>{'type': 'string'},
        'gunicornExtraArgs': <String, Object?>{'type': 'string'},
        'nodeVersion': <String, Object?>{'type': 'string'},
        'dartVersion': <String, Object?>{'type': 'string'},
        'goVersion': <String, Object?>{'type': 'string'},
        'rustVersion': <String, Object?>{'type': 'string'},
        'bunVersion': <String, Object?>{'type': 'string'},
        'celeryApp': <String, Object?>{'type': 'string'},
        'celeryWorkerCount': <String, Object?>{
          'type': 'integer',
          'format': 'int64'
        },
        'celeryConcurrency': <String, Object?>{
          'type': 'integer',
          'format': 'int64'
        },
        'celeryQueues': <String, Object?>{'type': 'string'},
        'celeryBeatEnabled': <String, Object?>{'type': 'boolean'},
        'celeryExtraArgs': <String, Object?>{'type': 'string'},
        'staticRoot': <String, Object?>{'type': 'string'},
        'staticSpa': <String, Object?>{'type': 'boolean'},
        'mediaEnabled': <String, Object?>{'type': 'boolean'},
        'mediaMaxUploadMb': <String, Object?>{
          'type': 'integer',
          'format': 'int64'
        },
        'deployKeyId': <String, Object?>{'type': 'integer', 'format': 'int64'},
        'internalPort': <String, Object?>{'type': 'integer', 'format': 'int64'},
        'exposeMode': <String, Object?>{'type': 'string'},
        'publiclyReachable': <String, Object?>{'type': 'boolean'}
      }
    });
    spec.putSchema('UpdateAppForm', <String, Object?>{
      'type': 'object',
      'properties': <String, Object?>{
        'name': <String, Object?>{'type': 'string'},
        'projectId': <String, Object?>{'type': 'integer', 'format': 'int64'},
        'gitUrl': <String, Object?>{'type': 'string'},
        'gitBranch': <String, Object?>{'type': 'string'},
        'sourceSubdir': <String, Object?>{},
        'buildCommand': <String, Object?>{'type': 'string'},
        'startCommand': <String, Object?>{'type': 'string'},
        'healthCheckPath': <String, Object?>{'type': 'string'},
        'releasesToKeep': <String, Object?>{
          'type': 'integer',
          'format': 'int64'
        },
        'memoryMbLimit': <String, Object?>{
          'type': 'integer',
          'format': 'int64'
        },
        'cpuQuotaPercent': <String, Object?>{
          'type': 'integer',
          'format': 'int64'
        },
        'tasksLimit': <String, Object?>{'type': 'integer', 'format': 'int64'},
        'pythonVersion': <String, Object?>{'type': 'string'},
        'pythonMode': <String, Object?>{'type': 'string'},
        'wsgiApp': <String, Object?>{'type': 'string'},
        'gunicornWorkers': <String, Object?>{
          'type': 'integer',
          'format': 'int64'
        },
        'gunicornThreads': <String, Object?>{
          'type': 'integer',
          'format': 'int64'
        },
        'gunicornTimeout': <String, Object?>{
          'type': 'integer',
          'format': 'int64'
        },
        'gunicornBind': <String, Object?>{'type': 'string'},
        'gunicornExtraArgs': <String, Object?>{'type': 'string'},
        'nodeVersion': <String, Object?>{'type': 'string'},
        'dartVersion': <String, Object?>{'type': 'string'},
        'goVersion': <String, Object?>{'type': 'string'},
        'rustVersion': <String, Object?>{'type': 'string'},
        'bunVersion': <String, Object?>{'type': 'string'},
        'celeryApp': <String, Object?>{'type': 'string'},
        'celeryWorkerCount': <String, Object?>{
          'type': 'integer',
          'format': 'int64'
        },
        'celeryConcurrency': <String, Object?>{
          'type': 'integer',
          'format': 'int64'
        },
        'celeryQueues': <String, Object?>{'type': 'string'},
        'celeryBeatEnabled': <String, Object?>{'type': 'boolean'},
        'celeryExtraArgs': <String, Object?>{'type': 'string'},
        'staticRoot': <String, Object?>{'type': 'string'},
        'staticSpa': <String, Object?>{'type': 'boolean'},
        'mediaEnabled': <String, Object?>{'type': 'boolean'},
        'mediaMaxUploadMb': <String, Object?>{
          'type': 'integer',
          'format': 'int64'
        },
        'deployKeyId': <String, Object?>{'type': 'integer', 'format': 'int64'},
        'internalPort': <String, Object?>{'type': 'integer', 'format': 'int64'}
      }
    });
    spec.putSchema('NetworkExposureForm', <String, Object?>{
      'type': 'object',
      'properties': <String, Object?>{
        'publiclyReachable': <String, Object?>{'type': 'boolean'}
      }
    });
    spec.putSchema('ExecCommandForm', <String, Object?>{
      'type': 'object',
      'properties': <String, Object?>{
        'command': <String, Object?>{'type': 'string'}
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
    spec.putTag('Apps');
    {
      final basePath = '$prefix/apps/';
      final openApiPath = '$prefix/apps/';
      final RouteConfig __cfg =
          RouteConfig.empty.merge(const RouteConfig(requireAuth: true));
      final __route = gisilaRoute(
        app: app,
        config: __cfg,
        routeId: 'GET $basePath',
        handler: (RequestContext ctx) async {
          final request = ctx.request;
          final (apps, projectId) = await (() async {
            try {
              final apps = ctx.service<AppsService>();
              final projectId = coerce<int?>(
                  request.url.queryParameters['projectId'], 'projectId',
                  required: false);
              return (apps, projectId);
            } on TypeError catch (e) {
              throw BadRequestException('Invalid request payload ($e)');
            } on FormatException catch (e) {
              throw BadRequestException('Invalid request format: ${e.message}');
            }
          })();
          final result = await this.list(apps, ctx, projectId);
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
            summary: 'List apps',
            tags: <String>['Apps'],
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
      final basePath = '$prefix/apps/';
      final openApiPath = '$prefix/apps/';
      final RouteConfig __cfg =
          RouteConfig.empty.merge(const RouteConfig(requireAuth: true));
      final __route = gisilaRoute(
        app: app,
        config: __cfg,
        routeId: 'POST $basePath',
        handler: (RequestContext ctx) async {
          final request = ctx.request;
          final (form, apps) = await (() async {
            try {
              final form = await bindForm(request, CreateAppForm.new);
              final apps = ctx.service<AppsService>();
              return (form, apps);
            } on TypeError catch (e) {
              throw BadRequestException('Invalid request payload ($e)');
            } on FormatException catch (e) {
              throw BadRequestException('Invalid request format: ${e.message}');
            }
          })();
          final result = await this.create(form, apps, ctx);
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
            summary: 'Create an app',
            tags: <String>['Apps'],
            parameters: <Parameter>[],
            requestBody: RequestBody(required: true, content: {
              'application/json': MediaType(schema: <String, Object?>{
                r'$ref': '#/components/schemas/CreateAppForm'
              }),
              'application/x-www-form-urlencoded': MediaType(
                  schema: <String, Object?>{
                    r'$ref': '#/components/schemas/CreateAppForm'
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
      final basePath = '$prefix/apps/metrics-summary';
      final openApiPath = '$prefix/apps/metrics-summary';
      final RouteConfig __cfg =
          RouteConfig.empty.merge(const RouteConfig(requireAuth: true));
      final __route = gisilaRoute(
        app: app,
        config: __cfg,
        routeId: 'GET $basePath',
        handler: (RequestContext ctx) async {
          final (apps,) = await (() async {
            try {
              final apps = ctx.service<AppsService>();
              return (apps,);
            } on TypeError catch (e) {
              throw BadRequestException('Invalid request payload ($e)');
            } on FormatException catch (e) {
              throw BadRequestException('Invalid request format: ${e.message}');
            }
          })();
          final result = await this.metricsSummary(apps, ctx);
          return jsonResponse(body: result, statusCode: 200);
        },
      );
      router.get(basePath, __route);
      spec.putOperation(
          openApiPath,
          'get',
          Operation(
            summary: 'Latest CPU/memory usage per running app',
            tags: <String>['Apps'],
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
    {
      final basePath = '$prefix/apps/limits';
      final openApiPath = '$prefix/apps/limits';
      final RouteConfig __cfg =
          RouteConfig.empty.merge(const RouteConfig(requireAuth: true));
      final __route = gisilaRoute(
        app: app,
        config: __cfg,
        routeId: 'GET $basePath',
        handler: (RequestContext ctx) async {
          final result = await this.limits(ctx);
          return jsonResponse(body: result, statusCode: 200);
        },
      );
      router.get(basePath, __route);
      spec.putOperation(
          openApiPath,
          'get',
          Operation(
            summary: 'Host resource limits apps can be configured up to',
            tags: <String>['Apps'],
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
    {
      final basePath = '$prefix/apps/<id>';
      final openApiPath = '$prefix/apps/{id}';
      final RouteConfig __cfg =
          RouteConfig.empty.merge(const RouteConfig(requireAuth: true));
      final __route = gisilaRoute(
        app: app,
        config: __cfg,
        routeId: 'GET $basePath',
        handler: (RequestContext ctx) async {
          final request = ctx.request;
          final (id, apps) = await (() async {
            try {
              final id =
                  coerce<int>(request.params['id'], 'id', required: true);
              final apps = ctx.service<AppsService>();
              return (id, apps);
            } on TypeError catch (e) {
              throw BadRequestException('Invalid request payload ($e)');
            } on FormatException catch (e) {
              throw BadRequestException('Invalid request format: ${e.message}');
            }
          })();
          final result = await this.retrieve(id, apps, ctx);
          return jsonResponse(body: result, statusCode: 200);
        },
      );
      router.get(basePath, __route);
      spec.putOperation(
          openApiPath,
          'get',
          Operation(
            summary: 'Get an app',
            tags: <String>['Apps'],
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
      final basePath = '$prefix/apps/<id>';
      final openApiPath = '$prefix/apps/{id}';
      final RouteConfig __cfg =
          RouteConfig.empty.merge(const RouteConfig(requireAuth: true));
      final __route = gisilaRoute(
        app: app,
        config: __cfg,
        routeId: 'PATCH $basePath',
        handler: (RequestContext ctx) async {
          final request = ctx.request;
          final (id, form, apps) = await (() async {
            try {
              final id =
                  coerce<int>(request.params['id'], 'id', required: true);
              final form = await bindForm(request, UpdateAppForm.new);
              final apps = ctx.service<AppsService>();
              return (id, form, apps);
            } on TypeError catch (e) {
              throw BadRequestException('Invalid request payload ($e)');
            } on FormatException catch (e) {
              throw BadRequestException('Invalid request format: ${e.message}');
            }
          })();
          final result = await this.update(id, form, apps, ctx);
          return jsonResponse(body: result, statusCode: 200);
        },
      );
      router.patch(basePath, __route);
      spec.putOperation(
          openApiPath,
          'patch',
          Operation(
            summary: 'Update an app',
            tags: <String>['Apps'],
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
                r'$ref': '#/components/schemas/UpdateAppForm'
              }),
              'application/x-www-form-urlencoded': MediaType(
                  schema: <String, Object?>{
                    r'$ref': '#/components/schemas/UpdateAppForm'
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
      final basePath = '$prefix/apps/<id>/network';
      final openApiPath = '$prefix/apps/{id}/network';
      final RouteConfig __cfg =
          RouteConfig.empty.merge(const RouteConfig(requireAuth: true));
      final __route = gisilaRoute(
        app: app,
        config: __cfg,
        routeId: 'POST $basePath',
        handler: (RequestContext ctx) async {
          final request = ctx.request;
          final (id, form, apps) = await (() async {
            try {
              final id =
                  coerce<int>(request.params['id'], 'id', required: true);
              final form = await bindForm(request, NetworkExposureForm.new);
              final apps = ctx.service<AppsService>();
              return (id, form, apps);
            } on TypeError catch (e) {
              throw BadRequestException('Invalid request payload ($e)');
            } on FormatException catch (e) {
              throw BadRequestException('Invalid request format: ${e.message}');
            }
          })();
          final result = await this.network(id, form, apps, ctx);
          return jsonResponse(body: result, statusCode: 201);
        },
      );
      router.post(basePath, __route);
      spec.putOperation(
          openApiPath,
          'post',
          Operation(
            summary: 'Toggle public reachability for a tcp app',
            tags: <String>['Apps'],
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
                r'$ref': '#/components/schemas/NetworkExposureForm'
              }),
              'application/x-www-form-urlencoded': MediaType(
                  schema: <String, Object?>{
                    r'$ref': '#/components/schemas/NetworkExposureForm'
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
      final basePath = '$prefix/apps/<id>';
      final openApiPath = '$prefix/apps/{id}';
      final RouteConfig __cfg =
          RouteConfig.empty.merge(const RouteConfig(requireAuth: true));
      final __route = gisilaRoute(
        app: app,
        config: __cfg,
        routeId: 'DELETE $basePath',
        handler: (RequestContext ctx) async {
          final request = ctx.request;
          final (id, lifecycle) = await (() async {
            try {
              final id =
                  coerce<int>(request.params['id'], 'id', required: true);
              final lifecycle = ctx.service<LifecycleService>();
              return (id, lifecycle);
            } on TypeError catch (e) {
              throw BadRequestException('Invalid request payload ($e)');
            } on FormatException catch (e) {
              throw BadRequestException('Invalid request format: ${e.message}');
            }
          })();
          final result = await this.delete(id, lifecycle, ctx);
          return jsonResponse(body: result, statusCode: 204);
        },
      );
      router.delete(basePath, __route);
      spec.putOperation(
          openApiPath,
          'delete',
          Operation(
            summary: 'Remove an app and all of its resources',
            tags: <String>['Apps'],
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
      final basePath = '$prefix/apps/<id>/start';
      final openApiPath = '$prefix/apps/{id}/start';
      final RouteConfig __cfg =
          RouteConfig.empty.merge(const RouteConfig(requireAuth: true));
      final __route = gisilaRoute(
        app: app,
        config: __cfg,
        routeId: 'POST $basePath',
        handler: (RequestContext ctx) async {
          final request = ctx.request;
          final (id, lifecycle) = await (() async {
            try {
              final id =
                  coerce<int>(request.params['id'], 'id', required: true);
              final lifecycle = ctx.service<LifecycleService>();
              return (id, lifecycle);
            } on TypeError catch (e) {
              throw BadRequestException('Invalid request payload ($e)');
            } on FormatException catch (e) {
              throw BadRequestException('Invalid request format: ${e.message}');
            }
          })();
          final result = await this.start(id, lifecycle, ctx);
          return jsonResponse(body: result, statusCode: 201);
        },
      );
      router.post(basePath, __route);
      spec.putOperation(
          openApiPath,
          'post',
          Operation(
            summary: 'Start an app',
            tags: <String>['Apps'],
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
      final basePath = '$prefix/apps/<id>/stop';
      final openApiPath = '$prefix/apps/{id}/stop';
      final RouteConfig __cfg =
          RouteConfig.empty.merge(const RouteConfig(requireAuth: true));
      final __route = gisilaRoute(
        app: app,
        config: __cfg,
        routeId: 'POST $basePath',
        handler: (RequestContext ctx) async {
          final request = ctx.request;
          final (id, lifecycle) = await (() async {
            try {
              final id =
                  coerce<int>(request.params['id'], 'id', required: true);
              final lifecycle = ctx.service<LifecycleService>();
              return (id, lifecycle);
            } on TypeError catch (e) {
              throw BadRequestException('Invalid request payload ($e)');
            } on FormatException catch (e) {
              throw BadRequestException('Invalid request format: ${e.message}');
            }
          })();
          final result = await this.stop(id, lifecycle, ctx);
          return jsonResponse(body: result, statusCode: 201);
        },
      );
      router.post(basePath, __route);
      spec.putOperation(
          openApiPath,
          'post',
          Operation(
            summary: 'Stop an app',
            tags: <String>['Apps'],
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
      final basePath = '$prefix/apps/<id>/restart';
      final openApiPath = '$prefix/apps/{id}/restart';
      final RouteConfig __cfg =
          RouteConfig.empty.merge(const RouteConfig(requireAuth: true));
      final __route = gisilaRoute(
        app: app,
        config: __cfg,
        routeId: 'POST $basePath',
        handler: (RequestContext ctx) async {
          final request = ctx.request;
          final (id, lifecycle) = await (() async {
            try {
              final id =
                  coerce<int>(request.params['id'], 'id', required: true);
              final lifecycle = ctx.service<LifecycleService>();
              return (id, lifecycle);
            } on TypeError catch (e) {
              throw BadRequestException('Invalid request payload ($e)');
            } on FormatException catch (e) {
              throw BadRequestException('Invalid request format: ${e.message}');
            }
          })();
          final result = await this.restart(id, lifecycle, ctx);
          return jsonResponse(body: result, statusCode: 201);
        },
      );
      router.post(basePath, __route);
      spec.putOperation(
          openApiPath,
          'post',
          Operation(
            summary: 'Restart an app',
            tags: <String>['Apps'],
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
      final basePath = '$prefix/apps/<id>/exec';
      final openApiPath = '$prefix/apps/{id}/exec';
      final RouteConfig __cfg =
          RouteConfig.empty.merge(const RouteConfig(requireAuth: true));
      final __route = gisilaRoute(
        app: app,
        config: __cfg,
        routeId: 'POST $basePath',
        handler: (RequestContext ctx) async {
          final request = ctx.request;
          final (id, form, apps) = await (() async {
            try {
              final id =
                  coerce<int>(request.params['id'], 'id', required: true);
              final form = await bindForm(request, ExecCommandForm.new);
              final apps = ctx.service<AppsService>();
              return (id, form, apps);
            } on TypeError catch (e) {
              throw BadRequestException('Invalid request payload ($e)');
            } on FormatException catch (e) {
              throw BadRequestException('Invalid request format: ${e.message}');
            }
          })();
          final result = await this.exec(id, form, apps, ctx);
          return jsonResponse(body: result, statusCode: 201);
        },
      );
      router.post(basePath, __route);
      spec.putOperation(
          openApiPath,
          'post',
          Operation(
            summary: 'Run a one-off command in the app environment',
            tags: <String>['Apps'],
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
                r'$ref': '#/components/schemas/ExecCommandForm'
              }),
              'application/x-www-form-urlencoded': MediaType(
                  schema: <String, Object?>{
                    r'$ref': '#/components/schemas/ExecCommandForm'
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
      final basePath = '$prefix/apps/<id>/envs';
      final openApiPath = '$prefix/apps/{id}/envs';
      final RouteConfig __cfg =
          RouteConfig.empty.merge(const RouteConfig(requireAuth: true));
      final __route = gisilaRoute(
        app: app,
        config: __cfg,
        routeId: 'GET $basePath',
        handler: (RequestContext ctx) async {
          final request = ctx.request;
          final (id, envs) = await (() async {
            try {
              final id =
                  coerce<int>(request.params['id'], 'id', required: true);
              final envs = ctx.service<EnvsService>();
              return (id, envs);
            } on TypeError catch (e) {
              throw BadRequestException('Invalid request payload ($e)');
            } on FormatException catch (e) {
              throw BadRequestException('Invalid request format: ${e.message}');
            }
          })();
          final result = await this.listEnvs(id, envs, ctx);
          return jsonResponse(body: result, statusCode: 200);
        },
      );
      router.get(basePath, __route);
      spec.putOperation(
          openApiPath,
          'get',
          Operation(
            summary: 'List env vars',
            tags: <String>['Apps'],
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
      final basePath = '$prefix/apps/<id>/envs';
      final openApiPath = '$prefix/apps/{id}/envs';
      final RouteConfig __cfg =
          RouteConfig.empty.merge(const RouteConfig(requireAuth: true));
      final __route = gisilaRoute(
        app: app,
        config: __cfg,
        routeId: 'POST $basePath',
        handler: (RequestContext ctx) async {
          final request = ctx.request;
          final (id, form, envs) = await (() async {
            try {
              final id =
                  coerce<int>(request.params['id'], 'id', required: true);
              final form = await bindForm(request, EnvVarForm.new);
              final envs = ctx.service<EnvsService>();
              return (id, form, envs);
            } on TypeError catch (e) {
              throw BadRequestException('Invalid request payload ($e)');
            } on FormatException catch (e) {
              throw BadRequestException('Invalid request format: ${e.message}');
            }
          })();
          final result = await this.setEnv(id, form, envs, ctx);
          return jsonResponse(body: result, statusCode: 201);
        },
      );
      router.post(basePath, __route);
      spec.putOperation(
          openApiPath,
          'post',
          Operation(
            summary: 'Set an env var',
            tags: <String>['Apps'],
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
      final basePath = '$prefix/apps/<id>/envs/bulk';
      final openApiPath = '$prefix/apps/{id}/envs/bulk';
      final RouteConfig __cfg =
          RouteConfig.empty.merge(const RouteConfig(requireAuth: true));
      final __route = gisilaRoute(
        app: app,
        config: __cfg,
        routeId: 'POST $basePath',
        handler: (RequestContext ctx) async {
          final request = ctx.request;
          final (id, form, envs) = await (() async {
            try {
              final id =
                  coerce<int>(request.params['id'], 'id', required: true);
              final form = await bindForm(request, BulkEnvVarForm.new);
              final envs = ctx.service<EnvsService>();
              return (id, form, envs);
            } on TypeError catch (e) {
              throw BadRequestException('Invalid request payload ($e)');
            } on FormatException catch (e) {
              throw BadRequestException('Invalid request format: ${e.message}');
            }
          })();
          final result = await this.bulkEnvs(id, form, envs, ctx);
          return jsonResponse(body: result, statusCode: 201);
        },
      );
      router.post(basePath, __route);
      spec.putOperation(
          openApiPath,
          'post',
          Operation(
            summary: 'Bulk-upsert env vars from a .env file',
            tags: <String>['Apps'],
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
      final basePath = '$prefix/apps/<id>/envs/<envId>';
      final openApiPath = '$prefix/apps/{id}/envs/{envId}';
      final RouteConfig __cfg =
          RouteConfig.empty.merge(const RouteConfig(requireAuth: true));
      final __route = gisilaRoute(
        app: app,
        config: __cfg,
        routeId: 'DELETE $basePath',
        handler: (RequestContext ctx) async {
          final request = ctx.request;
          final (id, envId, envs) = await (() async {
            try {
              final id =
                  coerce<int>(request.params['id'], 'id', required: true);
              final envId =
                  coerce<int>(request.params['envId'], 'envId', required: true);
              final envs = ctx.service<EnvsService>();
              return (id, envId, envs);
            } on TypeError catch (e) {
              throw BadRequestException('Invalid request payload ($e)');
            } on FormatException catch (e) {
              throw BadRequestException('Invalid request format: ${e.message}');
            }
          })();
          final result = await this.deleteEnv(id, envId, envs, ctx);
          return jsonResponse(body: result, statusCode: 204);
        },
      );
      router.delete(basePath, __route);
      spec.putOperation(
          openApiPath,
          'delete',
          Operation(
            summary: 'Delete an env var',
            tags: <String>['Apps'],
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
