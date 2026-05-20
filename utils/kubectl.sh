#!/bin/bash
# Kubernetes utility functions (all prefixed kubectl_).

_kubectl_require() {
    if ! command -v kubectl >/dev/null 2>&1; then
        echo "Error: kubectl is not installed or not in PATH" >&2
        return 1
    fi
}

_kubectl_require_namespace() {
    local namespace="$1"
    local op="$2"
    if [[ -z "$namespace" ]]; then
        echo "Error: -n <namespace> is required for ${op}" >&2
        return 1
    fi
}

_kubectl_require_value() {
    local value="$1"
    local flag="$2"
    if [[ -z "$value" ]]; then
        echo "Error: ${flag} requires a value" >&2
        return 1
    fi
}

_kubectl_flag_value() {
    if [[ -z "${2:-}" || "$2" == -* ]]; then
        echo "Error: $1 requires a value" >&2
        return 1
    fi
}

_kubectl_confirm_yes() {
    local count="$1"
    local reply
    echo
    printf "Type 'yes' to delete %s pod(s), anything else to abort: " "$count"
    read -r reply
    if [[ "$reply" != "yes" ]]; then
        echo "Aborted."
        return 1
    fi
}

_kubectl_collect_pods() {
    local namespace="$1"
    local awk_filter="$2"
    kubectl get pods -n "$namespace" --no-headers 2>/dev/null | awk "$awk_filter {print \$1, \$3}"
}

_kubectl_delete_pods() {
    local namespace="$1"
    local description="$2"
    local awk_filter="$3"
    local skip_confirm="${4:-0}"
    shift 4
    local extra_delete_args=("$@")

    _kubectl_require || return 1
    _kubectl_require_namespace "$namespace" "$description" || return 1

    local pods=()
    local statuses=()
    local line pod status

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        pod="${line%% *}"
        status="${line#* }"
        pods+=("$pod")
        statuses+=("$status")
    done < <(_kubectl_collect_pods "$namespace" "$awk_filter")

    if [[ ${#pods[@]} -eq 0 ]]; then
        echo "No pods to delete (${description}, namespace: ${namespace})."
        return 0
    fi

    echo "Pods matching: ${description} (namespace: ${namespace})"
    printf "%-40s %s\n" "POD" "STATUS"
    printf "%-40s %s\n" "----" "------"
    local i
    for i in "${!pods[@]}"; do
        printf "%-40s %s\n" "${pods[$i]}" "${statuses[$i]}"
    done

    if [[ "$skip_confirm" != "1" ]]; then
        _kubectl_confirm_yes "${#pods[@]}" || return 1
    fi

    kubectl delete pod -n "$namespace" "${pods[@]}" "${extra_delete_args[@]}"
}

kubectl_delete_completed_pods_help() {
    cat <<'EOF'
Usage: kubectl_delete_completed_pods -n <namespace>

Delete pods in Completed status. Namespace is required.
Shows matching pods and asks for confirmation (type 'yes' to proceed).
EOF
}

kubectl_delete_completed_pods() {
    local namespace=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help) kubectl_delete_completed_pods_help; return 0 ;;
            -n|--namespace)
                _kubectl_flag_value "$1" "${2:-}" || return 1
                namespace="$2"
                shift 2
                ;;
            *)
                echo "Unknown argument: $1" >&2
                kubectl_delete_completed_pods_help >&2
                return 1
                ;;
        esac
    done

    _kubectl_delete_pods "$namespace" "completed pods" '$3=="Completed"'
}

kubectl_delete_evicted_pods_help() {
    cat <<'EOF'
Usage: kubectl_delete_evicted_pods -n <namespace>

Delete pods in Evicted status. Namespace is required.
Shows matching pods and asks for confirmation (type 'yes' to proceed).
EOF
}

kubectl_delete_evicted_pods() {
    local namespace=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help) kubectl_delete_evicted_pods_help; return 0 ;;
            -n|--namespace)
                _kubectl_flag_value "$1" "${2:-}" || return 1
                namespace="$2"
                shift 2
                ;;
            *)
                echo "Unknown argument: $1" >&2
                kubectl_delete_evicted_pods_help >&2
                return 1
                ;;
        esac
    done

    _kubectl_delete_pods "$namespace" "evicted pods" '$3=="Evicted"'
}

