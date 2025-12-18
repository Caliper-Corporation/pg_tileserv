# External Secrets Setup - One-Time Cluster Configuration

The External Secrets service account with IAM role (IRSA) is a **cluster-level resource** that only needs to be set up once per cluster, not per application deployment.

## Quick Setup

Run the automated script:

```powershell
.\scripts\create-iam-role-for-external-secrets.ps1 -ClusterName "your-cluster-name"
```

This will:

1. Create the IAM policy for reading secrets from AWS Secrets Manager
2. Create an IAM role with IRSA trust policy
3. Output the role ARN to add to `values.yaml`

## Manual Setup (if script fails)

### Step 1: Create IAM Policy

```bash
aws iam create-policy \
  --policy-name ExternalSecretsPolicy-pg-tileserv \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ],
      "Resource": "arn:aws:secretsmanager:us-east-1:*:secret:pg-tileserv/*"
    }]
  }'
```

### Step 2: Create IRSA with eksctl

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
CLUSTER_NAME="your-cluster-name"

eksctl create iamserviceaccount \
  --name external-secrets-sa \
  --namespace default \
  --cluster $CLUSTER_NAME \
  --region us-east-1 \
  --attach-policy-arn arn:aws:iam::$ACCOUNT_ID:policy/ExternalSecretsPolicy-pg-tileserv \
  --approve \
  --override-existing-serviceaccounts
```

### Step 3: Get the Role ARN

```bash
kubectl get serviceaccount external-secrets-sa -n default \
  -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}'
```

### Step 4: Update values.yaml

Add the role ARN to `values.yaml`:

```yaml
externalSecretsIamRoleArn: "arn:aws:iam::ACCOUNT_ID:role/eksctl-CLUSTER-addon-iamserviceaccount-Role..."
```

## Why is this needed?

The External Secrets Operator needs to authenticate with AWS Secrets Manager to retrieve secrets. IRSA (IAM Roles for Service Accounts) allows Kubernetes service accounts to assume IAM roles, providing secure, credential-less authentication.

## Troubleshooting

### Error: "AccessDenied: Not authorized to perform sts:AssumeRoleWithWebIdentity"

The IAM role doesn't have the correct trust policy. Ensure eksctl created the role with IRSA trust policy, or create it manually with:

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/oidc.eks.REGION.amazonaws.com/id/OIDC_ID"
    },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "oidc.eks.REGION.amazonaws.com/id/OIDC_ID:sub": "system:serviceaccount:default:external-secrets-sa"
      }
    }
  }]
}
```

### Error: "SecretStore is not ready"

Check the service account has the role annotation:

```bash
kubectl describe serviceaccount external-secrets-sa -n default
```

Should show:
```
Annotations: eks.amazonaws.com/role-arn: arn:aws:iam::...
```

### Error: "could not get secret data from provider"

The IAM role doesn't have permissions to read the secret. Verify the policy is attached:

```bash
aws iam list-attached-role-policies --role-name YOUR_ROLE_NAME
```
