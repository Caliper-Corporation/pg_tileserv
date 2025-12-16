# pg_tileserv

Vector tile server for PostgreSQL/PostGIS databases deployed in Kubernetes.

## Overview

pg_tileserv is a high-performance vector tile server connected to our RDS PostgreSQL database. It serves map tiles for area layers exported from Maptitude to PostgreSQL tables.

This repository uses the [Caliper fork of pg_tileserv](https://github.com/Caliper-Corporation/pg_tileserv), based on the [CrunchyData original](https://github.com/CrunchyData/pg_tileserv).

## Architecture

**Single Shared Instance**: Deployed in the `default` namespace of our EKS cluster, serving all environments (dev, staging, production) from one RDS PostgreSQL instance.

**Benefits:**

- Reduced infrastructure costs
- Consistent tile serving across environments
- Simplified deployment and maintenance
- Single point for monitoring

**Service Endpoint**: `http://pg-tileserv-service.default.svc.cluster.local:7800`

## Vector Tile URL Format

```text
${DB_TILESERVER_URL}/${schema}.${table}/{z}/{x}/{y}.pbf
```

**Example:**

```text
http://localhost:7800/user_geometry.mcz7fn2m001x0wf35sfl_mcz7er6p001p2cnv98ne_development_2/11/343/799.pbf
```

**Components:**

- `schema`: Database schema (e.g., `user_geometry`)
- `table`: Format `{layerid}_{mapid}_{accountid}`
  - `layerid`: Layer identifier from map model
  - `mapid`: Map identifier
  - `accountid`: Account ID with dashes replaced by underscores

## Local Development

On Windows development machines, use the pre-packaged executable in the `windows/` subfolder.

**Configuration**: `windows/pg_tileserv.toml`

**Backend Configuration** (`saas-backend/app/config/override.env.js`):

```javascript
DB_TILESERVER_URL: 'http://localhost:7800'
```

## Deployment

### Prerequisites

1. **AWS ECR**: Repository named `pg-tileserv`
2. **GitHub Secrets**:
   - `AWS_ACCESS_KEY_ID`
   - `AWS_SECRET_ACCESS_KEY`
   - `KUBECONFIG_B64`
3. **Database**: Shared RDS PostgreSQL endpoint

### Configuration

Update `databaseUrl` in the values file with your shared RDS endpoint:

```yaml
# deploy/pg-tileserv/values.yaml
env: shared
releaseName: pg-tileserv
containerRepo: pg-tileserv
databaseUrl: "postgresql://username:password@rds-endpoint.us-east-1.rds.amazonaws.com:5432/caliper"
resources:
  requests:
    memory: "1Gi"
    cpu: "500m"
  limits:
    memory: "2Gi"
    cpu: "2000m"
```

> **Note**: Consider using AWS Secrets Manager instead of hardcoding credentials.

### Automated Deployment

GitHub Actions workflow automatically deploys on:

- Push to `dev`, `staging`, or `main` branches
- Daily cron (7:30 AM UTC) for `main`
- Manual workflow dispatch

All branches deploy to the same shared instance in `default` namespace.

### Manual Deployment

```bash
# Build image
docker build -t pg-tileserv:local .

# Deploy to Kubernetes
helm upgrade --install pg-tileserv \
  --namespace default \
  --create-namespace \
  --set containerTag=latest \
  --values deploy/pg-tileserv/values.yaml \
  deploy/pg-tileserv
```

## Backend Integration

The saas-backend connects via `DB_TILESERVER_URL` in ConfigMaps:

```yaml
DB_TILESERVER_URL: "http://pg-tileserv-service.default.svc.cluster.local:7800"
```

Updated in:

- `saas-backend/deploy/caliper-saas-api/templates/caliper-saas-api-configmap.yaml`
- `saas-backend/deploy/values/{dev,staging,production}/values.yaml`

## Monitoring

### Health Endpoints

- `/index.json` - Service metadata (used for probes)
- `/` - Web UI for browsing layers

### Kubernetes Probes

```yaml
livenessProbe:
  httpGet:
    path: /index.json
    port: 7800
readinessProbe:
  httpGet:
    path: /index.json
    port: 7800
```

### Datadog

Logs collected with labels:

- `source: pg_tileserv`
- `service: pg-tileserv-service`
- `env: shared`

## Troubleshooting

### Check Status

```bash
kubectl get pods -n default -l app=pg-tileserv
```

### View Logs

```bash
kubectl logs -n default -l app=pg-tileserv --tail=100 -f
```

### Test Connectivity

```bash
# Port forward
kubectl port-forward -n default svc/pg-tileserv-service 7800:7800

# Test from cluster
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- \
  curl http://pg-tileserv-service.default.svc.cluster.local:7800/index.json

# Test from backend pod
kubectl exec -it -n dev <backend-pod-name> -- \
  curl http://pg-tileserv-service.default.svc.cluster.local:7800/index.json
```

### Rollback

```bash
helm rollback pg-tileserv -n default
```

## Resource Configuration

Recommended starting configuration:

| Resource | Request | Limit |
|----------|---------|-------|
| Memory   | 1Gi     | 2Gi   |
| CPU      | 500m    | 2000m |

Adjust in `deploy/pg-tileserv/values.yaml` based on monitoring.

**Scaling Tips:**

- Monitor tile generation latency
- Consider horizontal pod autoscaling for high load
- Connection pooling handled internally by pg_tileserv

## Security

1. **Credentials**: Stored in Kubernetes secrets
   - Migrate to AWS Secrets Manager with IRSA
   - Rotate regularly
2. **CORS**: Set to `*` (restrict in production if needed)
3. **Network Policies**: Add NetworkPolicy to restrict access
4. **HTTPS**: Runs HTTP internally (secure within cluster)
5. **Database**: RDS security groups should only allow EKS traffic

## Project Structure

```text
pg_tileserv/
├── Dockerfile                  # Multi-stage build
├── .github/workflows/
│   └── deploy.yml              # Deployment pipeline
├── deploy/
│   ├── config.yaml             # ECR/Helm config
│   └── pg-tileserv/            # Helm chart
│       ├── Chart.yaml
│       ├── values.yaml         # Single values file
│       └── templates/
├── windows/                     # Windows dev executable
└── README.md
```

## References

- [Caliper pg_tileserv Fork](https://github.com/Caliper-Corporation/pg_tileserv)
- [CrunchyData Original](https://github.com/CrunchyData/pg_tileserv)
- [Deployment Checklist](DEPLOYMENT_CHECKLIST.md)

The middleware should at least:

Only return a vector tile if the request referrer is in the domain *.caliper.com
Only return a vector tile for a particular account id and map id if the referrer includes the account id and map id.
Only return a vector tile if the request includes some authorization information (e.g. a valid JWT token, or a signed cookie?)
Cache the most recently requested vector tiles by URL.

(Should this middleware be part of saas/backend? Or a specialized micro-service? Or Ngninx proxy rules themselves?)