kubectl_delete_error_pods_help() {
    cat <<'EOF'
Usage: kubectl_delete_error_pods -n <namespace>

Delete pods in error states (Error, CrashLoopBackOff, ImagePullBackOff, etc.).
Namespace is required. Shows matching pods and asks for confirmation (type 'yes').
EOF
}

kubectl_delete_error_pods() {
    local namespace=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help) kubectl_delete_error_pods_help; return 0 ;;
            -n|--namespace)
                _kubectl_flag_value "$1" "${2:-}" || return 1
                namespace="$2"
                shift 2
                ;;
            *)
                echo "Unknown argument: $1" >&2
                kubectl_delete_error_pods_help >&2
                return 1
                ;;
        esac
    done

    _kubectl_delete_pods "$namespace" "error pods" \
        '$3 ~ /Error|CrashLoopBackOff|ImagePullBackOff|ErrImagePull|CreateContainerConfigError|RunContainerError|ContainerStatusUnknown/'
}

kubectl_delete_stuck_terminating_pods_help() {
    cat <<'EOF'
Usage: kubectl_delete_stuck_terminating_pods -n <namespace>

Force-delete pods stuck in Terminating status. Namespace is required.
Shows matching pods and asks for confirmation (type 'yes' to proceed).
EOF
}

kubectl_delete_stuck_terminating_pods() {
    local namespace=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help) kubectl_delete_stuck_terminating_pods_help; return 0 ;;
            -n|--namespace)
                _kubectl_flag_value "$1" "${2:-}" || return 1
                namespace="$2"
                shift 2
                ;;
            *)
                echo "Unknown argument: $1" >&2
                kubectl_delete_stuck_terminating_pods_help >&2
                return 1
                ;;
        esac
    done

    _kubectl_delete_pods "$namespace" "stuck terminating pods" '$3=="Terminating"' 0 \
        --grace-period=0 --force
}

kubectl_restart_crashloop_pods_help() {
    cat <<'EOF'
Usage: kubectl_restart_crashloop_pods -n <namespace>

Delete CrashLoopBackOff pods to trigger restart. Namespace is required.
Shows matching pods and asks for confirmation (type 'yes' to proceed).
EOF
}

kubectl_restart_crashloop_pods() {
    local namespace=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help) kubectl_restart_crashloop_pods_help; return 0 ;;
            -n|--namespace)
                _kubectl_flag_value "$1" "${2:-}" || return 1
                namespace="$2"
                shift 2
                ;;
            *)
                echo "Unknown argument: $1" >&2
                kubectl_restart_crashloop_pods_help >&2
                return 1
                ;;
        esac
    done

    _kubectl_delete_pods "$namespace" "CrashLoopBackOff pods" '$3=="CrashLoopBackOff"'
}

kubectl_cleanup_namespace_help() {
    cat <<'EOF'
Usage: kubectl_cleanup_namespace -n <namespace>

Run all cleanup deletes in a namespace (completed, evicted, error, terminating).
Namespace is required. Shows all matching pods and asks once for confirmation (type 'yes').
EOF
}

