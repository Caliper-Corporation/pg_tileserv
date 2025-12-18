# PowerShell script to complete External Secrets Operator setup
# Prerequisites: AWS secret created, External Secrets Operator installed

param(
    [Parameter(Mandatory = $true)]
    [string]$ClusterName,
    
    [Parameter(Mandatory = $false)]
    [string]$Region = "us-east-1",
    
    [Parameter(Mandatory = $false)]
    [string]$Namespace = "default",
    
    [Parameter(Mandatory = $false)]
    [string]$SecretName = "pg-tileserv/database-url"
)

$ErrorActionPreference = "Stop"

Write-Host "🔐 Completing External Secrets Operator Setup" -ForegroundColor Cyan
Write-Host ""

# Get AWS Account ID
Write-Host "📋 Getting AWS Account ID..." -ForegroundColor Yellow
$AccountId = (aws sts get-caller-identity --query Account --output text)
Write-Host "   Account ID: $AccountId" -ForegroundColor Gray
Write-Host ""

# Step 1: Create IAM Policy
Write-Host "Step 1: Creating IAM Policy..." -ForegroundColor Yellow
$policyDocument = @{
    Version   = "2012-10-17"
    Statement = @(
        @{
            Effect   = "Allow"
            Action   = @(
                "secretsmanager:GetSecretValue",
                "secretsmanager:DescribeSecret"
            )
            Resource = "arn:aws:secretsmanager:${Region}:*:secret:${SecretName}*"
        }
    )
} | ConvertTo-Json -Depth 10

$policyDocument | Out-File -FilePath ".\external-secrets-policy.json" -Encoding utf8

$PolicyName = "ExternalSecretsPolicy-pg-tileserv"

try {
    Write-Host "   Creating policy: $PolicyName" -ForegroundColor Gray
    $policyArn = aws iam create-policy `
        --policy-name $PolicyName `
        --policy-document file://external-secrets-policy.json `
        --query 'Policy.Arn' `
        --output text 2>&1
    
    if ($LASTEXITCODE -ne 0) {
        if ($policyArn -like "*EntityAlreadyExists*") {
            Write-Host "   Policy already exists, using existing policy" -ForegroundColor Gray
            $policyArn = "arn:aws:iam::${AccountId}:policy/${PolicyName}"
        }
        else {
            throw "Failed to create policy: $policyArn"
        }
    }
    Write-Host "   ✅ Policy ready: $policyArn" -ForegroundColor Green
}
catch {
    Write-Host "   ⚠️  Policy creation failed, attempting to use existing..." -ForegroundColor Yellow
    $policyArn = "arn:aws:iam::${AccountId}:policy/${PolicyName}"
}
Write-Host ""

# Step 2: Create IAM Service Account using eksctl
Write-Host "Step 2: Creating IAM Service Account (IRSA)..." -ForegroundColor Yellow
Write-Host "   This will create an IAM role and service account for External Secrets" -ForegroundColor Gray

try {
    eksctl create iamserviceaccount `
        --name external-secrets-sa `
        --namespace $Namespace `
        --cluster $ClusterName `
        --region $Region `
        --attach-policy-arn $policyArn `
        --approve `
        --override-existing-serviceaccounts
    
    Write-Host "   ✅ Service account created" -ForegroundColor Green
}
catch {
    Write-Host "   ⚠️  Service account might already exist or eksctl failed" -ForegroundColor Yellow
    Write-Host "   Continuing anyway..." -ForegroundColor Gray
}
Write-Host ""

# Step 3: Create SecretStore
Write-Host "Step 3: Creating SecretStore resource..." -ForegroundColor Yellow

$secretStoreYaml = @"
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: aws-secrets-manager
  namespace: $Namespace
spec:
  provider:
    aws:
      service: SecretsManager
      region: $Region
      auth:
        jwt:
          serviceAccountRef:
            name: external-secrets-sa
"@

$secretStoreYaml | Out-File -FilePath ".\secretstore.yaml" -Encoding utf8

Write-Host "   Applying SecretStore..." -ForegroundColor Gray
kubectl apply -f .\secretstore.yaml

Write-Host "   ✅ SecretStore created" -ForegroundColor Green
Write-Host ""

# Wait for SecretStore to be ready
Write-Host "⏳ Waiting for SecretStore to be ready..." -ForegroundColor Yellow
Start-Sleep -Seconds 5

$secretStoreStatus = kubectl get secretstore aws-secrets-manager -n $Namespace -o json 2>$null | ConvertFrom-Json
if ($secretStoreStatus) {
    Write-Host "   ✅ SecretStore is ready" -ForegroundColor Green
}
else {
    Write-Host "   ⚠️  Could not verify SecretStore status" -ForegroundColor Yellow
}
Write-Host ""

