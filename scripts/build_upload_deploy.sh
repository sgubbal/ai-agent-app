#!/usr/bin/env bash
set -euo pipefail

ENV=${1:-dev}
REGION=${AWS_REGION:-us-east-1}
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# read exports from bootstrap
ARTIFACT_BUCKET=$(aws cloudformation list-exports --query "Exports[?Name=='ai-agent-${ENV}-ArtifactBucket'].Value" --output text)
APP_BUCKET=$(aws cloudformation list-exports --query "Exports[?Name=='ai-agent-${ENV}-AppBucket'].Value" --output text)
KMS_ARN=$(aws cloudformation list-exports --query "Exports[?Name=='ai-agent-${ENV}-KmsKeyArn'].Value" --output text)
VPC_ID=$(aws cloudformation list-exports --query "Exports[?Name=='ai-agent-${ENV}-VpcId'].Value" --output text || true)
PRIVATE_SUBNETS=$(aws cloudformation list-exports --query "Exports[?Name=='ai-agent-${ENV}-PrivateSubnetIds'].Value" --output text || true)

if [ -z "$ARTIFACT_BUCKET" ]; then
  ARTIFACT_BUCKET="ai-agent-artifacts-${ACCOUNT_ID}-${ENV}"
fi
if [ -z "$APP_BUCKET" ]; then
  APP_BUCKET="ai-agent-app-${ACCOUNT_ID}-${ENV}"
fi

echo "Building lambda..."
cd lambda
rm -f ../lambda.zip
zip -r ../lambda.zip . -x "*.pyc" "__pycache__/*"
cd ..

echo "Uploading lambda to artifact bucket: ${ARTIFACT_BUCKET}"
aws s3 cp lambda.zip s3://${ARTIFACT_BUCKET}/lambda/${ENV}/lambda.zip --region ${REGION}

# upload templates to artifact bucket for master deploy (optional)
aws s3 sync cloudformation/ s3://${ARTIFACT_BUCKET}/cloudformation/ --region ${REGION}

# deploy lambda stack directly (no nested templates required)
aws cloudformation deploy \
  --stack-name ai-agent-app-${ENV} \
  --template-file cloudformation/00-lambda.yml \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides \
    Environment=${ENV} \
    ArtifactBucket=${ARTIFACT_BUCKET} \
    AppBucket=${APP_BUCKET} \
    KmsKeyArn=${KMS_ARN} \
    VpcId=${VPC_ID} \
    PrivateSubnetIds="${PRIVATE_SUBNETS}" \
  --region ${REGION}

# deploy API Gateway (pass Lambda function ARN from stack output)
LAMBDA_ARN=$(aws cloudformation describe-stacks --stack-name ai-agent-app-${ENV} --query "Stacks[0].Outputs[?OutputKey=='LambdaFunctionArn'].OutputValue" --output text)
aws cloudformation deploy \
  --stack-name ai-agent-app-api-${ENV} \
  --template-file cloudformation/01-api-gateway.yml \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides \
    Environment=${ENV} \
    LambdaFunctionArn=${LAMBDA_ARN} \
  --region ${REGION}

echo "App deploy complete."
