// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mail.dart';

// **************************************************************************
// ControllerGenerator
// **************************************************************************

// **************************************************
// gisila_doc: generated for MailApi
// **************************************************

extension MailApiGisilaDoc on MailApi {
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
    spec.putSchema('MailDomainForm', <String, Object?>{
      'type': 'object',
      'properties': <String, Object?>{
        'domain': <String, Object?>{'type': 'string'}
      }
    });
    spec.putSchema('MailDomainUpdateForm', <String, Object?>{
      'type': 'object',
      'properties': <String, Object?>{
        'mailHostname': <String, Object?>{'type': 'string'},
        'dmarcPolicy': <String, Object?>{'type': 'string'}
      }
    });
    spec.putSchema('MailAccountForm', <String, Object?>{
      'type': 'object',
      'properties': <String, Object?>{
        'localPart': <String, Object?>{'type': 'string'},
        'password': <String, Object?>{'type': 'string'},
        'quotaMb': <String, Object?>{'type': 'integer', 'format': 'int64'}
      }
    });
    spec.putSchema('MailPasswordForm', <String, Object?>{
      'type': 'object',
      'properties': <String, Object?>{
        'password': <String, Object?>{'type': 'string'}
      }
    });
    spec.putTag('Mail');
    {
      final basePath = '$prefix/mail/status';
      final openApiPath = '$prefix/mail/status';
      final RouteConfig __cfg =
          RouteConfig.empty.merge(const RouteConfig(requireAuth: true));
      router.get(
          basePath,
          gisilaRoute(
            app: app,
            config: __cfg,
            handler: (RequestContext ctx) async {
              try {
                final svc = ctx.service<MailService>();
                final result = await this.status(svc);
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
            summary: 'Whether the mail tooling is installed',
            tags: <String>['Mail'],
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
      final basePath = '$prefix/mail/install';
      final openApiPath = '$prefix/mail/install';
      final RouteConfig __cfg =
          RouteConfig.empty.merge(const RouteConfig(requireAuth: true));
      router.post(
          basePath,
          gisilaRoute(
            app: app,
            config: __cfg,
            handler: (RequestContext ctx) async {
              try {
                final svc = ctx.service<MailService>();
                final result = await this.install(svc);
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
            summary: 'Install the mail tooling on this host',
            tags: <String>['Mail'],
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
    {
      final basePath = '$prefix/mail/domains';
      final openApiPath = '$prefix/mail/domains';
      final RouteConfig __cfg =
          RouteConfig.empty.merge(const RouteConfig(requireAuth: true));
      router.get(
          basePath,
          gisilaRoute(
            app: app,
            config: __cfg,
            handler: (RequestContext ctx) async {
              try {
                final svc = ctx.service<MailService>();
                final result = await this.listDomains(svc);
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
            summary: 'List mail domains',
            tags: <String>['Mail'],
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
      final basePath = '$prefix/mail/domains';
      final openApiPath = '$prefix/mail/domains';
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
                final form = await bindForm(request, MailDomainForm.new);
                final svc = ctx.service<MailService>();
                final result = await this.addDomain(form, svc);
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
            summary: 'Add a mail domain',
            tags: <String>['Mail'],
            parameters: <Parameter>[],
            requestBody: RequestBody(required: true, content: {
              'application/json': MediaType(schema: <String, Object?>{
                r'$ref': '#/components/schemas/MailDomainForm'
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
      final basePath = '$prefix/mail/domains/<id>';
      final openApiPath = '$prefix/mail/domains/{id}';
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
                final form = await bindForm(request, MailDomainUpdateForm.new);
                final svc = ctx.service<MailService>();
                final result = await this.updateDomain(id, form, svc);
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
            summary: 'Update mail hostname / DMARC policy',
            tags: <String>['Mail'],
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
                r'$ref': '#/components/schemas/MailDomainUpdateForm'
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
      final basePath = '$prefix/mail/domains/<id>';
      final openApiPath = '$prefix/mail/domains/{id}';
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
                final svc = ctx.service<MailService>();
                final result = await this.removeDomain(id, svc);
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
            summary: 'Remove a mail domain and its mailboxes',
            tags: <String>['Mail'],
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
      final basePath = '$prefix/mail/domains/<id>/dns';
      final openApiPath = '$prefix/mail/domains/{id}/dns';
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
                final svc = ctx.service<MailService>();
                final result = await this.domainDns(id, svc);
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
            summary: 'DNS records to publish for a domain',
            tags: <String>['Mail'],
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
      final basePath = '$prefix/mail/domains/<id>/sync';
      final openApiPath = '$prefix/mail/domains/{id}/sync';
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
                final svc = ctx.service<MailService>();
                final result = await this.syncDomain(id, svc);
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
            summary: 'Re-queue a mail sync for this domain',
            tags: <String>['Mail'],
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
      final basePath = '$prefix/mail/domains/<id>/accounts';
      final openApiPath = '$prefix/mail/domains/{id}/accounts';
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
                final svc = ctx.service<MailService>();
                final result = await this.listAccounts(id, svc);
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
            summary: 'List mailboxes in a domain',
            tags: <String>['Mail'],
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
      final basePath = '$prefix/mail/domains/<id>/accounts';
      final openApiPath = '$prefix/mail/domains/{id}/accounts';
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
                final form = await bindForm(request, MailAccountForm.new);
                final svc = ctx.service<MailService>();
                final result = await this.addAccount(id, form, svc);
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
            summary: 'Create a mailbox',
            tags: <String>['Mail'],
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
                r'$ref': '#/components/schemas/MailAccountForm'
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
      final basePath = '$prefix/mail/accounts/<id>/password';
      final openApiPath = '$prefix/mail/accounts/{id}/password';
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
                final form = await bindForm(request, MailPasswordForm.new);
                final svc = ctx.service<MailService>();
                final result = await this.setPassword(id, form, svc);
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
            summary: 'Reset a mailbox password',
            tags: <String>['Mail'],
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
                r'$ref': '#/components/schemas/MailPasswordForm'
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
      final basePath = '$prefix/mail/accounts/<id>';
      final openApiPath = '$prefix/mail/accounts/{id}';
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
                final svc = ctx.service<MailService>();
                final result = await this.removeAccount(id, svc);
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
            summary: 'Delete a mailbox',
            tags: <String>['Mail'],
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
