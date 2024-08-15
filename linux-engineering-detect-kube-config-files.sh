#!/bin/bash

export KUBECONFIG=""
# if there's already a kubeconfig file in ~/.kube/config it will import that too and all the contexts
DEFAULT_KUBECONFIG_FILE="$HOME/.kube/config"
if [[ -f "${DEFAULT_KUBECONFIG_FILE}" ]]; then
  export KUBECONFIG="$DEFAULT_KUBECONFIG_FILE"
fi

# your additional kubeconfig files should be inside ~/.kube/config-files
ADD_KUBECONFIG_FILES="$HOME/.kube/config-files"
if [[ -d "${ADD_KUBECONFIG_FILES}" ]]; then
  for kubeconfigFile in $(find "${ADD_KUBECONFIG_FILES}" -type f -name "*.yml" -o -name "*.yaml")
  do
    export KUBECONFIG="$kubeconfigFile:$KUBECONFIG"
  done
fi
