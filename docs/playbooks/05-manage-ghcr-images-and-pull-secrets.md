# Manage GHCR images and pull secrets

## Purpose

Build and publish the poll-modem container image to GHCR, then make Kubernetes able to pull it reliably.

## When to use this

Use this playbook when:

- the app runs in Kubernetes
- the image is private on GHCR
- the cluster needs to pull a freshly built tag
- you do not want to rely on a node-local cached `latest` image

## Step 1: Build and push the image

From the app repo:

```bash
make docker-push IMAGE_TAG=<git-sha>
```

For `poll-modem`, commit-tagged images worked well:

- `ghcr.io/wesen/poll-modem:18063a2`
- `ghcr.io/wesen/poll-modem:v0.1.14`

## Step 2: Avoid relying on `latest`

Using `latest` with `IfNotPresent` can hide deployment problems because the node may keep using an old image.

Prefer a pinned tag when you are validating a new build.

## Step 3: Create a pull secret in the app namespace

If GHCR requires auth, create a `docker-registry` secret in the namespace that runs the app.

Example:

```bash
kubectl create secret docker-registry ghcr-pull \
  -n poll-modem \
  --docker-server=ghcr.io \
  --docker-username=wesen \
  --docker-password="$(gh auth token)" \
  --docker-email=none@example.com
```

This secret should stay out of git.

## Step 4: Reference the secret from the deployment

Add the secret name to the pod spec:

```yaml
spec:
  imagePullSecrets:
    - name: ghcr-pull
```

## Step 5: Update the deployment image tag

Pin the image to the pushed tag:

```yaml
image: ghcr.io/wesen/poll-modem:18063a2
```

Then let ArgoCD roll the deployment.

## Step 6: Validate the pull

Check the pod events if the image does not start:

```bash
kubectl describe pod <pod> -n poll-modem
```

Typical pull errors are:

- `401 Unauthorized`
- `ImagePullBackOff`
- `ErrImagePull`

Those usually mean the secret is missing, the token is wrong, or the repo permissions are insufficient.

## Validation checklist

- image is pushed to GHCR
- the namespace contains `ghcr-pull`
- the deployment references `imagePullSecrets`
- the pod starts with the new tag

## Recovery notes

If the new build is broken, roll back the image tag in the deployment. GitOps makes that safe and repeatable.
