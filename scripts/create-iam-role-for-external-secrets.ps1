# Script to create IAM role for External Secrets service account
# Run this once per cluster to set up IRSA (IAM Roles for Service Accounts)

param(
    [Parameter(Mandatory=$true)]
    [string]$ClusterName,
    
    [Parameter(Mandatory=$false)]
    [string]$Region = "us-east-1",
    
    [Parameter(Mandatory=$false)]
    [string]$Namespace = "default"
)

$ErrorActionPreference = "Stop"

Write-Host "🔐 Creating IAM Role for External Secrets Service Account" -ForegroundColor Cyan
Write-Host ""

# Get AWS Account ID
$AccountId = (aws sts get-caller-identity --query Account --output text)
Write-Host "Account ID: $AccountId" -ForegroundColor Gray
Write-Host "Cluster: $ClusterName" -ForegroundColor Gray
Write-Host "Region: $Region" -ForegroundColor Gray
Write-Host ""

# Create IAM policy if it doesn't exist
$PolicyName = "ExternalSecretsPolicy-pg-tileserv"
$policyArn = "arn:aws:iam::${AccountId}:policy/${PolicyName}"

Write-Host "Checking IAM policy..." -ForegroundColor Yellow
$policyExists = aws iam get-policy --policy-arn $policyArn 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "Creating IAM policy..." -ForegroundColor Yellow
    
    $policyDocument = @{
        Version = "2012-10-17"
        Statement = @(
            @{
                Effect = "Allow"
                Action = @(
                    "secretsmanager:GetSecretValue",
                    "secretsmanager:DescribeSecret"
                )
                Resource = "arn:aws:secretsmanager:${Region}:*:secret:pg-tileserv/*"
            }
        )
    } | ConvertTo-Json -Depth 10

    $policyDocument | Out-File -FilePath ".\external-secrets-policy.json" -Encoding utf8
    
    aws iam create-policy `
        --policy-name $PolicyName `
        --policy-document file://external-secrets-policy.json `
        --description "Allows External Secrets Operator to read pg-tileserv secrets from AWS Secrets Manager"
    
    Remove-Item ".\external-secrets-policy.json" -ErrorAction SilentlyContinue
    Write-Host "✅ Policy created" -ForegroundColor Green
} else {
    Write-Host "✅ Policy already exists" -ForegroundColor Green
}
Write-Host ""

# Create IRSA using eksctl
Write-Host "Creating IAM Role for Service Account (IRSA)..." -ForegroundColor Yellow
Write-Host "This will create an IAM role and link it to the Kubernetes service account" -ForegroundColor Gray
Write-Host ""

try {
    eksctl create iamserviceaccount `
        --name external-secrets-sa `
        --namespace $Namespace `
        --cluster $ClusterName `
        --region $Region `
        --attach-policy-arn $policyArn `
        --approve `
        --override-existing-serviceaccounts
    
    Write-Host "✅ Service account and IAM role created" -ForegroundColor Green
} catch {
    Write-Host "⚠️  Failed to create service account" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
Write-Host ""

# Get the role ARN
Write-Host "Retrieving IAM Role ARN..." -ForegroundColor Yellow
Start-Sleep -Seconds 3

$roleArn = kubectl get serviceaccount external-secrets-sa -n $Namespace -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}' 2>$null

if ($roleArn) {
    Write-Host "✅ Role ARN: $roleArn" -ForegroundColor Green
    Write-Host ""
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
    Write-Host "Next Steps:" -ForegroundColor White
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Add this to your values.yaml:" -ForegroundColor Yellow
    Write-Host "externalSecretsIamRoleArn: `"$roleArn`"" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Or set it during deployment:" -ForegroundColor Yellow
    Write-Host "helm upgrade --install pg-tileserv ./deploy/pg-tileserv \" -ForegroundColor Cyan
    Write-Host "  --set externalSecretsIamRoleArn=`"$roleArn`"" -ForegroundColor Cyan
} else {
    Write-Host "⚠️  Could not retrieve role ARN automatically" -ForegroundColor Yellow
    Write-Host "Check the service account annotation manually:" -ForegroundColor Gray
    Write-Host "kubectl get serviceaccount external-secrets-sa -n $Namespace -o yaml" -ForegroundColor Cyan
}
Write-Host ""
