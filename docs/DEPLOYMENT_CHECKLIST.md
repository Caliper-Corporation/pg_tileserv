# pg_tileserv Setup Checklist

## Architecture Overview

**Single Shared Instance**: pg_tileserv runs as a single deployment in the `default` namespace, serving vector tiles from a shared RDS PostgreSQL database to all environments (dev, staging, production).

## Pre-Deployment Steps

### 1. AWS ECR Repository Setup

- [ ] Create ECR repository named `pg-tileserv` in AWS account `110683733147`
- [ ] Verify IAM permissions for GitHub Actions to push images to ECR

### 2. GitHub Repository Setup

- [ ] Fork from <https://github.com/Caliper-Corporation/pg_tileserv>
- [ ] Ensure repository has required secrets:
  - [ ] `AWS_ACCESS_KEY_ID`
  - [ ] `AWS_SECRET_ACCESS_KEY`
  - [ ] `KUBECONFIG_B64` (base64-encoded kubeconfig)

### 3. Database Configuration

- [ ] Get **shared** RDS PostgreSQL endpoint (single instance for all environments)
- [ ] Verify database user has appropriate permissions for schema access
- [ ] Confirm database has required schemas (`user_geometry`, etc.)
- [ ] Update the single values file: `deploy/pg-tileserv/values.yaml`

### 4. Repository Setup

- [ ] Initialize git repository if not already done
- [ ] Create branches: `dev`, `staging`, `main`
- [ ] Push initial code to GitHub

## Deployment Steps

### Initial Deployment (Any Branch)

1. [ ] Update database URL in all values files
2. [ ] Push code to `dev` branch (recommended for initial testing)
3. [ ] GitHub Actions workflow triggers automatically
4. [ ] Verify deployment: `kubectl get pods -n default -l app=pg-tileserv`
5. [ ] Test health endpoint: `kubectl port-forward -n default svc/pg-tileserv-service 7800:7800`
6. [ ] Access <http://localhost:7800/index.json> in browser
7. [ ] Verify service is accessible from cluster:

   ```bash
   kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- \
     curl http://pg-tileserv-service.default.svc.cluster.local:7800/index.json
   ```

### Backend Integration Testing

#### Dev Backend

1. [ ] Verify `DB_TILESERVER_URL` is set in dev backend ConfigMap
2. [ ] Restart dev backend pods if needed: `kubectl rollout restart deployment -n dev`
3. [ ] Check backend logs for successful connection
4. [ ] Test map layer rendering with tiles from pg_tileserv

#### Staging Backend

1. [ ] Verify `DB_TILESERVER_URL` is set in staging backend ConfigMap
2. [ ] Restart staging backend pods if needed: `kubectl rollout restart deployment -n staging`
3. [ ] Check backend logs for successful connection
4. [ ] Test map layer rendering with tiles from pg_tileserv

#### Production Backend

1. [ ] Verify `DB_TILESERVER_URL` is set in production backend ConfigMap
2. [ ] Restart production backend pods if needed: `kubectl rollout restart deployment -n prod`
3. [ ] Monitor Datadog for any errors
4. [ ] Test map layer rendering with tiles from pg_tileserv

### Production Deployment (Main Branch)

1. [ ] Complete testing in dev and staging environments
2. [ ] Merge to `main` branch
3. [ ] Scheduled deployment at 7:30 AM UTC daily OR manual workflow dispatch
4. [ ] Monitor deployment: `kubectl get pods -n default -l app=pg-tileserv`
5. [ ] Check all backend environments for connectivity
6. [ ] Monitor Datadog for errors across all environments
7. [ ] Verify performance metrics and tile loading times

## Post-Deployment Monitoring

### Health Checks

- [ ] Verify liveness probes are passing
- [ ] Verify readiness probes are passing
- [ ] Check resource usage (CPU/Memory)

### Datadog

- [ ] Verify logs are being collected
- [ ] Set up dashboard for pg_tileserv metrics
- [ ] Create alert for service availability
- [ ] Create alert for error rate threshold

### Performance

- [ ] Monitor tile generation latency
- [ ] Check database connection pool usage
- [ ] Monitor memory usage over time
- [ ] Review CPU usage patterns

## Security Hardening (Post-MVP)

- [ ] Move database credentials to AWS Secrets Manager
- [ ] Update deployment to use IRSA (IAM Roles for Service Accounts)
- [ ] Implement NetworkPolicy for pod-to-pod communication
- [ ] Review and restrict CORS settings for production
- [ ] Set up ingress with HTTPS if external access needed
- [ ] Enable audit logging
- [ ] Implement rate limiting if needed

## Rollback Plan

If deployment fails or causes issues:

### Immediate Rollback

```bash
# Rollback to previous Helm release (shared instance in default namespace)
helm rollback pg-tileserv -n default
```

### Emergency Fix

1. Point backends to a backup tile server endpoint (if available)
2. Scale pg_tileserv deployment to 0 replicas: `kubectl scale deployment pg-tileserv-deployment -n default --replicas=0`
3. Investigate logs and fix issues
4. Redeploy when ready: `kubectl scale deployment pg-tileserv-deployment -n default --replicas=1`

### Impact Assessment

- **Single point of failure**: All environments share this service
- Test changes in lower environments by temporarily pointing only dev backend to the new deployment
- Consider blue/green deployment for zero-downtime updates

## Useful Commands

### Check Service Status

```bash
# Check the shared pg_tileserv deployment
kubectl get all -n default -l app=pg-tileserv

# Check if service is reachable from all backend namespaces
kubectl get endpoints -n default pg-tileserv-service
```

### View Logs

```bash
kubectl logs -n default -l app=pg-tileserv --tail=100 -f
```

### Describe Pod

```bash
kubectl describe pod -n default -l app=pg-tileserv
```

```bash
kubectl describe pod -n dev -l app=pg-tileserv
```

### Test Service

```bash
# Port forward to local machine
kubectl port-forward -n default svc/pg-tileserv-service 7800:7800

# From within cluster
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- \
  curl http://pg-tileserv-service.default.svc.cluster.local:7800/index.json

# Test from backend pod
kubectl exec -it -n dev <backend-pod-name> -- \
  curl http://pg-tileserv-service.default.svc.cluster.local:7800/index.json
```

### Manual Deployment

```bash
# Build and push image
docker build -t 110683733147.dkr.ecr.us-east-1.amazonaws.com/pg-tileserv:manual .
docker push 110683733147.dkr.ecr.us-east-1.amazonaws.com/pg-tileserv:manual

# Deploy with Helm to default namespace
helm upgrade --install pg-tileserv \
  --namespace default \
  --create-namespace \
  --set containerTag=manual \
  --values deploy/pg-tileserv/values.yaml \
  deploy/pg-tileserv
```

## Documentation Links

- [pg_tileserv GitHub](https://github.com/CrunchyData/pg_tileserv)
- [Helm Documentation](https://helm.sh/docs/)
- [Kubernetes Services](https://kubernetes.io/docs/concepts/services-networking/service/)
- [ECR User Guide](https://docs.aws.amazon.com/ecr/index.html)
