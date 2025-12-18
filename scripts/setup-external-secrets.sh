#!/bin/bash
# Setup script for AWS Secrets Manager + External Secrets Operator
# Run this to configure external secrets for pg_tileserv

set -e

echo "🔐 Setting up AWS Secrets Manager + External Secrets Operator"
echo ""

# Configuration
SECRET_NAME="pg-tileserv/database-url"
REGION="us-east-1"
NAMESPACE="default"  # Change if deploying to different namespace

# Step 1: Create secret in AWS Secrets Manager
echo "Step 1: Creating secret in AWS Secrets Manager..."
echo "Enter your database URL (format: postgres://user:pass@host:port/db):"
read -s DATABASE_URL

aws secretsmanager create-secret \
  --name "$SECRET_NAME" \
  --description "Database URL for pg_tileserv" \
  --secret-string "$DATABASE_URL" \
  --region "$REGION" || {
    echo "Secret might already exist. Updating instead..."
    aws secretsmanager update-secret \
      --secret-id "$SECRET_NAME" \
      --secret-string "$DATABASE_URL" \
      --region "$REGION"
  }

echo "✅ Secret created/updated in AWS Secrets Manager"
echo ""

# Step 2: Install External Secrets Operator
echo "Step 2: Installing External Secrets Operator..."
helm repo add external-secrets https://charts.external-secrets.io 2>/dev/null || true
helm repo update

helm upgrade --install external-secrets \
  external-secrets/external-secrets \
  -n external-secrets-system \
  --create-namespace \
  --wait

echo "✅ External Secrets Operator installed"
echo ""

# Step 3: Create IAM policy for External Secrets
echo "Step 3: Creating IAM policy..."
cat > /tmp/external-secrets-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ],
      "Resource": "arn:aws:secretsmanager:${REGION}:*:secret:${SECRET_NAME}*"
    }
  ]
}
EOF

POLICY_NAME="ExternalSecretsPolicy-pg-tileserv"
aws iam create-policy \
  --policy-name "$POLICY_NAME" \
  --policy-document file:///tmp/external-secrets-policy.json \
  --region "$REGION" 2>/dev/null || echo "Policy might already exist, continuing..."

echo "✅ IAM policy created"
echo ""

# Step 4: Create service account with IAM role (EKS only)
echo "Step 4: Service account and IAM role setup"
echo "For EKS, you need to:"
echo "1. Create an IAM role for service account (IRSA)"
echo "2. Attach the policy created above"
echo "3. Annotate the service account"
echo ""
echo "Run these commands (replace ACCOUNT_ID and CLUSTER_NAME):"
echo ""
cat <<'EOF'
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
CLUSTER_NAME="your-cluster-name"
REGION="us-east-1"

# Create IAM role
eksctl create iamserviceaccount \
  --name external-secrets-sa \
  --namespace default \
  --cluster $CLUSTER_NAME \
  --region $REGION \
  --attach-policy-arn arn:aws:iam::$ACCOUNT_ID:policy/ExternalSecretsPolicy-pg-tileserv \
  --approve \
  --override-existing-serviceaccounts
EOF
echo ""

# Step 5: Create SecretStore
echo "Step 5: Creating SecretStore..."
cat > /tmp/secretstore.yaml <<EOF
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: aws-secrets-manager
  namespace: $NAMESPACE
spec:
  provider:
    aws:
      service: SecretsManager
      region: $REGION
      auth:
        jwt:
          serviceAccountRef:
            name: external-secrets-sa
EOF

kubectl apply -f /tmp/secretstore.yaml

echo "✅ SecretStore created"
echo ""

# Cleanup
rm -f /tmp/external-secrets-policy.json /tmp/secretstore.yaml

echo "✅ Setup complete!"
echo ""
echo "Next steps:"
echo "1. Complete the IRSA setup for EKS (see Step 4 output)"
echo "2. Deploy your Helm chart: helm upgrade --install pg-tileserv ./deploy/pg-tileserv"
echo "3. Verify the external secret: kubectl get externalsecret"
echo "4. Verify the generated secret: kubectl get secret pg-tileserv-db-secret -o yaml"