# Step 4: Deploy the Helm chart
Write-Host "Step 4: Deploying pg-tileserv Helm chart..." -ForegroundColor Yellow

try {
    helm upgrade --install pg-tileserv .\deploy\pg-tileserv `
        --namespace $Namespace `
        --create-namespace `
        --wait `
        --timeout 5m
    
    Write-Host "   ✅ Helm chart deployed" -ForegroundColor Green
}
catch {
    Write-Host "   ⚠️  Helm deployment failed or timed out" -ForegroundColor Yellow
    Write-Host "   Check the status manually: kubectl get pods -n $Namespace" -ForegroundColor Gray
}
Write-Host ""

# Step 5: Verify the setup
Write-Host "Step 5: Verifying the setup..." -ForegroundColor Yellow
Write-Host ""

# Check ExternalSecret
Write-Host "   Checking ExternalSecret:" -ForegroundColor Gray
kubectl get externalsecret -n $Namespace

Start-Sleep -Seconds 3

# Check if secret was created
Write-Host "`n   Checking generated Secret:" -ForegroundColor Gray
$secret = kubectl get secret pg-tileserv-db-secret -n $Namespace -o json 2>$null | ConvertFrom-Json

if ($secret) {
    Write-Host "   ✅ Secret 'pg-tileserv-db-secret' exists" -ForegroundColor Green
    
    # Check if it has the DATABASE_URL key
    if ($secret.data.DATABASE_URL) {
        Write-Host "   ✅ SECRET has DATABASE_URL key" -ForegroundColor Green
    }
    else {
        Write-Host "   ❌ Secret missing DATABASE_URL key" -ForegroundColor Red
    }
}
else {
    Write-Host "   ❌ Secret 'pg-tileserv-db-secret' not found" -ForegroundColor Red
    Write-Host "`n   Checking ExternalSecret status:" -ForegroundColor Yellow
    kubectl describe externalsecret pg-tileserv-db-secret -n $Namespace
}

Write-Host "`n   Checking pods:" -ForegroundColor Gray
kubectl get pods -n $Namespace -l app=pg-tileserv

Write-Host ""

# Cleanup temporary files
Write-Host "🧹 Cleaning up temporary files..." -ForegroundColor Yellow
Remove-Item -Path ".\external-secrets-policy.json" -ErrorAction SilentlyContinue
Remove-Item -Path ".\secretstore.yaml" -ErrorAction SilentlyContinue
Write-Host ""

# Summary
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host "✅ Setup Complete!" -ForegroundColor Green
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host ""
Write-Host "What was configured:" -ForegroundColor White
Write-Host "  ✅ IAM Policy: ExternalSecretsPolicy-pg-tileserv" -ForegroundColor Gray
Write-Host "  ✅ IAM Role for Service Account (IRSA)" -ForegroundColor Gray
Write-Host "  ✅ Kubernetes SecretStore: aws-secrets-manager" -ForegroundColor Gray
Write-Host "  ✅ ExternalSecret: pg-tileserv-db-secret" -ForegroundColor Gray
Write-Host "  ✅ Helm deployment: pg-tileserv" -ForegroundColor Gray
Write-Host ""
Write-Host "Useful commands:" -ForegroundColor White
Write-Host "  # Check ExternalSecret status" -ForegroundColor Gray
Write-Host "  kubectl describe externalsecret pg-tileserv-db-secret -n $Namespace" -ForegroundColor Cyan
Write-Host ""
Write-Host "  # View secret (shows encrypted data)" -ForegroundColor Gray
Write-Host "  kubectl get secret pg-tileserv-db-secret -n $Namespace -o yaml" -ForegroundColor Cyan
Write-Host ""
Write-Host "  # Check pod logs" -ForegroundColor Gray
Write-Host "  kubectl logs -l app=pg-tileserv -n $Namespace" -ForegroundColor Cyan
Write-Host ""
Write-Host "  # Check external secrets operator logs" -ForegroundColor Gray
Write-Host "  kubectl logs -n external-secrets-system -l app.kubernetes.io/name=external-secrets" -ForegroundColor Cyan
Write-Host ""
Write-Host "To rotate credentials:" -ForegroundColor White
Write-Host "  1. Update secret in AWS: aws secretsmanager update-secret ..." -ForegroundColor Gray
Write-Host "  2. Wait up to 1 hour (auto-refresh) or delete the k8s secret to force refresh" -ForegroundColor Gray
Write-Host "  3. Restart pods: kubectl rollout restart deployment pg-tileserv-deployment -n $Namespace" -ForegroundColor Gray
Write-Host ""
