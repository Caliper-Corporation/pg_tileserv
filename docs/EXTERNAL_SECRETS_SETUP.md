# Step-by-Step Setup for AWS Secrets Manager + External Secrets Operator

## Prerequisites

- AWS CLI configured with appropriate credentials
- kubectl configured for your cluster
- Helm 3 installed
- An EKS cluster (or other Kubernetes cluster with AWS access)

## Step 1: Store the Database URL in AWS Secrets Manager

```bash
# Store your database URL securely in AWS Secrets Manager
aws secretsmanager create-secret `
  --name pg-tileserv/database-url `
  --description "Database URL for pg_tileserv" `
  --secret-string "postgres://saasuser:YOUR_PASSWORD_HERE@spatial-sandbox.cmthsuqwksby.us-east-1.rds.amazonaws.com:5432/spatial_sandbox" `
  --region us-east-1
```

**Important:** Replace `YOUR_PASSWORD_HERE` with your actual password (or the full current credentials if not rotating yet).

## Step 2: Install External Secrets Operator

```bash
# Add the helm repository
helm repo add external-secrets https://charts.external-secrets.io
helm repo update

# Install the operator
helm upgrade --install external-secrets `
  external-secrets/external-secrets `
  -n external-secrets-system `
  --create-namespace `
  --wait
```

Verify installation:

```bash
kubectl get pods -n external-secrets-system
```

## Step 3: Create IAM Policy for Secret Access

Create an IAM policy that allows reading the secret:

```bash
cat > external-secrets-policy.json <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ],
      "Resource": "arn:aws:secretsmanager:us-east-1:*:secret:pg-tileserv/database-url*"
    }
  ]
}
EOF

# Create the policy
aws iam create-policy `
  --policy-name ExternalSecretsPolicy-pg-tileserv `
  --policy-document file://external-secrets-policy.json
```

## Step 4: Set Up IAM Role for Service Account (IRSA)

For EKS clusters, create a service account with the IAM role:

```bash
# Get your AWS account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Set your cluster name
CLUSTER_NAME="your-cluster-name"  # CHANGE THIS
REGION="us-east-1"
NAMESPACE="default"  # or your target namespace

# Create IAM service account using eksctl
eksctl create iamserviceaccount `
  --name external-secrets-sa `
  --namespace $NAMESPACE `
  --cluster $CLUSTER_NAME `
  --region $REGION `
  --attach-policy-arn arn:aws:iam::$ACCOUNT_ID:policy/ExternalSecretsPolicy-pg-tileserv `
  --approve `
  --override-existing-serviceaccounts
```

**Alternative for non-EKS clusters:** You can use AWS access keys, but IRSA is more secure.

## Step 5: Create the SecretStore Resource

Create a file `secretstore.yaml`:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: aws-secrets-manager
  namespace: default  # Change if using different namespace
spec:
  provider:
    aws:
      service: SecretsManager
      region: us-east-1
      auth:
        jwt:
          serviceAccountRef:
            name: external-secrets-sa
```

Apply it:

```bash
kubectl apply -f secretstore.yaml
```

Verify:

```bash
kubectl get secretstore aws-secrets-manager
```

## Step 6: Deploy Your Application

Now your Helm chart is configured to use external secrets. Deploy it:

```bash
cd c:\repos\SaaS\pg_tileserv

helm upgrade --install pg-tileserv ./deploy/pg-tileserv `
  --namespace default `
  --create-namespace `
  --wait
```

## Step 7: Verify Everything Works

Check the ExternalSecret:

```bash
kubectl get externalsecret
kubectl describe externalsecret pg-tileserv-db-secret
```

Check that the secret was created:

```bash
kubectl get secret pg-tileserv-db-secret
```

View the secret (be careful - this shows the actual password):

```bash
kubectl get secret pg-tileserv-db-secret -o jsonpath='{.data.DATABASE_URL}' | base64 -d
```

Check the pod:

```bash
kubectl get pods
kubectl logs -l app=pg-tileserv
```

## Troubleshooting

### ExternalSecret shows "SecretSyncedError"

Check the ExternalSecret status:

```bash
kubectl describe externalsecret pg-tileserv-db-secret
```

Common issues:

1. **IAM permissions:** Ensure the service account has the right IAM role
2. **Secret name:** Verify the secret exists in AWS Secrets Manager
3. **Region:** Ensure the region matches in SecretStore and AWS

### Secret not being created

Check External Secrets Operator logs:

```bash
kubectl logs -n external-secrets-system -l app.kubernetes.io/name=external-secrets
```

### Pod can't access the secret

Verify the secret exists and has the right key:

```bash
kubectl get secret pg-tileserv-db-secret -o yaml
```

The secret should have a `DATABASE_URL` key.

## Rotating Credentials

When you need to rotate the database password:

1. Update the secret in AWS Secrets Manager:

```bash
aws secretsmanager update-secret `
  --secret-id pg-tileserv/database-url `
  --secret-string "postgres://saasuser:NEW_PASSWORD@spatial-sandbox.cmthsuqwksby.us-east-1.rds.amazonaws.com:5432/spatial_sandbox"
```

1. The External Secrets Operator will automatically sync (default: every 1 hour)
   Or force immediate refresh by deleting the secret:

```bash
kubectl delete secret pg-tileserv-db-secret
# It will be recreated automatically
```

1. Restart your pods to use the new credentials:

```bash
kubectl rollout restart deployment pg-tileserv-deployment
```

## Alternative: Using AWS Access Keys (Less Secure)

If you can't use IRSA, you can use AWS access keys:

1. Create an IAM user with the policy from Step 3
2. Create access keys for that user
3. Create a Kubernetes secret with the keys:

```bash
kubectl create secret generic aws-credentials `
  --from-literal=access-key-id=YOUR_ACCESS_KEY `
  --from-literal=secret-access-key=YOUR_SECRET_KEY
```

1. Update the SecretStore to use the secret:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: aws-secrets-manager
spec:
  provider:
    aws:
      service: SecretsManager
      region: us-east-1
      auth:
        secretRef:
          accessKeyIDSecretRef:
            name: aws-credentials
            key: access-key-id
          secretAccessKeySecretRef:
            name: aws-credentials
            key: secret-access-key
```

## Next Steps

✅ Your database credentials are now securely stored in AWS Secrets Manager
✅ External Secrets Operator manages the Kubernetes secret automatically
✅ No plaintext credentials in your git repository
✅ Centralized secret management with audit trails
✅ Support for automatic credential rotation

**Don't forget to rotate your database password** since the old one was committed to git!