kubectl_cleanup_namespace() {
    local namespace=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help) kubectl_cleanup_namespace_help; return 0 ;;
            -n|--namespace)
                _kubectl_flag_value "$1" "${2:-}" || return 1
                namespace="$2"
                shift 2
                ;;
            *)
                echo "Unknown argument: $1" >&2
                kubectl_cleanup_namespace_help >&2
                return 1
                ;;
        esac
    done

    _kubectl_require || return 1
    _kubectl_require_namespace "$namespace" "cleanup" || return 1

    echo "Scanning namespace: ${namespace}"

    local -a pods=() statuses=() categories=()
    local line pod status category awk_filter entry

    local filters=(
        'completed:$3=="Completed"'
        'evicted:$3=="Evicted"'
        'error:$3 ~ /Error|CrashLoopBackOff|ImagePullBackOff|ErrImagePull|CreateContainerConfigError|RunContainerError|ContainerStatusUnknown/'
        'terminating:$3=="Terminating"'
    )

    for entry in "${filters[@]}"; do
        category="${entry%%:*}"
        awk_filter="${entry#*:}"
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            pod="${line%% *}"
            status="${line#* }"
            pods+=("$pod")
            statuses+=("$status")
            categories+=("$category")
        done < <(_kubectl_collect_pods "$namespace" "$awk_filter")
    done

    if [[ ${#pods[@]} -eq 0 ]]; then
        echo "No pods to clean up in namespace: ${namespace}."
        return 0
    fi

    echo "Pods to clean up:"
    printf "%-12s %-40s %s\n" "CATEGORY" "POD" "STATUS"
    printf "%-12s %-40s %s\n" "--------" "----" "------"
    local i
    for i in "${!pods[@]}"; do
        printf "%-12s %-40s %s\n" "${categories[$i]}" "${pods[$i]}" "${statuses[$i]}"
    done

    _kubectl_confirm_yes "${#pods[@]}" || return 1

    _kubectl_delete_pods "$namespace" "completed pods" '$3=="Completed"' 1
    _kubectl_delete_pods "$namespace" "evicted pods" '$3=="Evicted"' 1
    _kubectl_delete_pods "$namespace" "error pods" \
        '$3 ~ /Error|CrashLoopBackOff|ImagePullBackOff|ErrImagePull|CreateContainerConfigError|RunContainerError|ContainerStatusUnknown/' 1
    _kubectl_delete_pods "$namespace" "stuck terminating pods" '$3=="Terminating"' 1 \
        --grace-period=0 --force

    echo "Cleanup complete for namespace: ${namespace}."
}

kubectl_pods_by_node_help() {
    cat <<'EOF'
Usage: kubectl_pods_by_node [-n <namespace>]

List pods sorted by node. Omit -n to search all namespaces.
EOF
}

kubectl_pods_by_node() {
    local namespace=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help) kubectl_pods_by_node_help; return 0 ;;
            -n|--namespace)
                _kubectl_flag_value "$1" "${2:-}" || return 1
                namespace="$2"
                shift 2
                ;;
            *)
                echo "Unknown argument: $1" >&2
                kubectl_pods_by_node_help >&2
                return 1
                ;;
        esac
    done

    _kubectl_require || return 1

    if [[ -n "$namespace" ]]; then
        kubectl get pods -n "$namespace" -o wide | sort -k7
    else
        kubectl get pods -A -o wide | sort -k8
    fi
}

kubectl_pods_by_restart_count_help() {
    cat <<'EOF'
Usage: kubectl_pods_by_restart_count [-n <namespace>]

List pods sorted by restart count. Omit -n to search all namespaces.
EOF
}

kubectl_pods_by_restart_count() {
    local namespace=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help) kubectl_pods_by_restart_count_help; return 0 ;;
            -n|--namespace)
                _kubectl_flag_value "$1" "${2:-}" || return 1
                namespace="$2"
                shift 2
                ;;
            *)
                echo "Unknown argument: $1" >&2
                kubectl_pods_by_restart_count_help >&2
                return 1
                ;;
        esac
    done

    _kubectl_require || return 1

    if [[ -n "$namespace" ]]; then
        kubectl get pods -n "$namespace" --sort-by='.status.containerStatuses[0].restartCount'
    else
        kubectl get pods -A --sort-by='.status.containerStatuses[0].restartCount'
    fi
}

kubectl_top_pods_help() {
    cat <<'EOF'
Usage: kubectl_top_pods [-n <namespace>]

Show pod CPU usage sorted by CPU. Omit -n to search all namespaces.
EOF
}

