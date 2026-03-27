# Crossplane Compositions

This directory contains reusable Crossplane Compositions for common infrastructure patterns.

## Directory Structure

```
compositions/
├── README.md                      # This file
├── functions/                     # Composition functions
│   └── patch-and-transform.yaml   # P&T function for compositions
├── s3-bucket/                     # S3 bucket compositions
│   ├── composition.yaml           # S3 bucket with lifecycle policies
│   └── definition.yaml            # XRD for XBucket
├── iam-role/                      # IAM role compositions
│   ├── composition.yaml           # IAM role with policies
│   └── definition.yaml            # XRD for XRole
└── network/                       # Network compositions
    ├── composition.yaml           # VPC with subnets
    └── definition.yaml            # XRD for XNetwork
```

## Available Compositions

### 1. S3 Bucket (XBucket)

Creates an S3 bucket with:
- Versioning configuration
- Lifecycle policies
- Encryption settings
- Public access blocking
- Tagging

**Usage:**
```yaml
apiVersion: storage.platform.io/v1alpha1
kind: XBucket
metadata:
  name: my-app-bucket
spec:
  parameters:
    region: us-east-1
    versioning: true
    lifecycleDays: 30
    encryption: AES256
    tags:
      Environment: dev
      Team: platform
```

### 2. IAM Role (XRole)

Creates an IAM role with:
- Trust policy configuration
- Attached managed policies
- Inline policies
- Session duration settings

**Usage:**
```yaml
apiVersion: iam.platform.io/v1alpha1
kind: XRole
metadata:
  name: my-app-role
spec:
  parameters:
    trustService: ec2.amazonaws.com
    managedPolicies:
      - arn:aws:iam::aws:policy/ReadOnlyAccess
    inlinePolicy: |
      {
        "Version": "2012-10-17",
        "Statement": [{
          "Effect": "Allow",
          "Action": "s3:*",
          "Resource": "*"
        }]
      }
```

### 3. Network (XNetwork)

Creates a VPC with:
- Public and private subnets
- Internet gateway
- NAT gateway (optional)
- Route tables
- Security groups

**Usage:**
```yaml
apiVersion: network.platform.io/v1alpha1
kind: XNetwork
metadata:
  name: my-app-network
spec:
  parameters:
    region: us-east-1
    vpcCidr: 10.0.0.0/16
    availabilityZones: 2
    natGateways: true
    tags:
      Environment: dev
```

## Creating New Compositions

### 1. Define the XRD (Composite Resource Definition)

```yaml
apiVersion: apiextensions.crossplane.io/v1
kind: CompositeResourceDefinition
metadata:
  name: xbuckets.storage.platform.io
spec:
  group: storage.platform.io
  names:
    kind: XBucket
    plural: xbuckets
  versions:
    - name: v1alpha1
      served: true
      referenceable: true
      schema:
        openAPIV3Schema:
          type: object
          properties:
            spec:
              type: object
              properties:
                parameters:
                  type: object
                  properties:
                    region:
                      type: string
                    versioning:
                      type: boolean
                  required:
                    - region
```

### 2. Create the Composition

```yaml
apiVersion: apiextensions.crossplane.io/v1
kind: Composition
metadata:
  name: xbuckets.aws.platform.io
spec:
  compositeTypeRef:
    apiVersion: storage.platform.io/v1alpha1
    kind: XBucket
  mode: Pipeline
  pipeline:
    - step: create-s3-bucket
      functionRef:
        name: function-patch-and-transform
      input:
        apiVersion: pt.fn.crossplane.io/v1beta1
        kind: Resources
        resources:
          - name: s3-bucket
            base:
              apiVersion: s3.aws.upbound.io/v1beta1
              kind: Bucket
            patches:
              - type: FromCompositeFieldPath
                fromFieldPath: spec.parameters.region
                toFieldPath: spec.forProvider.region
```

### 3. Apply the Resources

```bash
# Apply the XRD
kubectl apply -f definition.yaml

# Apply the Composition
kubectl apply -f composition.yaml

# Create an instance
kubectl apply -f example-bucket.yaml
```

## Best Practices

1. **Naming Conventions**
   - Use descriptive names for XRDs (XBucket, XDatabase, XNetwork)
   - Include the provider in composition names (xbuckets.aws.platform.io)

2. **Parameter Design**
   - Keep parameters simple and intuitive
   - Provide sensible defaults
   - Use validation in XRD schemas

3. **Composition Structure**
   - Use Pipeline mode for better modularity
   - Leverage composition functions for complex logic
   - Keep compositions focused on single concerns

4. **Testing**
   - Test compositions in development first
   - Use dry-run to preview changes
   - Validate with different parameter combinations

5. **Documentation**
   - Document all parameters
   - Provide usage examples
   - Include troubleshooting guides

## Composition Functions

### Patch and Transform Function

The most commonly used function for:
- Patching values from composite to resources
- Transforming data between fields
- Conditional resource creation

**Installation:**
```yaml
apiVersion: pkg.crossplane.io/v1
kind: Function
metadata:
  name: function-patch-and-transform
spec:
  package: xpkg.upbound.io/crossplane-contrib/function-patch-and-transform:v0.4.0
```

### Auto-Ready Function

Automatically marks composite resources as ready:

```yaml
apiVersion: pkg.crossplane.io/v1
kind: Function
metadata:
  name: function-auto-ready
spec:
  package: xpkg.upbound.io/crossplane-contrib/function-auto-ready:v0.2.1
```

## Environment-Specific Configurations

Use patches to apply environment-specific settings:

```yaml
patches:
  - type: FromCompositeFieldPath
    fromFieldPath: metadata.labels[environment]
    toFieldPath: spec.forProvider.tags[Environment]
  - type: FromCompositeFieldPath
    fromFieldPath: metadata.labels[environment]
    toFieldPath: spec.providerConfigRef.name
    transforms:
      - type: map
        map:
          dev: default          # LocalStack
          prod: aws-production  # Real AWS
```

## Troubleshooting

### Common Issues

1. **Composition not working**
   ```bash
   # Check composition status
   kubectl describe composition xbuckets.aws.platform.io

   # Check XRD
   kubectl get xrd xbuckets.storage.platform.io
   ```

2. **Resources not creating**
   ```bash
   # Check composite resource
   kubectl describe xbucket my-app-bucket

   # Check composed resources
   kubectl get managed -l crossplane.io/composite=my-app-bucket
   ```

3. **Function errors**
   ```bash
   # Check function logs
   kubectl logs -n crossplane-system deployment/function-patch-and-transform
   ```

## References

- [Composition Documentation](https://docs.crossplane.io/latest/concepts/compositions/)
- [Composition Functions](https://docs.crossplane.io/latest/concepts/composition-functions/)
- [Patch and Transform Reference](https://github.com/crossplane-contrib/function-patch-and-transform)
