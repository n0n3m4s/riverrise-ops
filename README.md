# riverrise-ops

GitOps manifests for riverrise (Argo CD).

Content lives under `gitops/`. Bootstrap:

```bash
kubectl apply -n argocd -f gitops/bootstrap/root-application-prod.yaml
```