kubectl_top_pods() {
    local namespace=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help) kubectl_top_pods_help; return 0 ;;
            -n|--namespace)
                _kubectl_flag_value "$1" "${2:-}" || return 1
                namespace="$2"
                shift 2
                ;;
            *)
                echo "Unknown argument: $1" >&2
                kubectl_top_pods_help >&2
                return 1
                ;;
        esac
    done

    _kubectl_require || return 1

    if [[ -n "$namespace" ]]; then
        kubectl top pods -n "$namespace" --sort-by=cpu
    else
        kubectl top pods -A --sort-by=cpu
    fi
}

kubectl_top_nodes_help() {
    cat <<'EOF'
Usage: kubectl_top_nodes

Show node CPU and memory usage.
EOF
}

kubectl_top_nodes() {
    [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && { kubectl_top_nodes_help; return 0; }
    [[ $# -gt 0 ]] && { echo "Unknown argument: $1" >&2; kubectl_top_nodes_help >&2; return 1; }

    _kubectl_require || return 1
    kubectl top nodes
}

kubectl_pod_watch_help() {
    cat <<'EOF'
Usage: kubectl_pod_watch [-n <namespace>]

Watch pods (kubectl get pods). Omit -n to watch all namespaces.
EOF
}

kubectl_pod_watch() {
    local namespace=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help) kubectl_pod_watch_help; return 0 ;;
            -n|--namespace)
                _kubectl_flag_value "$1" "${2:-}" || return 1
                namespace="$2"
                shift 2
                ;;
            *)
                echo "Unknown argument: $1" >&2
                kubectl_pod_watch_help >&2
                return 1
                ;;
        esac
    done

    _kubectl_require || return 1

    if [[ -n "$namespace" ]]; then
        watch kubectl get pods -n "$namespace"
    else
        watch kubectl get pods -A
    fi
}

kubectl_pod_logs_help() {
    cat <<'EOF'
Usage: kubectl_pod_logs -n <namespace> -p <pod>

Tail logs for a pod (-f).
EOF
}

kubectl_pod_logs() {
    local namespace="" pod=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help) kubectl_pod_logs_help; return 0 ;;
            -n|--namespace)
                _kubectl_flag_value "$1" "${2:-}" || return 1
                namespace="$2"
                shift 2
                ;;
            -p|--pod)
                _kubectl_flag_value "$1" "${2:-}" || return 1
                pod="$2"
                shift 2
                ;;
            *)
                echo "Unknown argument: $1" >&2
                kubectl_pod_logs_help >&2
                return 1
                ;;
        esac
    done

    _kubectl_require || return 1
    _kubectl_require_value "$namespace" "-n" || return 1
    _kubectl_require_value "$pod" "-p" || return 1

    kubectl logs -f -n "$namespace" "$pod"
}

kubectl_pod_shell_help() {
    cat <<'EOF'
Usage: kubectl_pod_shell -n <namespace> -p <pod>

Open an interactive /bin/sh shell in a pod.
EOF
}

kubectl_pod_shell() {
    local namespace="" pod=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help) kubectl_pod_shell_help; return 0 ;;
            -n|--namespace)
                _kubectl_flag_value "$1" "${2:-}" || return 1
                namespace="$2"
                shift 2
                ;;
            -p|--pod)
                _kubectl_flag_value "$1" "${2:-}" || return 1
                pod="$2"
                shift 2
                ;;
            *)
                echo "Unknown argument: $1" >&2
                kubectl_pod_shell_help >&2
                return 1
                ;;
        esac
    done

    _kubectl_require || return 1
    _kubectl_require_value "$namespace" "-n" || return 1
    _kubectl_require_value "$pod" "-p" || return 1

    kubectl exec -it -n "$namespace" "$pod" -- /bin/sh
}

kubectl_pod_bash_help() {
    cat <<'EOF'
Usage: kubectl_pod_bash -n <namespace> -p <pod>

Open an interactive /bin/bash shell in a pod.
EOF
}

