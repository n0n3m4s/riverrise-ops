{{/*
JSON podSelector object for workload name.
*/}}
{{- define "network-policies.podSelectorJSON" -}}
{{- $w := index .root.Values.workloads .name -}}
{{- if not (hasKey $w "selector") -}}
{{- toJson (dict "matchLabels" (dict "app.kubernetes.io/name" .name "app.kubernetes.io/instance" .name)) -}}
{{- else if and (kindIs "map" $w.selector) (eq (len $w.selector) 0) -}}
{{- toJson (dict) -}}
{{- else if or (hasKey $w.selector "matchLabels") (hasKey $w.selector "matchExpressions") -}}
{{- toJson $w.selector -}}
{{- else -}}
{{- toJson (dict "matchLabels" $w.selector) -}}
{{- end -}}
{{- end }}

{{/*
True if workload is an external FQDN peer (CiliumNetworkPolicy only).
*/}}
{{- define "network-policies.isFQDNPeer" -}}
{{- $t := index .root.Values.workloads .ref -}}
{{- if and (hasKey $t "toFQDNs") (not (hasKey $t "ipBlock")) -}}true{{- else -}}false{{- end -}}
{{- end }}

{{/*
JSON NetworkPolicyPeer for ref relative to policyNamespace.
FQDN-only peers are not valid in networking.k8s.io NetworkPolicy — skip via isFQDNPeer.
*/}}
{{- define "network-policies.peerJSON" -}}
{{- $root := .root -}}
{{- $ref := .ref -}}
{{- $policyNamespace := .policyNamespace -}}
{{- if not (hasKey $root.Values.workloads $ref) -}}
{{- fail (printf "network-policies: unknown workload ref %q" $ref) -}}
{{- end -}}
{{- $t := index $root.Values.workloads $ref -}}
{{- if hasKey $t "ipBlock" -}}
{{- toJson (dict "ipBlock" $t.ipBlock) -}}
{{- else if hasKey $t "toFQDNs" -}}
{{- fail (printf "network-policies: workload %q is toFQDNs-only (use CiliumNetworkPolicy path; do not peerJSON it)" $ref) -}}
{{- else if hasKey $t "namespaceSelector" -}}
{{- $p := dict "namespaceSelector" $t.namespaceSelector -}}
{{- if hasKey $t "podSelector" -}}
{{- $_ := set $p "podSelector" $t.podSelector -}}
{{- end -}}
{{- toJson $p -}}
{{- else -}}
{{- $tns := $t.namespace | default "default" -}}
{{- $sel := fromJson (include "network-policies.podSelectorJSON" (dict "root" $root "name" $ref)) -}}
{{- if eq $tns $policyNamespace -}}
{{- toJson (dict "podSelector" $sel) -}}
{{- else -}}
{{- toJson (dict "namespaceSelector" (dict "matchLabels" (dict "kubernetes.io/metadata.name" $tns)) "podSelector" $sel) -}}
{{- end -}}
{{- end -}}
{{- end }}
