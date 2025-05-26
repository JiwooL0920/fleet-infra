#!/bin/bash

# Pre-commit hook to prevent cross-environment mistakes
# To install: ln -s ../../scripts/pre-commit-check.sh .git/hooks/pre-commit

# Get current branch
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)

# Get staged files
STAGED_FILES=$(git diff --cached --name-only)

# Check for cross-environment editing
if [[ "$CURRENT_BRANCH" == "develop" ]]; then
    # On develop branch - check if any prod files are being modified
    PROD_FILES=$(echo "$STAGED_FILES" | grep "clusters/stages/prod/" || true)
    if [[ ! -z "$PROD_FILES" ]]; then
        echo "🚨 ERROR: You're on the 'develop' branch but trying to modify production files!"
        echo ""
        echo "Files being modified in production directory:"
        echo "$PROD_FILES"
        echo ""
        echo "Please:"
        echo "1. Switch to 'main' branch to edit production files, OR"
        echo "2. Only edit files in 'clusters/stages/dev/' directory"
        echo ""
        echo "To check your current branch: git branch"
        echo "To switch branches: git checkout main"
        exit 1
    fi
    
    echo "✅ Good! You're on 'develop' branch and modifying dev environment files."
    
elif [[ "$CURRENT_BRANCH" == "main" ]]; then
    # On main branch - warn about direct production changes
    PROD_FILES=$(echo "$STAGED_FILES" | grep "clusters/stages/prod/" || true)
    if [[ ! -z "$PROD_FILES" ]]; then
        echo "⚠️  WARNING: You're committing directly to 'main' branch!"
        echo ""
        echo "Production files being modified:"
        echo "$PROD_FILES"
        echo ""
        echo "Best practice: Test changes in 'develop' branch first, then merge via PR"
        echo ""
        read -p "Are you sure you want to continue? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Commit aborted."
            exit 1
        fi
    fi
    
else
    echo "ℹ️  You're on branch '$CURRENT_BRANCH' - make sure you're on the right branch!"
fi

echo "Environment check passed! ✅" 