kubectl_pod_bash() {
    local namespace="" pod=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help) kubectl_pod_bash_help; return 0 ;;
            -n|--namespace)
                _kubectl_flag_value "$1" "${2:-}" || return 1
                namespace="$2"
                shift 2
                ;;
            -p|--pod)
                _kubectl_flag_value "$1" "${2:-}" || return 1
                pod="$2"
                shift 2
                ;;
            *)
                echo "Unknown argument: $1" >&2
                kubectl_pod_bash_help >&2
                return 1
                ;;
        esac
    done

    _kubectl_require || return 1
    _kubectl_require_value "$namespace" "-n" || return 1
    _kubectl_require_value "$pod" "-p" || return 1

    kubectl exec -it -n "$namespace" "$pod" -- /bin/bash
}

kubectl_describe_pod_help() {
    cat <<'EOF'
Usage: kubectl_describe_pod -n <namespace> -p <pod>

Describe a pod.
EOF
}

kubectl_describe_pod() {
    local namespace="" pod=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help) kubectl_describe_pod_help; return 0 ;;
            -n|--namespace)
                _kubectl_flag_value "$1" "${2:-}" || return 1
                namespace="$2"
                shift 2
                ;;
            -p|--pod)
                _kubectl_flag_value "$1" "${2:-}" || return 1
                pod="$2"
                shift 2
                ;;
            *)
                echo "Unknown argument: $1" >&2
                kubectl_describe_pod_help >&2
                return 1
                ;;
        esac
    done

    _kubectl_require || return 1
    _kubectl_require_value "$namespace" "-n" || return 1
    _kubectl_require_value "$pod" "-p" || return 1

    kubectl describe pod -n "$namespace" "$pod"
}

kubectl_get_all_help() {
    cat <<'EOF'
Usage: kubectl_get_all [-n <namespace>]

Get all resources in a namespace. Omit -n to search all namespaces.
EOF
}

kubectl_get_all() {
    local namespace=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help) kubectl_get_all_help; return 0 ;;
            -n|--namespace)
                _kubectl_flag_value "$1" "${2:-}" || return 1
                namespace="$2"
                shift 2
                ;;
            *)
                echo "Unknown argument: $1" >&2
                kubectl_get_all_help >&2
                return 1
                ;;
        esac
    done

    _kubectl_require || return 1

    if [[ -n "$namespace" ]]; then
        kubectl get all -n "$namespace"
    else
        kubectl get all -A
    fi
}

kubectl_restart_deployment_help() {
    cat <<'EOF'
Usage: kubectl_restart_deployment -n <namespace> -d <deployment>

Rollout restart a deployment.
EOF
}

kubectl_restart_deployment() {
    local namespace="" deployment=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help) kubectl_restart_deployment_help; return 0 ;;
            -n|--namespace)
                _kubectl_flag_value "$1" "${2:-}" || return 1
                namespace="$2"
                shift 2
                ;;
            -d|--deployment)
                _kubectl_flag_value "$1" "${2:-}" || return 1
                deployment="$2"
                shift 2
                ;;
            *)
                echo "Unknown argument: $1" >&2
                kubectl_restart_deployment_help >&2
                return 1
                ;;
        esac
    done

    _kubectl_require || return 1
    _kubectl_require_value "$namespace" "-n" || return 1
    _kubectl_require_value "$deployment" "-d" || return 1

    kubectl rollout restart deployment "$deployment" -n "$namespace"
}

kubectl_rollout_status_help() {
    cat <<'EOF'
Usage: kubectl_rollout_status -n <namespace> -d <deployment>

Watch rollout status for a deployment.
EOF
}

kubectl_rollout_status() {
    local namespace="" deployment=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help) kubectl_rollout_status_help; return 0 ;;
            -n|--namespace)
                _kubectl_flag_value "$1" "${2:-}" || return 1
                namespace="$2"
                shift 2
                ;;
            -d|--deployment)
                _kubectl_flag_value "$1" "${2:-}" || return 1
                deployment="$2"
                shift 2
                ;;
            *)
                echo "Unknown argument: $1" >&2
                kubectl_rollout_status_help >&2
                return 1
                ;;
        esac
    done

    _kubectl_require || return 1
    _kubectl_require_value "$namespace" "-n" || return 1
    _kubectl_require_value "$deployment" "-d" || return 1

    kubectl rollout status deployment "$deployment" -n "$namespace"
}

