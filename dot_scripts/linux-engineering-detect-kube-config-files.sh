#!/bin/bash

# Builds KUBECONFIG from the machine's own ~/.kube/config and every *.yml/*.yaml file under
# ~/.kube/config-files. The order is the point: kubectl takes the default context from the first
# file that sets one, and `kubectl config use-context` writes into that same file. So
# ~/.kube/config, the machine-local file the secrets sync never copies, comes first, and the extra
# files follow sorted by name. They used to follow the order `find` happened to return, which
# changes whenever a tool rewrites one of them, so a new shell's default context could move to
# another cluster without anyone choosing it.
export KUBECONFIG=""
_kube_count=0

# if there's already a kubeconfig file in ~/.kube/config it will import that too and all the contexts
DEFAULT_KUBECONFIG_FILE="$HOME/.kube/config"
if [[ -f "${DEFAULT_KUBECONFIG_FILE}" ]]; then
  export KUBECONFIG="$DEFAULT_KUBECONFIG_FILE"
  _kube_count=$((_kube_count + 1))
fi

# your additional kubeconfig files should be inside ~/.kube/config-files, merged in name order
ADD_KUBECONFIG_FILES="$HOME/.kube/config-files"
if [[ -d "${ADD_KUBECONFIG_FILES}" ]]; then
  while IFS= read -r kubeconfigFile; do
    export KUBECONFIG="${KUBECONFIG:+$KUBECONFIG:}$kubeconfigFile"
    _kube_count=$((_kube_count + 1))
  done < <(find "${ADD_KUBECONFIG_FILES}" -type f \( -name "*.yml" -o -name "*.yaml" \) | LC_ALL=C sort)
fi

if [[ $_kube_count -gt 0 ]]; then
  echo "[kube-config] merged $_kube_count kubeconfig files" >&2
fi
