# Add a new app via ArgoCD

## Purpose

Deploy a new service into crib-k3s using the repo-managed GitOps flow.

The goal is to make the app fully declarative:

- namespace
- deployment
- service
- ingress or ingress route
- secret references
- ArgoCD Application

## When to use this

Use this playbook when you want to add a new app or migrate an existing service into the crib cluster.

## Core pattern

1. Create a `gitops/kustomize/<app>/` directory with the Kubernetes resources.
2. Add a `gitops/applications/<app>.yaml` ArgoCD Application.
3. Push to `main`.
4. Let ArgoCD reconcile the app.
5. Validate the route, TLS, and health checks.

## Relevant example

The `poll-modem` app in this repo follows this exact pattern.

## Step 1: Create the app namespace and resources

Start with a kustomize overlay containing the app’s base resources.

Typical files:

- `namespace.yaml`
- `deployment.yaml`
- `service.yaml`
- `pvc.yaml` if the app has state
- `ingress.yaml` or `ingressroute.yaml`
- `servicemonitor.yaml` if the app should be scraped

## Step 2: Choose how to expose the app

### Option A: Standard Kubernetes Ingress

Use this if you are fine with cert-manager handling the TLS path on the ingress.

This works well for simple apps but can trigger ingress-shim and certificate churn if you are not careful.

### Option B: Traefik IngressRoute

Use this if you want to:

- avoid cert-manager ingress-shim
- reuse an existing wildcard TLS secret
- keep the route controlled by Traefik directly

That was the path used for `poll-modem`.

Example shape:

```yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
spec:
  entryPoints:
    - websecure
  routes:
    - kind: Rule
      match: Host(`modem.crib.scapegoat.dev`)
      services:
        - name: poll-modem
          port: 80
  tls:
    secretName: crib-scapegoat-dev-tls
```

## Step 3: Keep secrets out of git

Anything sensitive should be created manually or via Vault/VSO, not committed.

Examples:

- app credentials
- API tokens
- image pull secrets
- TLS bootstrap secrets if they are not meant to be public

For `poll-modem`, the modem credentials secret is manual:

```bash
kubectl create secret generic modem-credentials \
  --namespace poll-modem \
  --from-literal=username=admin \
  --from-literal=password='<modem-password>'
```

## Step 4: Add the ArgoCD Application

Create the application in `gitops/applications/<app>.yaml`.

Recommended sync settings:

- `automated.prune: true`
- `automated.selfHeal: true`
- `CreateNamespace=true`
- `ServerSideApply=true`

Example:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: poll-modem
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/wesen/crib-k3s.git
    targetRevision: main
    path: gitops/kustomize/poll-modem
  destination:
    server: https://kubernetes.default.svc
    namespace: poll-modem
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
```

## Step 5: Push and refresh

After pushing the repo changes, ArgoCD should sync automatically.

If you need a hard refresh, use kubectl against the Application resource:

```bash
kubectl annotate application poll-modem -n argocd argocd.argoproj.io/refresh=hard --overwrite
```

## Step 6: Validate the app

Check the app state:

```bash
kubectl get application poll-modem -n argocd -o wide
kubectl get pods -n poll-modem
kubectl get svc -n poll-modem
kubectl get ingressroute -n poll-modem
```

Then check the route:

```bash
curl -skI https://modem.crib.scapegoat.dev/
```

## Validation checklist

- ArgoCD app is `Synced`
- App health is `Healthy`
- pod is running
- service has the expected selector and port
- ingress route or ingress resolves correctly
- TLS terminates with the wildcard secret

## Common failure modes

### App stays OutOfSync

Usually means one of:

- repo path is wrong
- manifest has invalid YAML
- the cluster-side resource was edited manually and ArgoCD is correcting it

### Pod is healthy but route does not work

Check:

- service port names
- ingress route backend port
- DNS name
- TLS secret name
- Traefik controller status

### Secret not found

Make sure the manual secret exists in the app namespace, not just in the cluster.

## Recovery notes

If the app is noisy because of cert-manager or ingress-shim, consider reusing an existing wildcard TLS secret and switching to Traefik IngressRoute rather than fighting per-app certificate issuance.
