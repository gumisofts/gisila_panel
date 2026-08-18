// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'notifications.dart';

// **************************************************************************
// ControllerGenerator
// **************************************************************************

// **************************************************
// gisila_doc: generated for NotificationsApi
// **************************************************

extension NotificationsApiGisilaDoc on NotificationsApi {
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
    spec.putSchema('UpdateSmtpConfigForm', <String, Object?>{
      'type': 'object',
      'properties': <String, Object?>{
        'smtpHost': <String, Object?>{'type': 'string'},
        'smtpPort': <String, Object?>{'type': 'integer', 'format': 'int64'},
        'smtpUsername': <String, Object?>{'type': 'string'},
        'smtpPassword': <String, Object?>{'type': 'string'},
        'smtpSecurity': <String, Object?>{'type': 'string'},
        'fromEmail': <String, Object?>{'type': 'string'},
        'fromName': <String, Object?>{'type': 'string'},
        'emailEnabled': <String, Object?>{'type': 'boolean'}
      }
    });
    spec.putSchema('SendTestEmailForm', <String, Object?>{
      'type': 'object',
      'properties': <String, Object?>{
        'toEmail': <String, Object?>{'type': 'string', 'format': 'email'}
      }
    });
    spec.putSchema('CreateAlertRuleForm', <String, Object?>{
      'type': 'object',
      'properties': <String, Object?>{
        'scope': <String, Object?>{'type': 'string'},
        'appId': <String, Object?>{'type': 'integer', 'format': 'int64'},
        'postgresInstanceId': <String, Object?>{
          'type': 'integer',
          'format': 'int64'
        },
        'mongoInstanceId': <String, Object?>{
          'type': 'integer',
          'format': 'int64'
        },
        'metric': <String, Object?>{'type': 'string'},
        'comparison': <String, Object?>{'type': 'string'},
        'thresholdPercent': <String, Object?>{
          'type': 'integer',
          'format': 'int64'
        },
        'severity': <String, Object?>{'type': 'string'},
        'cooldownMinutes': <String, Object?>{
          'type': 'integer',
          'format': 'int64'
        },
        'enabled': <String, Object?>{'type': 'boolean'},
        'notifyEmail': <String, Object?>{'type': 'boolean'}
      }
    });
    spec.putSchema('UpdateAlertRuleForm', <String, Object?>{
      'type': 'object',
      'properties': <String, Object?>{
        'metric': <String, Object?>{'type': 'string'},
        'comparison': <String, Object?>{'type': 'string'},
        'thresholdPercent': <String, Object?>{
          'type': 'integer',
          'format': 'int64'
        },
        'severity': <String, Object?>{'type': 'string'},
        'cooldownMinutes': <String, Object?>{
          'type': 'integer',
          'format': 'int64'
        },
        'enabled': <String, Object?>{'type': 'boolean'},
        'notifyEmail': <String, Object?>{'type': 'boolean'}
      }
    });
    spec.putTag('Notifications');
    {
      final basePath = '$prefix/notifications/settings/smtp';
      final openApiPath = '$prefix/notifications/settings/smtp';
      final RouteConfig __cfg =
          RouteConfig.empty.merge(const RouteConfig(requireAuth: true));
      router.get(
          basePath,
          gisilaRoute(
            app: app,
            config: __cfg,
            handler: (RequestContext ctx) async {
              try {
                final notifications = ctx.service<NotificationService>();
                final result = await this.getSmtpConfig(notifications, ctx);
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
            summary: 'Get the panel-wide SMTP config',
            tags: <String>['Notifications'],
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
      final basePath = '$prefix/notifications/settings/smtp';
      final openApiPath = '$prefix/notifications/settings/smtp';
      final RouteConfig __cfg =
          RouteConfig.empty.merge(const RouteConfig(requireAuth: true));
      router.put(
          basePath,
          gisilaRoute(
            app: app,
            config: __cfg,
            handler: (RequestContext ctx) async {
              try {
                final request = ctx.request;
                final form = await bindForm(request, UpdateSmtpConfigForm.new);
                final notifications = ctx.service<NotificationService>();
                final result =
                    await this.updateSmtpConfig(form, notifications, ctx);
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
          'put',
          Operation(
            summary: 'Update the panel-wide SMTP config',
            tags: <String>['Notifications'],
            parameters: <Parameter>[],
            requestBody: RequestBody(required: true, content: {
              'application/json': MediaType(schema: <String, Object?>{
                r'$ref': '#/components/schemas/UpdateSmtpConfigForm'
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
      final basePath = '$prefix/notifications/settings/smtp/test';
      final openApiPath = '$prefix/notifications/settings/smtp/test';
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
                final form = await bindForm(request, SendTestEmailForm.new);
                final notifications = ctx.service<NotificationService>();
                final result =
                    await this.sendTestEmail(form, notifications, ctx);
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
            summary: 'Send a one-off test email',
            tags: <String>['Notifications'],
            parameters: <Parameter>[],
            requestBody: RequestBody(required: true, content: {
              'application/json': MediaType(schema: <String, Object?>{
                r'$ref': '#/components/schemas/SendTestEmailForm'
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
      final basePath = '$prefix/notifications/host-stats';
      final openApiPath = '$prefix/notifications/host-stats';
      final RouteConfig __cfg =
          RouteConfig.empty.merge(const RouteConfig(requireAuth: true));
      router.get(
          basePath,
          gisilaRoute(
            app: app,
            config: __cfg,
            handler: (RequestContext ctx) async {
              try {
                final result = await this.hostStats(ctx);
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
            summary: 'Latest whole-host CPU / memory / disk snapshot',
            tags: <String>['Notifications'],
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
      final basePath = '$prefix/notifications/rules';
      final openApiPath = '$prefix/notifications/rules';
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
                final notifications = ctx.service<NotificationService>();
                final apps = ctx.service<AppsService>();
                final scope = coerce<String?>(
                    request.url.queryParameters['scope'], 'scope',
                    required: false);
                final appId = coerce<int?>(
                    request.url.queryParameters['appId'], 'appId',
                    required: false);
                final postgresInstanceId = coerce<int?>(
                    request.url.queryParameters['postgresInstanceId'],
                    'postgresInstanceId',
                    required: false);
                final mongoInstanceId = coerce<int?>(
                    request.url.queryParameters['mongoInstanceId'],
                    'mongoInstanceId',
                    required: false);
                final result = await this.listRules(notifications, apps, ctx,
                    scope, appId, postgresInstanceId, mongoInstanceId);
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
            summary: 'List alert rules',
            tags: <String>['Notifications'],
            parameters: <Parameter>[
              Parameter(
                name: 'scope',
                location: 'query',
                required: false,
                description: null,
                schema: <String, Object?>{
                  'type': <Object?>['string', 'null']
                },
              ),
              Parameter(
                name: 'appId',
                location: 'query',
                required: false,
                description: null,
                schema: <String, Object?>{
                  'type': <Object?>['integer', 'null'],
                  'format': 'int64'
                },
              ),
              Parameter(
                name: 'postgresInstanceId',
                location: 'query',
                required: false,
                description: null,
                schema: <String, Object?>{
                  'type': <Object?>['integer', 'null'],
                  'format': 'int64'
                },
              ),
              Parameter(
                name: 'mongoInstanceId',
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
              })
            },
          ));
    }
    {
      final basePath = '$prefix/notifications/rules/<id>';
      final openApiPath = '$prefix/notifications/rules/{id}';
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
                final notifications = ctx.service<NotificationService>();
                final apps = ctx.service<AppsService>();
                final result =
                    await this.retrieveRule(id, notifications, apps, ctx);
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
            summary: 'Get an alert rule',
            tags: <String>['Notifications'],
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
      final basePath = '$prefix/notifications/rules';
      final openApiPath = '$prefix/notifications/rules';
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
                final form = await bindForm(request, CreateAlertRuleForm.new);
                final notifications = ctx.service<NotificationService>();
                final apps = ctx.service<AppsService>();
                final result =
                    await this.createRule(form, notifications, apps, ctx);
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
            summary: 'Create an alert rule',
            tags: <String>['Notifications'],
            parameters: <Parameter>[],
            requestBody: RequestBody(required: true, content: {
              'application/json': MediaType(schema: <String, Object?>{
                r'$ref': '#/components/schemas/CreateAlertRuleForm'
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
      final basePath = '$prefix/notifications/rules/<id>';
      final openApiPath = '$prefix/notifications/rules/{id}';
      final RouteConfig __cfg =
          RouteConfig.empty.merge(const RouteConfig(requireAuth: true));
      router.put(
          basePath,
          gisilaRoute(
            app: app,
            config: __cfg,
            handler: (RequestContext ctx) async {
              try {
                final request = ctx.request;
                final id =
                    coerce<int>(request.params['id'], 'id', required: true);
                final form = await bindForm(request, UpdateAlertRuleForm.new);
                final notifications = ctx.service<NotificationService>();
                final apps = ctx.service<AppsService>();
                final result =
                    await this.updateRule(id, form, notifications, apps, ctx);
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
          'put',
          Operation(
            summary: 'Update an alert rule',
            tags: <String>['Notifications'],
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
                r'$ref': '#/components/schemas/UpdateAlertRuleForm'
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
      final basePath = '$prefix/notifications/rules/<id>';
      final openApiPath = '$prefix/notifications/rules/{id}';
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
                final notifications = ctx.service<NotificationService>();
                final apps = ctx.service<AppsService>();
                final result =
                    await this.deleteRule(id, notifications, apps, ctx);
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
            summary: 'Delete an alert rule',
            tags: <String>['Notifications'],
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
    {
      final basePath = '$prefix/notifications/events';
      final openApiPath = '$prefix/notifications/events';
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
                final notifications = ctx.service<NotificationService>();
                final apps = ctx.service<AppsService>();
                final scope = coerce<String?>(
                    request.url.queryParameters['scope'], 'scope',
                    required: false);
                final appId = coerce<int?>(
                    request.url.queryParameters['appId'], 'appId',
                    required: false);
                final postgresInstanceId = coerce<int?>(
                    request.url.queryParameters['postgresInstanceId'],
                    'postgresInstanceId',
                    required: false);
                final mongoInstanceId = coerce<int?>(
                    request.url.queryParameters['mongoInstanceId'],
                    'mongoInstanceId',
                    required: false);
                final limit = coerce<int?>(
                    request.url.queryParameters['limit'], 'limit',
                    required: false);
                final result = await this.listEvents(notifications, apps, ctx,
                    scope, appId, postgresInstanceId, mongoInstanceId, limit);
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
            summary: 'List alert event history',
            tags: <String>['Notifications'],
            parameters: <Parameter>[
              Parameter(
                name: 'scope',
                location: 'query',
                required: false,
                description: null,
                schema: <String, Object?>{
                  'type': <Object?>['string', 'null']
                },
              ),
              Parameter(
                name: 'appId',
                location: 'query',
                required: false,
                description: null,
                schema: <String, Object?>{
                  'type': <Object?>['integer', 'null'],
                  'format': 'int64'
                },
              ),
              Parameter(
                name: 'postgresInstanceId',
                location: 'query',
                required: false,
                description: null,
                schema: <String, Object?>{
                  'type': <Object?>['integer', 'null'],
                  'format': 'int64'
                },
              ),
              Parameter(
                name: 'mongoInstanceId',
                location: 'query',
                required: false,
                description: null,
                schema: <String, Object?>{
                  'type': <Object?>['integer', 'null'],
                  'format': 'int64'
                },
              ),
              Parameter(
                name: 'limit',
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
              })
            },
          ));
    }
    {
      final basePath = '$prefix/notifications/inbox';
      final openApiPath = '$prefix/notifications/inbox';
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
                final notifications = ctx.service<NotificationService>();
                final unreadOnly = coerce<bool?>(
                    request.url.queryParameters['unreadOnly'], 'unreadOnly',
                    required: false);
                final limit = coerce<int?>(
                    request.url.queryParameters['limit'], 'limit',
                    required: false);
                final result =
                    await this.inbox(notifications, ctx, unreadOnly, limit);
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
            summary: 'List the current user\'s notifications',
            tags: <String>['Notifications'],
            parameters: <Parameter>[
              Parameter(
                name: 'unreadOnly',
                location: 'query',
                required: false,
                description: null,
                schema: <String, Object?>{
                  'type': <Object?>['boolean', 'null']
                },
              ),
              Parameter(
                name: 'limit',
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
              })
            },
          ));
    }
    {
      final basePath = '$prefix/notifications/inbox/unread-count';
      final openApiPath = '$prefix/notifications/inbox/unread-count';
      final RouteConfig __cfg =
          RouteConfig.empty.merge(const RouteConfig(requireAuth: true));
      router.get(
          basePath,
          gisilaRoute(
            app: app,
            config: __cfg,
            handler: (RequestContext ctx) async {
              try {
                final notifications = ctx.service<NotificationService>();
                final result = await this.unreadCount(notifications, ctx);
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
            summary: 'Unread notification count for the bell badge',
            tags: <String>['Notifications'],
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
      final basePath = '$prefix/notifications/inbox/<id>/read';
      final openApiPath = '$prefix/notifications/inbox/{id}/read';
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
                final id =
                    coerce<int>(request.params['id'], 'id', required: true);
                final notifications = ctx.service<NotificationService>();
                final result = await this.markRead(id, notifications, ctx);
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
            summary: 'Mark a notification as read',
            tags: <String>['Notifications'],
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
              })
            },
          ));
    }
    {
      final basePath = '$prefix/notifications/inbox/read-all';
      final openApiPath = '$prefix/notifications/inbox/read-all';
      final RouteConfig __cfg =
          RouteConfig.empty.merge(const RouteConfig(requireAuth: true));
      router.post(
          basePath,
          gisilaRoute(
            app: app,
            config: __cfg,
            handler: (RequestContext ctx) async {
              try {
                final notifications = ctx.service<NotificationService>();
                final result = await this.markAllRead(notifications, ctx);
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
            summary: 'Mark every notification as read',
            tags: <String>['Notifications'],
            parameters: <Parameter>[],
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
  }
}
