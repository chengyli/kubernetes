#!/bin/bash

# Copyright 2015 The Kubernetes Authors All rights reserved.
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

# Create the overlay files for the salt tree.  We create these in a separate
# place so that we can blow away the rest of the salt configs on a kube-push and
# re-apply these.

cluster_pillar="/srv/salt-overlay/pillar/cluster-params.sls"
mkdir -p /srv/salt-overlay/pillar
cat <<EOF >"${cluster_pillar}"
node_instance_prefix: '$(echo "$NODE_INSTANCE_PREFIX" | sed -e "s/'/''/g")'
service_cluster_ip_range: '$(echo "$SERVICE_CLUSTER_IP_RANGE" | sed -e "s/'/''/g")'
enable_cluster_monitoring: '$(echo "$ENABLE_CLUSTER_MONITORING" | sed -e "s/'/''/g")'
enable_node_monitoring: '$(echo "$ENABLE_NODE_MONITORING" | sed -e "s/'/''/g")'
grafana_memory_mb: '$(echo "$GRAFANA_MEMORY_LIMIT_MB" | sed -e "s/'/''/g")'
heapster_memory_mb: '$(echo "$HEAPSTER_MEMORY_LIMIT_MB" | sed -e "s/'/''/g")'
alertmanager_memory_mb: '$(echo "$ALERTMANAGER_MEMORY_LIMIT_MB" | sed -e "s/'/''/g")'
prometheus_memory_mb: '$(echo "$PROMETHEUS_MEMORY_LIMIT_MB" | sed -e "s/'/''/g")'
prometheus_memory_chunks: '$(echo "$PROMETHEUS_MEMORY_CHUNKS" | sed -e "s/'/''/g")'
prometheus_retenion: '$(echo "$PROMETHEUS_RETENTION" | sed -e "s/'/''/g")'
influxdb_memory_mb: '$(echo "$INFLUXDB_MEMORY_LIMIT_MB" | sed -e "s/'/''/g")'
enable_cluster_logging: '$(echo "$ENABLE_CLUSTER_LOGGING" | sed -e "s/'/''/g")'
enable_node_logging: '$(echo "$ENABLE_NODE_LOGGING" | sed -e "s/'/''/g")'
logging_destination: '$(echo "$LOGGING_DESTINATION" | sed -e "s/'/''/g")'
elasticsearch_replicas: '$(echo "$ELASTICSEARCH_LOGGING_REPLICAS" | sed -e "s/'/''/g")'
elasticsearch_master_replicas: '$(echo "$ELASTICSEARCH_LOGGING_MASTER_REPLICAS" | sed -e "s/'/''/g")'
elasticsearch_heap_size_gb: '$(echo "$ELASTICSEARCH_HEAP_SIZE_GB" | sed -e "s/'/''/g")'
elasticsearch_host_port: '$(echo "$ELASTICSEARCH_HOST_PORT" | sed -e "s/'/''/g")'
os_tenant_name: '$(echo "$OS_TENANT_NAME" | sed -e "s/'/''/g")'
enable_cluster_dns: '$(echo "$ENABLE_CLUSTER_DNS" | sed -e "s/'/''/g")'
dns_replicas: '$(echo "$DNS_REPLICAS" | sed -e "s/'/''/g")'
dns_server: '$(echo "$DNS_SERVER_IP" | sed -e "s/'/''/g")'
dns_domain: '$(echo "$DNS_DOMAIN" | sed -e "s/'/''/g")'
admission_control: 'ServiceAccount,ResourceQuota,LimitRanger'
network_mode: '$(echo "$NETWORK_MODE" | sed -e "s/'/''/g")'
#the externally visible domain suffix, e.g slc01.tess.io
domain_suffix: '$(echo "$DOMAIN_SUFFIX" | sed -e "s/'/''/g")'
cluster_external_name: '$(echo "${CLUSTER_APISERVER_DNS_NAME}" | sed -e "s/'/''/g")'
cluster_domain_suffix: '$(echo "${CLUSTER_DOMAIN_SUFFIX}" | sed -e "s/'/''/g")'
api_servers_with_port: 'https://$(echo ${CLUSTER_APISERVER_DNS_NAME}:${APISERVER_PORT} | sed -e "s/'/''/g")'
master_extra_sans: 'IP:192.168.0.1,DNS:kubernetes,DNS:kubernetes-ro,DNS:kubernetes.default,DNS:kubernetes.default.svc,DNS:kubernetes.default.svc.cluster.local,DNS:$(echo "*.${CLUSTER_DOMAIN_SUFFIX}")'
EOF

if [[ "${ENABLE_API_SERVER_LB}" == "true" ]]; then
    # If APISERVER_LB_IP is not set, cluster_external_ip will be generated on salt master in bootstrap-gen-pillars sls
    echo "cluster_external_ip: '$(echo "${APISERVER_LB_IP}" | sed -e "s/'/''/g")'" >> "${cluster_pillar}"
fi

mkdir -p /srv/salt-overlay/salt/nginx
echo $MASTER_HTPASSWD > /srv/salt-overlay/salt/nginx/htpasswd

# Generate and distribute a shared secret (bearer token) to
# apiserver and kubelet so that kubelet can authenticate to
# apiserver to send events.
known_tokens_file="/srv/salt-overlay/salt/kube-apiserver/known_tokens.csv"
if [[ ! -f "${known_tokens_file}" ]]; then
  kubelet_token=$(cat /dev/urandom | base64 | tr -d "=+/" | dd bs=32 count=1 2> /dev/null)
  kube_proxy_token=$(cat /dev/urandom | base64 | tr -d "=+/" | dd bs=32 count=1 2> /dev/null)

  mkdir -p /srv/salt-overlay/salt/kube-apiserver
  (umask u=rw,go= ;
   echo "$kubelet_token,kubelet,kubelet" > $known_tokens_file;
   echo "$kube_proxy_token,kube_proxy,kube_proxy" >> $known_tokens_file)

  # Generate tokens for other "service accounts".  Append to known_tokens.
  #
  # NB: If this list ever changes, this script actually has to
  # change to detect the existence of this file, kill any deleted
  # old tokens and add any new tokens (to handle the upgrade case).
  service_accounts=("system:scheduler" "system:controller_manager" "system:logging" "system:monitoring" "system:dns" "system:read-only")
  for account in "${service_accounts[@]}"; do
    token=$(dd if=/dev/urandom bs=128 count=1 2>/dev/null | base64 | tr -d "=+/" | dd bs=32 count=1 2>/dev/null)
    echo "${token},${account},${account}" >> "${known_tokens_file}"
  done
fi