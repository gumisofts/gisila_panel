// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'auth.dart';

// **************************************************************************
// ControllerGenerator
// **************************************************************************

// **************************************************
// gisila_doc: generated for AuthApi
// **************************************************

extension AuthApiGisilaDoc on AuthApi {
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
    spec.putSchema('LoginForm', <String, Object?>{
      'type': 'object',
      'properties': <String, Object?>{
        'email': <String, Object?>{'type': 'string', 'format': 'email'},
        'password': <String, Object?>{'type': 'string'}
      }
    });
    spec.putSchema('ChangePasswordForm', <String, Object?>{
      'type': 'object',
      'properties': <String, Object?>{
        'oldPassword': <String, Object?>{'type': 'string'},
        'newPassword': <String, Object?>{'type': 'string'}
      }
    });
    spec.putSchema('CreateUserForm', <String, Object?>{
      'type': 'object',
      'properties': <String, Object?>{
        'email': <String, Object?>{'type': 'string', 'format': 'email'},
        'password': <String, Object?>{'type': 'string'},
        'firstName': <String, Object?>{'type': 'string'},
        'lastName': <String, Object?>{'type': 'string'},
        'isSuperuser': <String, Object?>{'type': 'boolean'}
      }
    });
    spec.putSchema('UpdateUserForm', <String, Object?>{
      'type': 'object',
      'properties': <String, Object?>{
        'firstName': <String, Object?>{'type': 'string'},
        'lastName': <String, Object?>{'type': 'string'},
        'isActive': <String, Object?>{'type': 'boolean'},
        'isSuperuser': <String, Object?>{'type': 'boolean'}
      }
    });
    spec.putTag('Auth');
    {
      final basePath = '$prefix/auth/login';
      final openApiPath = '$prefix/auth/login';
      final RouteConfig __cfg = RouteConfig.empty
          .merge(const RouteConfig(isPublic: true))
          .merge(const RouteConfig(
              rateLimit: const RateLimitConfig(requestsPerMinute: 60)));
      router.post(
          basePath,
          gisilaRoute(
            app: app,
            config: __cfg,
            handler: (RequestContext ctx) async {
              try {
                final request = ctx.request;
                final form = await bindForm(request, LoginForm.new);
                final auth = ctx.service<AuthService>();
                final result = await this.login(form, auth);
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
            summary: 'Sign in with email + password',
            tags: <String>['Auth'],
            parameters: <Parameter>[],
            requestBody: RequestBody(required: true, content: {
              'application/json': MediaType(schema: <String, Object?>{
                r'$ref': '#/components/schemas/LoginForm'
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
      final basePath = '$prefix/auth/me';
      final openApiPath = '$prefix/auth/me';
      final RouteConfig __cfg =
          RouteConfig.empty.merge(const RouteConfig(requireAuth: true));
      router.get(
          basePath,
          gisilaRoute(
            app: app,
            config: __cfg,
            handler: (RequestContext ctx) async {
              try {
                final result = await this.me(ctx);
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
            summary: 'Get the authenticated user profile',
            tags: <String>['Auth'],
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
      final basePath = '$prefix/auth/change-password';
      final openApiPath = '$prefix/auth/change-password';
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
                final form = await bindForm(request, ChangePasswordForm.new);
                final auth = ctx.service<AuthService>();
                final result = await this.changePassword(form, auth, ctx);
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
            summary: 'Change password',
            tags: <String>['Auth'],
            parameters: <Parameter>[],
            requestBody: RequestBody(required: true, content: {
              'application/json': MediaType(schema: <String, Object?>{
                r'$ref': '#/components/schemas/ChangePasswordForm'
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
      final basePath = '$prefix/auth/users';
      final openApiPath = '$prefix/auth/users';
      final RouteConfig __cfg =
          RouteConfig.empty.merge(const RouteConfig(requireAuth: true));
      router.get(
          basePath,
          gisilaRoute(
            app: app,
            config: __cfg,
            handler: (RequestContext ctx) async {
              try {
                final auth = ctx.service<AuthService>();
                final result = await this.listUsers(auth, ctx);
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
            summary: 'List all user accounts (superuser only)',
            tags: <String>['Auth'],
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
      final basePath = '$prefix/auth/users';
      final openApiPath = '$prefix/auth/users';
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
                final form = await bindForm(request, CreateUserForm.new);
                final auth = ctx.service<AuthService>();
                final result = await this.createUser(form, auth, ctx);
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
            summary: 'Create a new user account (superuser only)',
            tags: <String>['Auth'],
            parameters: <Parameter>[],
            requestBody: RequestBody(required: true, content: {
              'application/json': MediaType(schema: <String, Object?>{
                r'$ref': '#/components/schemas/CreateUserForm'
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
      final basePath = '$prefix/auth/users/<id>';
      final openApiPath = '$prefix/auth/users/<id>';
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
                final id = coerce<int>(request.url.queryParameters['id'], 'id',
                    required: true);
                final form = await bindForm(request, UpdateUserForm.new);
                final auth = ctx.service<AuthService>();
                final result = await this.updateUser(id, form, auth, ctx);
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
            summary: 'Update a user account (superuser only)',
            tags: <String>['Auth'],
            parameters: <Parameter>[
              Parameter(
                name: 'id',
                location: 'query',
                required: true,
                description: null,
                schema: <String, Object?>{'type': 'integer', 'format': 'int64'},
              )
            ],
            requestBody: RequestBody(required: true, content: {
              'application/json': MediaType(schema: <String, Object?>{
                r'$ref': '#/components/schemas/UpdateUserForm'
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
      final basePath = '$prefix/auth/users/<id>';
      final openApiPath = '$prefix/auth/users/<id>';
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
                final id = coerce<int>(request.url.queryParameters['id'], 'id',
                    required: true);
                final auth = ctx.service<AuthService>();
                final result = await this.deleteUser(id, auth, ctx);
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
            summary: 'Delete a user account (superuser only)',
            tags: <String>['Auth'],
            parameters: <Parameter>[
              Parameter(
                name: 'id',
                location: 'query',
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
