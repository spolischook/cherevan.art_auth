# Cherevan.art OAuth Service

A serverless OAuth service for Cherevan.art, built with AWS Lambda and API Gateway.

> Note: This repository is automatically synchronized from the main monorepo using GitHub Actions.

## Features

- Google OAuth2 authentication
- Custom domain support (auth.cherevan.art)
- Serverless architecture using AWS Lambda
- Infrastructure as Code using Terraform

## Contributing

This module is maintained in the main Cherevan.art monorepo. Please submit all pull requests there.

## Deployment

This repository is automatically synchronized from the main monorepo using GitHub Actions and SSH deploy keys. Any changes pushed to the `google-auth` directory in the main repository will be automatically reflected here.

## Prerequisites

- Go 1.21 or later
- AWS CLI configured with appropriate credentials
- Terraform 1.0 or later
- Domain name configured in DigitalOcean

## Local Development

1. Copy `.env.example` to `.env` and fill in the required values:
```bash
cp .env.example .env
# Edit .env with your credentials
```

2. Run locally:
```bash
go run main.go
```

## Deployment

1. Copy `terraform/terraform.tfvars.example` to `terraform/terraform.tfvars` and configure:
```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
# Edit terraform.tfvars with your values
```

2. Deploy using the provided script:
```bash
./deploy.sh
```

## Infrastructure

The service uses:
- AWS Lambda for serverless compute
- API Gateway for HTTP endpoints
- ACM for SSL certificate
- Custom domain mapping

## Security

- All sensitive configuration is stored in environment variables
- SSL/TLS encryption for all endpoints
- OAuth state parameter to prevent CSRF attacks

## License

MIT
