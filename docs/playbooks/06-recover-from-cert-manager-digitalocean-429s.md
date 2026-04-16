# Recover from cert-manager DigitalOcean 429s

## Purpose

Reduce or eliminate cert-manager DNS01 noise when DigitalOcean rate limits the DNS API.

This was the main issue when `poll-modem` tried to request its own certificate on top of the existing wildcard cert.

## When to use this

Use this playbook when you see:

- cert-manager repeatedly trying to create DNS01 challenges
- DigitalOcean API 429 errors
- old Order/Challenge resources that keep coming back
- a service requesting a certificate that is unnecessary because a wildcard cert already exists

## Preferred fix: reuse the wildcard certificate

If `*.crib.scapegoat.dev` already has a valid secret, reuse it instead of asking cert-manager for a new per-app cert.

For `poll-modem`, the app was moved to a Traefik `IngressRoute` and pointed at the shared `crib-scapegoat-dev-tls` secret.

That eliminated the extra DNS01 churn.

## Step 1: Stop ingress-shim from creating more certs

If you are using a standard Kubernetes Ingress with the cert-manager annotation, remove the annotation from the ingress path.

Switching to Traefik `IngressRoute` avoids the ingress-shim loop entirely.

## Step 2: Reuse the wildcard TLS secret

Copy or reference the existing wildcard secret into the app namespace if needed.

Then point the route at that secret.

```yaml
tls:
  secretName: crib-scapegoat-dev-tls
```

## Step 3: Clean up stale cert-manager objects

Delete the old resources for the app if they exist:

```bash
kubectl get certificate,order,challenge -n poll-modem
kubectl delete certificate <name> -n poll-modem
kubectl delete order <name> -n poll-modem
kubectl delete challenge <name> -n poll-modem
```

If a finalizer gets stuck, remove it carefully after confirming the object is no longer needed.

## Step 4: Throttle cert-manager if the cluster is noisy

If you still need cert-manager for other services, reduce concurrent challenge processing.

The live knob that helped in crib was:

```text
--max-concurrent-challenges=1
```

This lowers the chance of hammering the DigitalOcean DNS API.

## Step 5: Validate the recovery

You want:

- no new poll-modem `Certificate` objects
- no new DNS01 `Order`/`Challenge` spam
- `curl -kI https://modem.crib.scapegoat.dev/` returns `200`
- the app still serves through Traefik

## Validation checklist

- no extra cert-manager resources for the app
- no DigitalOcean 429 loop
- existing wildcard cert still serves the app
- the route remains healthy

## Recovery notes

If the wildcard cert is the right answer, prefer that over a per-app DNS01 certificate. It is simpler, faster, and much less noisy.
