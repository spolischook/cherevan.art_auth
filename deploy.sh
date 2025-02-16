#!/bin/bash

# Exit on error
set -e

# Default values
AWS_PROFILE=${AWS_PROFILE:-"default"}
AWS_REGION="eu-central-1"  # Change this to your preferred region

# Configuration
LAMBDA_FUNCTION_NAME="google-auth-lambda"
LAMBDA_ROLE_NAME="google-auth-lambda-role"
ZIP_FILE="function.zip"

# Help message
show_help() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -p, --profile    AWS profile to use (default: 'default')"
    echo "  -h, --help       Show this help message"
    exit 0
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        -p|--profile)
            if [[ "$2" == *=* ]]; then
                AWS_PROFILE="${2#*=}"
                shift
            else
                AWS_PROFILE="$2"
                shift 2
            fi
            ;;
        --profile=*)
            AWS_PROFILE="${key#*=}"
            shift
            ;;
        -h|--help)
            show_help
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            ;;
    esac
done

echo "Using AWS Profile: $AWS_PROFILE"

# AWS CLI with profile
AWS_CMD="aws --profile $AWS_PROFILE"

echo "Building Lambda function..."
GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -o bootstrap

echo "Creating deployment package..."
zip $ZIP_FILE bootstrap

# Check if the Lambda role exists, if not create it
if ! $AWS_CMD iam get-role --role-name $LAMBDA_ROLE_NAME 2>/dev/null; then
    echo "Creating IAM role..."
    $AWS_CMD iam create-role \
        --role-name $LAMBDA_ROLE_NAME \
        --assume-role-policy-document '{
            "Version": "2012-10-17",
            "Statement": [{
                "Action": "sts:AssumeRole",
                "Effect": "Allow",
                "Principal": {
                    "Service": "lambda.amazonaws.com"
                }
            }]
        }'

    # Attach basic Lambda execution policy
    $AWS_CMD iam attach-role-policy \
        --role-name $LAMBDA_ROLE_NAME \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

    # Wait for role to be created
    echo "Waiting for role to be created..."
    sleep 10
fi

# Get the role ARN
ROLE_ARN=$($AWS_CMD iam get-role --role-name $LAMBDA_ROLE_NAME --query 'Role.Arn' --output text)

# Check if Lambda function exists
if $AWS_CMD lambda get-function --function-name $LAMBDA_FUNCTION_NAME 2>/dev/null; then
    echo "Updating existing Lambda function..."
    $AWS_CMD lambda update-function-code \
        --function-name $LAMBDA_FUNCTION_NAME \
        --zip-file fileb://$ZIP_FILE
else
    echo "Creating new Lambda function..."
    $AWS_CMD lambda create-function \
        --function-name $LAMBDA_FUNCTION_NAME \
        --runtime provided.al2 \
        --handler bootstrap \
        --role $ROLE_ARN \
        --zip-file fileb://$ZIP_FILE \
        --environment "Variables={
            GOOGLE_CLIENT_ID=$GOOGLE_CLIENT_ID,
            GOOGLE_CLIENT_SECRET=$GOOGLE_CLIENT_SECRET,
            GOOGLE_REDIRECT_URL=$GOOGLE_REDIRECT_URL
        }"
fi

# Create or update API Gateway
API_NAME="google-auth-api"
if ! API_ID=$($AWS_CMD apigateway get-rest-apis --query "items[?name=='$API_NAME'].id" --output text); then
    echo "Creating API Gateway..."
    API_ID=$($AWS_CMD apigateway create-rest-api \
        --name $API_NAME \
        --query 'id' --output text)

    # Get the root resource ID
    ROOT_RESOURCE_ID=$($AWS_CMD apigateway get-resources \
        --rest-api-id $API_ID \
        --query 'items[?path=='/'].id' \
        --output text)

    # Create resources and methods
    # /auth resource
    AUTH_RESOURCE_ID=$($AWS_CMD apigateway create-resource \
        --rest-api-id $API_ID \
        --parent-id $ROOT_RESOURCE_ID \
        --path-part "auth" \
        --query 'id' --output text)

    # /callback resource
    CALLBACK_RESOURCE_ID=$($AWS_CMD apigateway create-resource \
        --rest-api-id $API_ID \
        --parent-id $ROOT_RESOURCE_ID \
        --path-part "callback" \
        --query 'id' --output text)

    # Create methods and integrations
    for RESOURCE_ID in $AUTH_RESOURCE_ID $CALLBACK_RESOURCE_ID; do
        $AWS_CMD apigateway put-method \
            --rest-api-id $API_ID \
            --resource-id $RESOURCE_ID \
            --http-method GET \
            --authorization-type NONE

        $AWS_CMD apigateway put-integration \
            --rest-api-id $API_ID \
            --resource-id $RESOURCE_ID \
            --http-method GET \
            --type AWS_PROXY \
            --integration-http-method POST \
            --uri arn:aws:apigateway:$AWS_REGION:lambda:path/2015-03-31/functions/arn:aws:lambda:$AWS_REGION:$($AWS_CMD sts get-caller-identity --query 'Account' --output text):function:$LAMBDA_FUNCTION_NAME/invocations
    done

    # Deploy the API
    $AWS_CMD apigateway create-deployment \
        --rest-api-id $API_ID \
        --stage-name prod

    # Add Lambda permission for API Gateway
    $AWS_CMD lambda add-permission \
        --function-name $LAMBDA_FUNCTION_NAME \
        --statement-id apigateway-prod \
        --action lambda:InvokeFunction \
        --principal apigateway.amazonaws.com \
        --source-arn "arn:aws:execute-api:$AWS_REGION:$($AWS_CMD sts get-caller-identity --query 'Account' --output text):$API_ID/*"
fi

# Clean up
echo "Cleaning up..."
rm -f bootstrap $ZIP_FILE

echo "Deployment completed!"
echo "API Gateway endpoint: https://$API_ID.execute-api.$AWS_REGION.amazonaws.com/prod"
echo "Auth endpoint: https://$API_ID.execute-api.$AWS_REGION.amazonaws.com/prod/auth"
echo "Callback endpoint: https://$API_ID.execute-api.$AWS_REGION.amazonaws.com/prod/callback"
