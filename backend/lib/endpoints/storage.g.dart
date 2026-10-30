// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'storage.dart';

// **************************************************************************
// ControllerGenerator
// **************************************************************************

// **************************************************
// gisila_doc: generated for StorageApi
// **************************************************

extension StorageApiGisilaDoc on StorageApi {
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
    spec.putSchema('InstallGarageForm', <String, Object?>{
      'type': 'object',
      'properties': <String, Object?>{
        'displayName': <String, Object?>{'type': 'string'},
        'port': <String, Object?>{'type': 'integer', 'format': 'int64'},
        'publicUrl': <String, Object?>{'type': 'string'}
      }
    });
    spec.putSchema('AddConnectorForm', <String, Object?>{
      'type': 'object',
      'properties': <String, Object?>{
        'displayName': <String, Object?>{'type': 'string'},
        'endpoint': <String, Object?>{'type': 'string'},
        'region': <String, Object?>{'type': 'string'},
        'accessKey': <String, Object?>{'type': 'string'},
        'secretKey': <String, Object?>{'type': 'string'},
        'publicUrl': <String, Object?>{'type': 'string'},
        'forcePathStyle': <String, Object?>{'type': 'boolean'}
      }
    });
    spec.putSchema('ExposeProviderForm', <String, Object?>{
      'type': 'object',
      'properties': <String, Object?>{
        'publicUrl': <String, Object?>{'type': 'string'},
        'consoleUrl': <String, Object?>{'type': 'string'},
        'issueCert': <String, Object?>{'type': 'boolean'}
      }
    });
    spec.putSchema('CreateBucketForm', <String, Object?>{
      'type': 'object',
      'properties': <String, Object?>{
        'bucketName': <String, Object?>{'type': 'string'},
        'isPublic': <String, Object?>{'type': 'boolean'}
      }
    });
    spec.putSchema('LinkBucketForm', <String, Object?>{
      'type': 'object',
      'properties': <String, Object?>{
        'bucketId': <String, Object?>{'type': 'integer', 'format': 'int64'},
        'envPrefix': <String, Object?>{'type': 'string'}
      }
    });
    spec.putTag('Storage');
    {
      final basePath = '$prefix/storage/providers';
      final openApiPath = '$prefix/storage/providers';
      final RouteConfig __cfg =
          RouteConfig.empty.merge(const RouteConfig(requireAuth: true));
      final __route = gisilaRoute(
        app: app,
        config: __cfg,
        routeId: 'GET $basePath',
        handler: (RequestContext ctx) async {
          final (svc,) = await (() async {
            try {
              final svc = ctx.service<StorageService>();
              return (svc,);
            } on TypeError catch (e) {
              throw BadRequestException('Invalid request payload ($e)');
            } on FormatException catch (e) {
              throw BadRequestException('Invalid request format: ${e.message}');
            }
          })();
          final result = await this.listProviders(svc, ctx);
          return jsonResponse(body: result, statusCode: 200);
        },
      );
      router.get(basePath, __route);
      spec.putOperation(
          openApiPath,
          'get',
          Operation(
            summary: 'List storage providers',
            tags: <String>['Storage'],
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
      final basePath = '$prefix/storage/providers/garage';
      final openApiPath = '$prefix/storage/providers/garage';
      final RouteConfig __cfg =
          RouteConfig.empty.merge(const RouteConfig(requireAuth: true));
      final __route = gisilaRoute(
        app: app,
        config: __cfg,
        routeId: 'POST $basePath',
        handler: (RequestContext ctx) async {
          final request = ctx.request;
          final (form, svc) = await (() async {
            try {
              final form = await bindForm(request, InstallGarageForm.new);
              final svc = ctx.service<StorageService>();
              return (form, svc);
            } on TypeError catch (e) {
              throw BadRequestException('Invalid request payload ($e)');
            } on FormatException catch (e) {
              throw BadRequestException('Invalid request format: ${e.message}');
            }
          })();
          final result = await this.installGarage(form, svc, ctx);
          return jsonResponse(body: result, statusCode: 201);
        },
      );
      router.post(basePath, __route);
      spec.putOperation(
          openApiPath,
          'post',
          Operation(
            summary: 'Install the self-hosted Garage server',
            tags: <String>['Storage'],
            parameters: <Parameter>[],
            requestBody: RequestBody(required: true, content: {
              'application/json': MediaType(schema: <String, Object?>{
                r'$ref': '#/components/schemas/InstallGarageForm'
              }),
              'application/x-www-form-urlencoded': MediaType(
                  schema: <String, Object?>{
                    r'$ref': '#/components/schemas/InstallGarageForm'
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
      final basePath = '$prefix/storage/providers/external';
      final openApiPath = '$prefix/storage/providers/external';
      final RouteConfig __cfg =
          RouteConfig.empty.merge(const RouteConfig(requireAuth: true));
      final __route = gisilaRoute(
        app: app,
        config: __cfg,
        routeId: 'POST $basePath',
        handler: (RequestContext ctx) async {
          final request = ctx.request;
          final (form, svc) = await (() async {
            try {
              final form = await bindForm(request, AddConnectorForm.new);
              final svc = ctx.service<StorageService>();
              return (form, svc);
            } on TypeError catch (e) {
              throw BadRequestException('Invalid request payload ($e)');
            } on FormatException catch (e) {
              throw BadRequestException('Invalid request format: ${e.message}');
            }
          })();
          final result = await this.addConnector(form, svc, ctx);
          return jsonResponse(body: result, statusCode: 201);
        },
      );
      router.post(basePath, __route);
      spec.putOperation(
          openApiPath,
          'post',
          Operation(
            summary: 'Register an external S3 endpoint',
            tags: <String>['Storage'],
            parameters: <Parameter>[],
            requestBody: RequestBody(required: true, content: {
              'application/json': MediaType(schema: <String, Object?>{
                r'$ref': '#/components/schemas/AddConnectorForm'
              }),
              'application/x-www-form-urlencoded': MediaType(
                  schema: <String, Object?>{
                    r'$ref': '#/components/schemas/AddConnectorForm'
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
      final basePath = '$prefix/storage/providers/<id>';
      final openApiPath = '$prefix/storage/providers/{id}';
      final RouteConfig __cfg =
          RouteConfig.empty.merge(const RouteConfig(requireAuth: true));
      final __route = gisilaRoute(
        app: app,
        config: __cfg,
        routeId: 'GET $basePath',
        handler: (RequestContext ctx) async {
          final request = ctx.request;
          final (id, svc) = await (() async {
            try {
              final id =
                  coerce<int>(request.params['id'], 'id', required: true);
              final svc = ctx.service<StorageService>();
              return (id, svc);
            } on TypeError catch (e) {
              throw BadRequestException('Invalid request payload ($e)');
            } on FormatException catch (e) {
              throw BadRequestException('Invalid request format: ${e.message}');
            }
          })();
          final result = await this.getProvider(id, svc, ctx);
          return jsonResponse(body: result, statusCode: 200);
        },
      );
      router.get(basePath, __route);
      spec.putOperation(
          openApiPath,
          'get',
          Operation(
            summary: 'Get a storage provider',
            tags: <String>['Storage'],
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
      final basePath = '$prefix/storage/providers/<id>/start';
      final openApiPath = '$prefix/storage/providers/{id}/start';
      final RouteConfig __cfg =
          RouteConfig.empty.merge(const RouteConfig(requireAuth: true));
      final __route = gisilaRoute(
        app: app,
        config: __cfg,
        routeId: 'POST $basePath',
        handler: (RequestContext ctx) async {
          final request = ctx.request;
          final (id, svc) = await (() async {
            try {
              final id =
                  coerce<int>(request.params['id'], 'id', required: true);
              final svc = ctx.service<StorageService>();
              return (id, svc);
            } on TypeError catch (e) {
              throw BadRequestException('Invalid request payload ($e)');
            } on FormatException catch (e) {
              throw BadRequestException('Invalid request format: ${e.message}');
            }
          })();
          final result = await this.startProvider(id, svc, ctx);
          return jsonResponse(body: result, statusCode: 201);
        },
      );
      router.post(basePath, __route);
      spec.putOperation(
          openApiPath,
          'post',
          Operation(
            summary: 'Start the storage server',
            tags: <String>['Storage'],
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
      final basePath = '$prefix/storage/providers/<id>/stop';
      final openApiPath = '$prefix/storage/providers/{id}/stop';
      final RouteConfig __cfg =
          RouteConfig.empty.merge(const RouteConfig(requireAuth: true));
      final __route = gisilaRoute(
        app: app,
        config: __cfg,
        routeId: 'POST $basePath',
        handler: (RequestContext ctx) async {
          final request = ctx.request;
          final (id, svc) = await (() async {
            try {
              final id =
                  coerce<int>(request.params['id'], 'id', required: true);
              final svc = ctx.service<StorageService>();
              return (id, svc);
            } on TypeError catch (e) {
              throw BadRequestException('Invalid request payload ($e)');
            } on FormatException catch (e) {
              throw BadRequestException('Invalid request format: ${e.message}');
            }
          })();
          final result = await this.stopProvider(id, svc, ctx);
          return jsonResponse(body: result, statusCode: 201);
        },
      );
      router.post(basePath, __route);
      spec.putOperation(
          openApiPath,
          'post',
          Operation(
            summary: 'Stop the storage server',
            tags: <String>['Storage'],
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
      final basePath = '$prefix/storage/providers/<id>/expose';
      final openApiPath = '$prefix/storage/providers/{id}/expose';
      final RouteConfig __cfg =
          RouteConfig.empty.merge(const RouteConfig(requireAuth: true));
      final __route = gisilaRoute(
        app: app,
        config: __cfg,
        routeId: 'POST $basePath',
        handler: (RequestContext ctx) async {
          final request = ctx.request;
          final (id, form, svc) = await (() async {
            try {
              final id =
                  coerce<int>(request.params['id'], 'id', required: true);
              final form = await bindForm(request, ExposeProviderForm.new);
              final svc = ctx.service<StorageService>();
              return (id, form, svc);
            } on TypeError catch (e) {
              throw BadRequestException('Invalid request payload ($e)');
            } on FormatException catch (e) {
              throw BadRequestException('Invalid request format: ${e.message}');
            }
          })();
          final result = await this.exposeProvider(id, form, svc, ctx);
          return jsonResponse(body: result, statusCode: 201);
        },
      );
      router.post(basePath, __route);
      spec.putOperation(
          openApiPath,
          'post',
          Operation(
            summary: 'Set the public URL (+ nginx vhost)',
            tags: <String>['Storage'],
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
                r'$ref': '#/components/schemas/ExposeProviderForm'
              }),
              'application/x-www-form-urlencoded': MediaType(
                  schema: <String, Object?>{
                    r'$ref': '#/components/schemas/ExposeProviderForm'
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
      final basePath = '$prefix/storage/providers/<id>';
      final openApiPath = '$prefix/storage/providers/{id}';
      final RouteConfig __cfg =
          RouteConfig.empty.merge(const RouteConfig(requireAuth: true));
      final __route = gisilaRoute(
        app: app,
        config: __cfg,
        routeId: 'DELETE $basePath',
        handler: (RequestContext ctx) async {
          final request = ctx.request;
          final (id, svc) = await (() async {
            try {
              final id =
                  coerce<int>(request.params['id'], 'id', required: true);
              final svc = ctx.service<StorageService>();
              return (id, svc);
            } on TypeError catch (e) {
              throw BadRequestException('Invalid request payload ($e)');
            } on FormatException catch (e) {
              throw BadRequestException('Invalid request format: ${e.message}');
            }
          })();
          final result = await this.deleteProvider(id, svc, ctx);
          return jsonResponse(body: result, statusCode: 204);
        },
      );
      router.delete(basePath, __route);
      spec.putOperation(
          openApiPath,
          'delete',
          Operation(
            summary: 'Remove a storage provider',
            tags: <String>['Storage'],
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
      final basePath = '$prefix/storage/providers/<id>/buckets';
      final openApiPath = '$prefix/storage/providers/{id}/buckets';
      final RouteConfig __cfg =
          RouteConfig.empty.merge(const RouteConfig(requireAuth: true));
      final __route = gisilaRoute(
        app: app,
        config: __cfg,
        routeId: 'GET $basePath',
        handler: (RequestContext ctx) async {
          final request = ctx.request;
          final (id, svc) = await (() async {
            try {
              final id =
                  coerce<int>(request.params['id'], 'id', required: true);
              final svc = ctx.service<StorageService>();
              return (id, svc);
            } on TypeError catch (e) {
              throw BadRequestException('Invalid request payload ($e)');
            } on FormatException catch (e) {
              throw BadRequestException('Invalid request format: ${e.message}');
            }
          })();
          final result = await this.listBuckets(id, svc, ctx);
          return jsonResponse(body: result, statusCode: 200);
        },
      );
      router.get(basePath, __route);
      spec.putOperation(
          openApiPath,
          'get',
          Operation(
            summary: 'List buckets in a provider',
            tags: <String>['Storage'],
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
      final basePath = '$prefix/storage/providers/<id>/buckets';
      final openApiPath = '$prefix/storage/providers/{id}/buckets';
      final RouteConfig __cfg =
          RouteConfig.empty.merge(const RouteConfig(requireAuth: true));
      final __route = gisilaRoute(
        app: app,
        config: __cfg,
        routeId: 'POST $basePath',
        handler: (RequestContext ctx) async {
          final request = ctx.request;
          final (id, form, svc) = await (() async {
            try {
              final id =
                  coerce<int>(request.params['id'], 'id', required: true);
              final form = await bindForm(request, CreateBucketForm.new);
              final svc = ctx.service<StorageService>();
              return (id, form, svc);
            } on TypeError catch (e) {
              throw BadRequestException('Invalid request payload ($e)');
            } on FormatException catch (e) {
              throw BadRequestException('Invalid request format: ${e.message}');
            }
          })();
          final result = await this.createBucket(id, form, svc, ctx);
          return jsonResponse(body: result, statusCode: 201);
        },
      );
      router.post(basePath, __route);
      spec.putOperation(
          openApiPath,
          'post',
          Operation(
            summary: 'Create a bucket + scoped key',
            tags: <String>['Storage'],
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
                r'$ref': '#/components/schemas/CreateBucketForm'
              }),
              'application/x-www-form-urlencoded': MediaType(
                  schema: <String, Object?>{
                    r'$ref': '#/components/schemas/CreateBucketForm'
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
      final basePath = '$prefix/storage/providers/<id>/buckets/<bid>';
      final openApiPath = '$prefix/storage/providers/{id}/buckets/{bid}';
      final RouteConfig __cfg =
          RouteConfig.empty.merge(const RouteConfig(requireAuth: true));
      final __route = gisilaRoute(
        app: app,
        config: __cfg,
        routeId: 'GET $basePath',
        handler: (RequestContext ctx) async {
          final request = ctx.request;
          final (id, bid, svc) = await (() async {
            try {
              final id =
                  coerce<int>(request.params['id'], 'id', required: true);
              final bid =
                  coerce<int>(request.params['bid'], 'bid', required: true);
              final svc = ctx.service<StorageService>();
              return (id, bid, svc);
            } on TypeError catch (e) {
              throw BadRequestException('Invalid request payload ($e)');
            } on FormatException catch (e) {
              throw BadRequestException('Invalid request format: ${e.message}');
            }
          })();
          final result = await this.getBucket(id, bid, svc, ctx);
          return jsonResponse(body: result, statusCode: 200);
        },
      );
      router.get(basePath, __route);
      spec.putOperation(
          openApiPath,
          'get',
          Operation(
            summary: 'Get a bucket (with creds)',
            tags: <String>['Storage'],
            parameters: <Parameter>[
              Parameter(
                name: 'id',
                location: 'path',
                required: true,
                description: null,
                schema: <String, Object?>{'type': 'integer', 'format': 'int64'},
              ),
              Parameter(
                name: 'bid',
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
      final basePath = '$prefix/storage/providers/<id>/buckets/<bid>';
      final openApiPath = '$prefix/storage/providers/{id}/buckets/{bid}';
      final RouteConfig __cfg =
          RouteConfig.empty.merge(const RouteConfig(requireAuth: true));
      final __route = gisilaRoute(
        app: app,
        config: __cfg,
        routeId: 'DELETE $basePath',
        handler: (RequestContext ctx) async {
          final request = ctx.request;
          final (id, bid, svc) = await (() async {
            try {
              final id =
                  coerce<int>(request.params['id'], 'id', required: true);
              final bid =
                  coerce<int>(request.params['bid'], 'bid', required: true);
              final svc = ctx.service<StorageService>();
              return (id, bid, svc);
            } on TypeError catch (e) {
              throw BadRequestException('Invalid request payload ($e)');
            } on FormatException catch (e) {
              throw BadRequestException('Invalid request format: ${e.message}');
            }
          })();
          final result = await this.deleteBucket(id, bid, svc, ctx);
          return jsonResponse(body: result, statusCode: 204);
        },
      );
      router.delete(basePath, __route);
      spec.putOperation(
          openApiPath,
          'delete',
          Operation(
            summary: 'Delete a bucket',
            tags: <String>['Storage'],
            parameters: <Parameter>[
              Parameter(
                name: 'id',
                location: 'path',
                required: true,
                description: null,
                schema: <String, Object?>{'type': 'integer', 'format': 'int64'},
              ),
              Parameter(
                name: 'bid',
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
      final basePath = '$prefix/storage/apps/<appId>/links';
      final openApiPath = '$prefix/storage/apps/{appId}/links';
      final RouteConfig __cfg =
          RouteConfig.empty.merge(const RouteConfig(requireAuth: true));
      final __route = gisilaRoute(
        app: app,
        config: __cfg,
        routeId: 'GET $basePath',
        handler: (RequestContext ctx) async {
          final request = ctx.request;
          final (appId, svc) = await (() async {
            try {
              final appId =
                  coerce<int>(request.params['appId'], 'appId', required: true);
              final svc = ctx.service<StorageService>();
              return (appId, svc);
            } on TypeError catch (e) {
              throw BadRequestException('Invalid request payload ($e)');
            } on FormatException catch (e) {
              throw BadRequestException('Invalid request format: ${e.message}');
            }
          })();
          final result = await this.listAppLinks(appId, svc, ctx);
          return jsonResponse(body: result, statusCode: 200);
        },
      );
      router.get(basePath, __route);
      spec.putOperation(
          openApiPath,
          'get',
          Operation(
            summary: 'List an app\'s linked buckets',
            tags: <String>['Storage'],
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
      final basePath = '$prefix/storage/apps/<appId>/links';
      final openApiPath = '$prefix/storage/apps/{appId}/links';
      final RouteConfig __cfg =
          RouteConfig.empty.merge(const RouteConfig(requireAuth: true));
      final __route = gisilaRoute(
        app: app,
        config: __cfg,
        routeId: 'POST $basePath',
        handler: (RequestContext ctx) async {
          final request = ctx.request;
          final (appId, form, svc) = await (() async {
            try {
              final appId =
                  coerce<int>(request.params['appId'], 'appId', required: true);
              final form = await bindForm(request, LinkBucketForm.new);
              final svc = ctx.service<StorageService>();
              return (appId, form, svc);
            } on TypeError catch (e) {
              throw BadRequestException('Invalid request payload ($e)');
            } on FormatException catch (e) {
              throw BadRequestException('Invalid request format: ${e.message}');
            }
          })();
          final result = await this.linkBucket(appId, form, svc, ctx);
          return jsonResponse(body: result, statusCode: 201);
        },
      );
      router.post(basePath, __route);
      spec.putOperation(
          openApiPath,
          'post',
          Operation(
            summary: 'Link a bucket to an app',
            tags: <String>['Storage'],
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
                r'$ref': '#/components/schemas/LinkBucketForm'
              }),
              'application/x-www-form-urlencoded': MediaType(
                  schema: <String, Object?>{
                    r'$ref': '#/components/schemas/LinkBucketForm'
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
      final basePath = '$prefix/storage/apps/<appId>/links/<linkId>';
      final openApiPath = '$prefix/storage/apps/{appId}/links/{linkId}';
      final RouteConfig __cfg =
          RouteConfig.empty.merge(const RouteConfig(requireAuth: true));
      final __route = gisilaRoute(
        app: app,
        config: __cfg,
        routeId: 'DELETE $basePath',
        handler: (RequestContext ctx) async {
          final request = ctx.request;
          final (appId, linkId, svc) = await (() async {
            try {
              final appId =
                  coerce<int>(request.params['appId'], 'appId', required: true);
              final linkId = coerce<int>(request.params['linkId'], 'linkId',
                  required: true);
              final svc = ctx.service<StorageService>();
              return (appId, linkId, svc);
            } on TypeError catch (e) {
              throw BadRequestException('Invalid request payload ($e)');
            } on FormatException catch (e) {
              throw BadRequestException('Invalid request format: ${e.message}');
            }
          })();
          final result = await this.unlinkBucket(appId, linkId, svc, ctx);
          return jsonResponse(body: result, statusCode: 204);
        },
      );
      router.delete(basePath, __route);
      spec.putOperation(
          openApiPath,
          'delete',
          Operation(
            summary: 'Unlink a bucket from an app',
            tags: <String>['Storage'],
            parameters: <Parameter>[
              Parameter(
                name: 'appId',
                location: 'path',
                required: true,
                description: null,
                schema: <String, Object?>{'type': 'integer', 'format': 'int64'},
              ),
              Parameter(
                name: 'linkId',
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
