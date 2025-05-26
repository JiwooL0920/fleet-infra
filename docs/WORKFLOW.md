# Environment Workflow Guide

## Branch and Environment Mapping

| Environment | Branch | Cluster | Path |
|-------------|--------|---------|------|
| **Development** | `develop` | `services-amer` | `clusters/stages/dev/clusters/services-amer/` |
| **Production** | `main` | `services-amer-prod` | `clusters/stages/prod/clusters/services-amer/` |

## Safety Rules for Environment Isolation

### 🔒 **Development Environment (develop branch)**

#### ✅ **Safe Operations**
- Work only on the `develop` branch
- Make changes only in `clusters/stages/dev/` directory
- Test and iterate freely
- Commit and push changes to `develop` branch

#### ❌ **Forbidden Operations**
- Never edit files in `clusters/stages/prod/` while on `develop` branch
- Never merge directly to `main` without proper review
- Don't modify production configurations from dev branch

#### **Development Workflow**
```bash
# 1. Switch to develop branch
git checkout develop

# 2. Make changes only in dev directory
# Edit files in: clusters/stages/dev/clusters/services-amer/

# 3. Commit and push
git add clusters/stages/dev/
git commit -m "feat: add new application to dev"
git push origin develop

# 4. Flux automatically deploys to dev cluster
```

### 🔒 **Production Environment (main branch)**

#### ✅ **Safe Operations**  
- Only merge tested changes from `develop`
- Review all changes thoroughly
- Use pull requests for all production changes
- Monitor deployments after merge

#### ❌ **Forbidden Operations**
- Never commit directly to `main` branch
- Never edit production configs without testing in dev first
- Don't bypass the develop → main workflow

#### **Production Deployment Workflow**
```bash
# 1. Ensure dev testing is complete
git checkout develop
# Verify all changes work in dev environment

# 2. Create pull request: develop → main
# (Do this on GitHub with proper review)

# 3. After approval and merge
git checkout main
git pull origin main

# 4. Flux automatically deploys to prod cluster
```

## Environment-Specific Commands

### Development Commands
```bash
# Switch to development
git checkout develop
kubectl config use-context kind-services-amer

# Bootstrap dev environment
scripts/flux-bootstrap.sh dev

# Check dev status
flux get all --context kind-services-amer

# Add applications to dev
mkdir -p clusters/stages/dev/clusters/services-amer/applications
# Add your manifests here...
```

### Production Commands
```bash
# Switch to production
git checkout main
kubectl config use-context kind-services-amer-prod

# Bootstrap prod environment (only when ready)
scripts/flux-bootstrap.sh prod

# Check prod status
flux get all --context kind-services-amer-prod
```

## File Organization Rules

### ✅ **Correct File Placement**

#### Development Files
```
clusters/stages/dev/clusters/services-amer/
├── flux-system/          # Flux configuration (branch: develop)
├── applications/         # Your applications
├── namespaces/          # Namespace definitions
└── kustomization.yaml   # Root kustomization
```

#### Production Files
```
clusters/stages/prod/clusters/services-amer/
├── flux-system/          # Flux configuration (branch: main)
├── applications/         # Your applications  
├── namespaces/          # Namespace definitions
└── kustomization.yaml   # Root kustomization
```

### ❌ **Common Mistakes to Avoid**

1. **Cross-Environment Editing**
   ```bash
   # ❌ WRONG: Editing prod files while on develop branch
   git checkout develop
   vim clusters/stages/prod/clusters/services-amer/applications/app.yaml
   ```

2. **Direct Production Changes**
   ```bash
   # ❌ WRONG: Committing directly to main
   git checkout main
   # make changes
   git commit -m "hotfix"
   git push origin main
   ```

3. **Branch Confusion**
   ```bash
   # ❌ WRONG: Not knowing which branch you're on
   vim clusters/stages/dev/clusters/services-amer/app.yaml
   git add .
   git commit -m "dev changes"
   # But you're actually on main branch!
   ```

## Safety Checks

### Pre-commit Checklist
- [ ] Am I on the correct branch? (`git branch`)
- [ ] Am I editing files in the correct directory?
- [ ] Have I tested this in dev before promoting to prod?
- [ ] Are my commit messages descriptive?

### Pre-merge Checklist (develop → main)
- [ ] All dev testing completed successfully
- [ ] Application works as expected in dev environment
- [ ] No breaking changes introduced
- [ ] Documentation updated if needed
- [ ] Pull request reviewed and approved

## Emergency Procedures

### Rollback Development
```bash
git checkout develop
git reset --hard HEAD~1  # Roll back last commit
git push --force-with-lease origin develop
```

### Rollback Production
```bash
# Create hotfix branch from last known good commit
git checkout main
git checkout -b hotfix/rollback-issue
git reset --hard <last-good-commit>
# Create PR: hotfix/rollback-issue → main
```

## Monitoring Your Environment

### Check Which Environment You're Working On
```bash
# Check current branch
git branch

# Check kubectl context  
kubectl config current-context

# Check Flux status
flux get all
```

### Verify Changes Are Applied to Correct Environment
```bash
# Development
kubectl get pods --context kind-services-amer

# Production  
kubectl get pods --context kind-services-amer-prod
```

This workflow ensures that development changes stay in development and only tested, approved changes make it to production! 