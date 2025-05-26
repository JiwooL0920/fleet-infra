#!/bin/bash

# Check if environment parameter is provided
if [ -z "$1" ]; then
    echo "Usage: $0 <environment>"
    echo "  environment: 'dev' or 'prod'"
    echo ""
    echo "Examples:"
    echo "  $0 dev   # Bootstrap dev environment (develop branch)"
    echo "  $0 prod  # Bootstrap prod environment (main branch)"
    exit 1
fi

ENVIRONMENT=$1

# Set branch and path based on environment
case $ENVIRONMENT in
    "dev")
        BRANCH="develop"
        PATH="./clusters/stages/dev/clusters/services-amer"
        ;;
    "prod")
        BRANCH="main"
        PATH="./clusters/stages/prod/clusters/services-amer"
        ;;
    *)
        echo "Error: Invalid environment '$ENVIRONMENT'"
        echo "Valid environments: 'dev' or 'prod'"
        exit 1
        ;;
esac

echo "Bootstrapping $ENVIRONMENT environment..."
echo "Branch: $BRANCH"
echo "Path: $PATH"
echo ""

flux bootstrap github \
  --owner=JiwooL0920 \
  --repository=fleet-infra \
  --branch=$BRANCH \
  --path=$PATH \
  --personal