kubectl_scale_deployment_help() {
    cat <<'EOF'
Usage: kubectl_scale_deployment -n <namespace> -d <deployment> -r <replicas>

Scale a deployment to the given replica count.
EOF
}

kubectl_scale_deployment() {
    local namespace="" deployment="" replicas=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help) kubectl_scale_deployment_help; return 0 ;;
            -n|--namespace)
                _kubectl_flag_value "$1" "${2:-}" || return 1
                namespace="$2"
                shift 2
                ;;
            -d|--deployment)
                _kubectl_flag_value "$1" "${2:-}" || return 1
                deployment="$2"
                shift 2
                ;;
            -r|--replicas)
                _kubectl_flag_value "$1" "${2:-}" || return 1
                replicas="$2"
                shift 2
                ;;
            *)
                echo "Unknown argument: $1" >&2
                kubectl_scale_deployment_help >&2
                return 1
                ;;
        esac
    done

    _kubectl_require || return 1
    _kubectl_require_value "$namespace" "-n" || return 1
    _kubectl_require_value "$deployment" "-d" || return 1
    _kubectl_require_value "$replicas" "-r" || return 1

    kubectl scale deployment "$deployment" --replicas="$replicas" -n "$namespace"
}

kubectl_decode_secret_help() {
    cat <<'EOF'
Usage: kubectl_decode_secret -n <namespace> -s <secret> -k <key>

Decode a base64 secret key and print the value.
EOF
}

kubectl_decode_secret() {
    local namespace="" secret="" key=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help) kubectl_decode_secret_help; return 0 ;;
            -n|--namespace)
                _kubectl_flag_value "$1" "${2:-}" || return 1
                namespace="$2"
                shift 2
                ;;
            -s|--secret)
                _kubectl_flag_value "$1" "${2:-}" || return 1
                secret="$2"
                shift 2
                ;;
            -k|--key)
                _kubectl_flag_value "$1" "${2:-}" || return 1
                key="$2"
                shift 2
                ;;
            *)
                echo "Unknown argument: $1" >&2
                kubectl_decode_secret_help >&2
                return 1
                ;;
        esac
    done

    _kubectl_require || return 1
    _kubectl_require_value "$namespace" "-n" || return 1
    _kubectl_require_value "$secret" "-s" || return 1
    _kubectl_require_value "$key" "-k" || return 1

    kubectl get secret "$secret" -n "$namespace" -o "jsonpath={.data.${key}}" | base64 --decode
    echo
}

kubectl_context_help() {
    cat <<'EOF'
Usage: kubectl_context

Print the current kubectl context.
EOF
}

