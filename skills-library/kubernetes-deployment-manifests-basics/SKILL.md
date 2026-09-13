---
name: kubernetes-deployment-manifests-basics
description: "Use this skill for writing and reviewing core Kubernetes manifests: Deployment, Service, ConfigMap and Secret, readiness and liveness probes, resource requests and limits, and rollout plus rollback control. Trigger when a service needs its first manifests, when pods restart or never become ready, when a rollout stalls, or when a release must be rolled back."
---

# Kubernetes Deployment Manifests Basics

Use this skill for infrastructure tasks covering the core workload objects of a Kubernetes service. The guidance is cluster-neutral and assumes no specific managed platform.

## Workflow

1. Identify what the workload is: stateless replicas, the port it serves, its configuration inputs, and its startup time.
2. Write the Deployment with an explicit image tag or digest, a replica count, and labels that the Service selector matches exactly.
3. Split configuration from code: non-sensitive values in a ConfigMap, sensitive values in a Secret, both referenced by name rather than inlined into the pod spec.
4. Define readiness and liveness probes with distinct meanings: readiness gates traffic, liveness restarts a wedged process. Give slow starters a startup probe instead of a long liveness delay.
5. Set resource requests from observed steady-state usage and limits from observed peaks; requests drive scheduling, limits drive throttling and termination.
6. Choose the rollout strategy and surge or unavailable budget consciously, and confirm the workload tolerates two versions running at once.
7. Apply to a non-production namespace, watch the rollout to completion, and exercise the rollback path before relying on it.
8. Report the objects created, the probe endpoints, the resource values with their justification, and the rollback command.

## Focus Checklist

- Service selector, pod template labels, and target port are verified together; a mismatch produces a Service with no endpoints and no error.
- Probe endpoints are cheap and dependency-aware: readiness may check dependencies, liveness must not, or a slow dependency will restart healthy pods.
- Every container sets requests; missing requests leave the pod in a best-effort class and first in line for eviction.
- Secret values are supplied by the cluster's secret mechanism, not committed as plain literals in the repository.
- A config change that must restart pods triggers a new pod template revision rather than relying on a silent in-place update.
- Replica count above one plus a disruption budget is required before a node drain can be considered safe.
- Rollout history is kept deep enough that a rollback to the previous known-good revision is actually possible.

## Guardrails

- Do not apply manifests against a production cluster or context without explicit confirmation; verify the active context first.
- Do not delete workloads, namespaces, or persistent volume claims without explicit confirmation.
- Do not commit decoded secret values, kubeconfig files, or service account tokens.
- Do not assume a particular managed control plane, ingress controller, or cloud load balancer; keep manifests portable.
- If no cluster is reachable, validate manifests offline, say so, and give the exact apply and rollout commands to run.
