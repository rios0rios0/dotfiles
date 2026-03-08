#!/bin/bash

export KUBECONFIG=""
_kube_count=0

# if there's already a kubeconfig file in ~/.kube/config it will import that too and all the contexts
DEFAULT_KUBECONFIG_FILE="$HOME/.kube/config"
if [[ -f "${DEFAULT_KUBECONFIG_FILE}" ]]; then
  export KUBECONFIG="$DEFAULT_KUBECONFIG_FILE"
  _kube_count=$((_kube_count + 1))
fi

# your additional kubeconfig files should be inside ~/.kube/config-files
ADD_KUBECONFIG_FILES="$HOME/.kube/config-files"
if [[ -d "${ADD_KUBECONFIG_FILES}" ]]; then
  for kubeconfigFile in $(find "${ADD_KUBECONFIG_FILES}" -type f -name "*.yml" -o -name "*.yaml")
  do
    export KUBECONFIG="$kubeconfigFile:$KUBECONFIG"
    _kube_count=$((_kube_count + 1))
  done
fi

if [[ $_kube_count -gt 0 ]]; then
  echo "[kube-config] merged $_kube_count kubeconfig files" >&2
fi
