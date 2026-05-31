Build a modern open-source lightweight PaaS hosting panel optimized for compiled backend applications such as Dart, Go, Rust, Zig, Bun, Node.js, and Python applications.

The platform should work similarly to Heroku, Railway, Render, and Coolify, but instead of relying heavily on Docker and Kubernetes, it should focus on ultra-lightweight deployment using native Linux execution with systemd sandboxing, Linux users, AppArmor, cgroups, seccomp, and Nginx reverse proxying.

Core philosophy:

- High-density hosting
- Low RAM usage
- Low-cost VPS friendly
- Minimal overhead
- Secure multi-tenant hosting
- Optimized for compiled backend apps
- Open-source first
- Self-hostable
- Modern UI/UX

Tech stack:
Frontend:

- Next.js
- TypeScript
- Tailwind CSS
- shadcn/ui

Backend:

- Dart + Gisila Tools
- PostgreSQL
- Redis
- Celery Replacement tools

Infrastructure:

- Ubuntu Linux
- systemd
- Nginx
- AppArmor
- cgroups
- seccomp
- Let's Encrypt
- journald

The platform architecture should include:

1. Control Plane

- Authentication
- User management
- Billing-ready architecture
- Team/project management
- API tokens
- SSH key management
- Deployment management
- Domain management
- SSL management
- Environment variables
- Logs viewer
- Metrics dashboard
- Deployment history
- Rollback system

2. Deployment Engine
   When a user deploys an app:

- Create isolated Linux user
- Create isolated app directory
- Assign internal port automatically
- Generate secure systemd service
- Apply resource limits
- Apply AppArmor profile
- Generate Nginx reverse proxy config
- Generate SSL certificate automatically
- Start/restart service
- Stream logs in real time

3. Supported Deployment Types

- Upload Linux executable binaries
- Git repository deployment
- ZIP source upload
- Automatic Dart compilation
- Automatic Go build
- Automatic Rust cargo build
- Automatic Node.js startup

4. Security Requirements

- No root execution
- Dedicated Linux user per app
- systemd sandboxing
- cgroup resource limits
- AppArmor profiles
- seccomp syscall filtering
- Isolated temporary directories
- Filesystem restrictions
- Prevent access to host filesystem
- Restrict internal networking
- Process limits
- Rate limiting
- Deployment validation

5. systemd Service Generation
   Generate secure services similar to:

[Unit]
Description=User App

[Service]
User=app123
WorkingDirectory=/srv/apps/app123
ExecStart=/srv/apps/app123/app
Restart=always
RestartSec=5

NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
RestrictRealtime=true
RestrictNamespaces=true
MemoryMax=512M
CPUQuota=50%
TasksMax=100

EnvironmentFile=/srv/apps/app123/.env

[Install]
WantedBy=multi-user.target

6. Nginx Integration
   Automatically generate reverse proxy configs:

server {
listen 80;
server_name app.example.com;

    location / {
        proxy_pass http://127.0.0.1:4001;

        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Real-IP $remote_addr;
    }

}

7. Logging & Monitoring

- Real-time log streaming
- journald integration
- CPU usage graphs
- RAM usage graphs
- Request metrics
- Uptime monitoring
- Deployment events
- Audit logs

8. Open Source Structure
   Design the platform as:

- Modular
- Plugin-based
- API-first
- Self-hostable
- Enterprise extensible

9. Developer Experience

- One-click deployments
- Fast deployments
- Simple UI
- GitHub integration
- Automatic SSL
- Custom domains
- Instant restart/redeploy
- Environment variable editor
- Build logs
- Health checks

10. UI Design Requirements

- Modern dashboard similar to Railway/Render
- Dark mode support
- Responsive layout
- Clean developer-focused UI
- Deployment timeline
- Live status indicators
- Real-time logs terminal
- Metrics graphs
- Project cards
- Domain management screens

11. Future Scalability
    Design architecture to later support:

- Multiple nodes
- Distributed deployments
- Optional Docker isolation
- Cluster scheduling
- Horizontal scaling
- Managed databases
- Object storage
- Background workers

12. Important Constraints

- Avoid Kubernetes complexity
- Avoid heavy Docker dependency for MVP
- Prioritize lightweight execution
- Prioritize low-memory environments
- Optimize for cheap VPS hosting
- Keep deployment latency minimal

Generate:

- Full architecture design
- Database schema
- API design
- Backend structure
- Frontend structure
- Deployment engine design
- Security model
- Directory structure
- Example code snippets
- Infrastructure automation approach
- Suggested roadmap from MVP to production
