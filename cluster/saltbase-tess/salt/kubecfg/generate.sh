#!/bin/bash

# Copyright 2014 The Kubernetes Authors All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Common utilites for kube-up/kube-down, modified for kube-assist's use

set -o errexit
set -o nounset
set -o pipefail

: ${KUBECTL:='/usr/local/bin/kubectl'}
: ${KNOWN_TOKENS:='/srv/kubernetes/known_tokens.csv'}

# Generate kubeconfig data for the created cluster.
# Assumed vars:
#   KUBE_USER
#   KUBE_PASSWORD
#   KUBE_MASTER_IP
#   KUBECONFIG
#   CONTEXT
#
# If the apiserver supports bearer auth, also provide:
#   KUBE_BEARER_TOKEN
#
# The following can be omitted for --insecure-skip-tls-verify
#   KUBE_CERT
#   KUBE_KEY
#   CA_CERT
function create-kubeconfig() {

  local cluster_args=(
      "--server=${KUBE_SERVER:-https://${KUBE_MASTER_IP}}"
  )
  if [[ -z "${CA_CERT:-}" ]]; then
    cluster_args+=("--insecure-skip-tls-verify=true")
  else
    cluster_args+=(
      "--certificate-authority=${CA_CERT}"
      "--embed-certs=true"
    )
  fi

  local user_args=()
  if [[ ! -z "${KUBE_BEARER_TOKEN:-}" ]]; then
    user_args+=(
     "--token=${KUBE_BEARER_TOKEN}"
    )
  else
  if [[ -z "$KUBE_ROLE" ]]; then
     echo "no role specified, expected a value matching text in /srv/kubernetes/know_tokens.csv"
     return 0
  fi
    KUBE_BEARER_TOKEN=$(grep "${KUBE_ROLE}" "${KNOWN_TOKENS}" | cut -d',' -f1)
    if [ -z "${KUBE_BEARER_TOKEN}" ]; then
         echo "no bearer token provided or found"
         return 1
    fi
    user_args+=(
     "--token=${KUBE_BEARER_TOKEN}"
    )
  fi

  if [[ ! -z "${KUBE_CERT:-}" && ! -z "${KUBE_KEY:-}" ]]; then
    user_args+=(
     "--client-certificate=${KUBE_CERT}"
     "--client-key=${KUBE_KEY}"
     "--embed-certs=true"
    )
  fi

  # KUBECONFIG determines the file we write to, but it may not exist yet
  if [[ ! -e "${KUBECONFIG}" ]]; then
    mkdir -p $(dirname "${KUBECONFIG}")
    touch "${KUBECONFIG}"
  fi

  "${KUBECTL}" config set-cluster "${CONTEXT}" "${cluster_args[@]}"
  if [[ -n "${user_args[@]:-}" ]]; then
    "${KUBECTL}" config set-credentials "${CONTEXT}" "${user_args[@]}"
  fi
  "${KUBECTL}" config set-context "${CONTEXT}" --cluster="${CONTEXT}" --user="${CONTEXT}"
  "${KUBECTL}" config use-context "${CONTEXT}"  --cluster="${CONTEXT}"

  # If we have a bearer token, also create a credential entry with basic auth
  # so that it is easy to discover the basic auth password for your cluster
  # to use in a web browser.
  if [[ ! -z "${KUBE_BEARER_TOKEN:-}" && ! -z "${KUBE_USER:-}" && ! -z "${KUBE_PASSWORD:-}" ]]; then
    "${KUBECTL}" config set-credentials "${CONTEXT}-basic-auth" "--username=${KUBE_USER}" "--password=${KUBE_PASSWORD}"
  fi

   echo "Wrote config for ${CONTEXT} to ${KUBECONFIG}"
}

#invoke
create-kubeconfig