kubectl_context() {
    [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && { kubectl_context_help; return 0; }
    [[ $# -gt 0 ]] && { echo "Unknown argument: $1" >&2; kubectl_context_help >&2; return 1; }

    _kubectl_require || return 1
    kubectl config current-context
}

kubectl_contexts_help() {
    cat <<'EOF'
Usage: kubectl_contexts

List all kubectl contexts.
EOF
}

kubectl_contexts() {
    [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && { kubectl_contexts_help; return 0; }
    [[ $# -gt 0 ]] && { echo "Unknown argument: $1" >&2; kubectl_contexts_help >&2; return 1; }

    _kubectl_require || return 1
    kubectl config get-contexts
}

kubectl_use_context_help() {
    cat <<'EOF'
Usage: kubectl_use_context -c <context>

Switch to the given kubectl context.
EOF
}

kubectl_use_context() {
    local context=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help) kubectl_use_context_help; return 0 ;;
            -c|--context)
                _kubectl_flag_value "$1" "${2:-}" || return 1
                context="$2"
                shift 2
                ;;
            *)
                echo "Unknown argument: $1" >&2
                kubectl_use_context_help >&2
                return 1
                ;;
        esac
    done

    _kubectl_require || return 1
    _kubectl_require_value "$context" "-c" || return 1

    kubectl config use-context "$context"
}

kubectl_namespaces_help() {
    cat <<'EOF'
Usage: kubectl_namespaces

List all namespaces.
EOF
}

kubectl_namespaces() {
    [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && { kubectl_namespaces_help; return 0; }
    [[ $# -gt 0 ]] && { echo "Unknown argument: $1" >&2; kubectl_namespaces_help >&2; return 1; }

    _kubectl_require || return 1
    kubectl get ns
}

kubectl_events_help() {
    cat <<'EOF'
Usage: kubectl_events [-n <namespace>]

List events sorted by last timestamp. Omit -n to search all namespaces.
EOF
}

kubectl_events() {
    local namespace=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help) kubectl_events_help; return 0 ;;
            -n|--namespace)
                _kubectl_flag_value "$1" "${2:-}" || return 1
                namespace="$2"
                shift 2
                ;;
            *)
                echo "Unknown argument: $1" >&2
                kubectl_events_help >&2
                return 1
                ;;
        esac
    done

    _kubectl_require || return 1

    if [[ -n "$namespace" ]]; then
        kubectl get events -n "$namespace" --sort-by='.lastTimestamp'
    else
        kubectl get events -A --sort-by='.lastTimestamp'
    fi
}

kubectl_failed_events_help() {
    cat <<'EOF'
Usage: kubectl_failed_events [-n <namespace>]

List events matching error/failed/backoff/unhealthy. Omit -n for all namespaces.
EOF
}

kubectl_failed_events() {
    local namespace=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help) kubectl_failed_events_help; return 0 ;;
            -n|--namespace)
                _kubectl_flag_value "$1" "${2:-}" || return 1
                namespace="$2"
                shift 2
                ;;
            *)
                echo "Unknown argument: $1" >&2
                kubectl_failed_events_help >&2
                return 1
                ;;
        esac
    done

    _kubectl_require || return 1

    if [[ -n "$namespace" ]]; then
        kubectl get events -n "$namespace" | grep -Ei 'error|failed|backoff|unhealthy' || true
    else
        kubectl get events -A | grep -Ei 'error|failed|backoff|unhealthy' || true
    fi
}

kubectl_help() {
    cat <<'EOF'
Kubernetes utilities (all functions prefixed kubectl_).

Common flags:
  -n, --namespace     Namespace (optional for list/get; required for delete)
  -p, --pod           Pod name
  -d, --deployment    Deployment name
  -r, --replicas      Replica count
  -s, --secret        Secret name
  -k, --key           Secret key
  -c, --context       Kubectl context name
  -h, --help          Show function help

Delete functions require -n and confirmation (type 'yes').

Functions:
  kubectl_delete_completed_pods -n <ns>
  kubectl_delete_evicted_pods -n <ns>
  kubectl_delete_error_pods -n <ns>
  kubectl_delete_stuck_terminating_pods -n <ns>
  kubectl_restart_crashloop_pods -n <ns>
  kubectl_cleanup_namespace -n <ns>
  kubectl_pods_by_node [-n <ns>]
  kubectl_pods_by_restart_count [-n <ns>]
  kubectl_top_pods [-n <ns>]
  kubectl_top_nodes
  kubectl_pod_watch [-n <ns>]
  kubectl_pod_logs -n <ns> -p <pod>
  kubectl_pod_shell -n <ns> -p <pod>
  kubectl_pod_bash -n <ns> -p <pod>
  kubectl_describe_pod -n <ns> -p <pod>
  kubectl_get_all [-n <ns>]
  kubectl_restart_deployment -n <ns> -d <deployment>
  kubectl_rollout_status -n <ns> -d <deployment>
  kubectl_scale_deployment -n <ns> -d <deployment> -r <replicas>
  kubectl_decode_secret -n <ns> -s <secret> -k <key>
  kubectl_context
  kubectl_contexts
  kubectl_use_context -c <context>
  kubectl_namespaces
  kubectl_events [-n <ns>]
  kubectl_failed_events [-n <ns>]

Run '<function> -h' for detailed help on any function.
EOF
}
