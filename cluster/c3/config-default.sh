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

## Contains configuration values for interacting with the Vagrant cluster

# Common settings for both master and minions
ATOMIC_NODE="${ATOMIC_NODE-false}"
export ATOMIC_NODE

# LVS01 Fedora Cloud Basae 21 image
lvs01_KUBE_IMAGE="5fc8422a-e7c3-40d6-aa95-b3bbc5aeec6b"
lvs01_SWIFT_ENDPOINT="https://os-r-object.vip.lvs.ebayc3.com/v1"

# SLC01 Fedora Cloud Basae 21 image
if [ $ATOMIC_NODE == "true" ]; then
  slc01_KUBE_IMAGE="2f7e8774-f1a3-4e55-8d12-894dd5df2887"
else
  slc01_KUBE_IMAGE="e2dfa3a7-2ea0-46e9-be80-227719eca7d5"
fi
slc01_SWIFT_ENDPOINT="https://os-r-object.vip.slc.ebayc3.com/v1"

# PHX01 Fedora Cloud Basae 21 image
phx01_KUBE_IMAGE="c5f01299-a080-42b0-bf8c-c747e64114b3"
phx01_SWIFT_ENDPOINT="https://os-r-object.vip.phx.ebayc3.com/v1"

export TESSNET_BINARY_LOCATION=https://os-r-object.vip.slc.ebayc3.com/v1/KEY_630396909e6f4bf89d89477708c43e23/kubernetes-staging/tessnet

# Number of minions in the cluster
NUM_NODES=${NUM_NODES-"1"}
export NUM_NODES


# Network settings

# network device name to use for exposing API services
export API_DEVICE=${API_DEVICE:-'eth0'}

# Master settings
export KUBE_MASTER_HA=true
export KUBE_MASTER_FLAVOR="${KUBE_MASTER_FLAVOR-9}"
#export MASTER_IP="10.245.1.2"

NUM_MASTERS=1

export NUM_MASTERS
export INSTANCE_PREFIX=kubernetes
export MASTER_NAME="${INSTANCE_PREFIX}-master"

declare -a MASTER_NAMES
for (( c=0; c<${NUM_MASTERS}; c++ ))
do
    MASTER_NAMES[$c]="$MASTER_NAME-$((c+1))"
done
export MASTER_NAMES

# Minion settings
export KUBE_MINION_FLAVOR="${KUBE_MINION_FLAVOR-9}"
export CONTAINER_SUBNET_PREFIX="192.168."

# Map out the IPs, names and container subnets of each minion
#export MINION_IP_BASE="10.245.1."
MINION_CONTAINER_SUBNET_BASE="172.20"
CONTAINER_SUBNET="${MINION_CONTAINER_SUBNET_BASE}.0.0/16"
for ((i=0; i < NUM_NODES; i++)) do
  MINION_NAMES[$i]="${INSTANCE_PREFIX}-minion-$((i+1))"
  MINION_CONTAINER_SUBNETS[$i]="${MINION_CONTAINER_SUBNET_BASE}.${i}.0/24"
  MINION_CONTAINER_ADDRS[$i]="${MINION_CONTAINER_SUBNET_BASE}.${i}.254"
  MINION_CONTAINER_NETMASKS[$i]="255.255.255.0"
  VAGRANT_MINION_NAMES[$i]="minion-$((i+1))"
done

SERVICE_CLUSTER_IP_RANGE=192.168.0.0/16

# Since this isn't exposed on the network, default to a simple user/passwd
MASTER_USER=fedora
MASTER_PASSWD=fedora

# Optional: Install node monitoring.
ENABLE_NODE_MONITORING=false
ENABLE_CLUSTER_MONITORING=false
GRAFANA_MEMORY_LIMIT_MB="${GRAFANA_MEMORY_LIMIT_MB-100}"
HEAPSTER_MEMORY_LIMIT_MB="${HEAPSTER_MEMORY_LIMIT_MB-300}"
ALERTMANAGER_MEMORY_LIMIT_MB="${ALERTMANAGER_MEMORY_LIMIT_MB-100}"
PROMETHEUS_MEMORY_LIMIT_MB="${PROMETHEUS_MEMORY_LIMIT_MB-300}"
PROMETHEUS_MEMORY_CHUNKS="${PROMETHEUS_MEMORY_CHUNKS-102400}"
PROMETHEUS_RETENTION="${PROMETHEUS_RETENTION-720h}"
INFLUXDB_MEMORY_LIMIT_MB="${INFLUXDB_MEMORY_LIMIT_MB-300}"

# Optional: Enable node logging.
ENABLE_NODE_LOGGING=false
LOGGING_DESTINATION=logstash-elasticsearch

# Optional: When set to true, Elasticsearch and Kibana will be setup as part of the cluster bring up.
ENABLE_CLUSTER_LOGGING=false
ELASTICSEARCH_LOGGING_REPLICAS="${ELASTICSEARCH_LOGGING_REPLICAS-1}"
ELASTICSEARCH_LOGGING_MASTER_REPLICAS="${ELASTICSEARCH_LOGGING_MASTER_REPLICAS-1}"
ELASTICSEARCH_HEAP_SIZE_GB="${ELASTICSEARCH_HEAP_SIZE_GB-1}"
ELASTICSEARCH_HOST_PORT="pronto-es-tess-io-8521.lvs01.dev.ebayc3.com:9200"

# ENABLE_DOCKER_REGISTRY_CACHE=true

# Don't require https for registries in our local RFC1918 network
EXTRA_DOCKER_OPTS="--insecure-registry 10.0.0.0/8  --log-level=warn"

# Optional: Install cluster DNS.
ENABLE_CLUSTER_DNS=true
DNS_SERVER_IP="192.168.0.10"
DNS_DOMAIN="kubernetes.local"
DNS_REPLICAS=1

# Optional: Enable setting flags for kube-apiserver to turn on behavior in active-dev
RUNTIME_CONFIG="api/v1"

if ! which openstack >/dev/null; then
    echo "Can't find openstack command line client in PATH, please run pip install python-openstackclient. And also refer to https://github.corp.ebay.com/tess/tess/issues/536 if you run into issues"
    exit 1
fi

if [[ -z "${OS_TENANT_ID-}" ]]; then
    if [[ -z "${OS_TENANT_NAME-}" ]]; then
        echo -e "${color_red}OS_TENANT_NAME not set. Please check if you have sourced your openrc for openstack${color_norm}"
        return 1
    fi
    export OS_TENANT_ID=`openstack project show ${OS_TENANT_NAME} | awk '/ id / {print $0}' | awk -F '|' '{print $3}' | xargs`
fi

if openstack --version 2>&1 | grep -q 'openstack 2.1.0'; then
    project_details=$(openstack project show ${OS_TENANT_ID})
    VPC=$(echo "$project_details" | sed -n "s/|\s*properties\s*|\s*.*vpc='\([^']*\)'.*/\1/p")
    OS_TENANT_NAME=$(echo "$project_details" | sed -n "s/|\s*name\s*|\s*\([^/s]*\)/\1/p")
else
    # supposed to work on other versions of openstack?
    project_details=$(mktemp -t temp_project_details.XXXX)
    openstack project show ${OS_TENANT_ID} > $project_details
    VPC=$(cat $project_details | awk '/ vpc / {print $4}')
    OS_TENANT_NAME=$(cat $project_details | awk '/ name / {print $4}')
    rm -R $project_details
fi

export OS_TENANT_NAME=${OS_TENANT_NAME}

DOMAIN_SUFFIX="${VPC}.ebayc3.com"

# Specific SSH key to be used for this cluster
SSH_KEY_NAME=${SSH_KEY_NAME-"id_kubernetes_${OS_TENANT_NAME}"}
echo "SSH_KEY_NAME=${SSH_KEY_NAME}"}

export CLUSTER_EXTERNAL_DNS_NAME="${CLUSTER_EXTERNAL_DNS_NAME-unspecified}"
#(todo): generate one dynamically, if not specified

# Cinder volume name for etcd
export CLUSTER_METADATA_VOLUME="ETCD_metadata_volume"
export CLUSTER_METADATA_VOLUME_SIZE=2

if [ "$VPC" = "dev" ]; then
    NETWORK_MODE="overlay"
    DUAL_NIC=true
    #External Networks for creating Floating ips
    slc01_EXTERNAL_NET="c0667e7d-a6ff-4fda-8994-d96b23050a5a"
    phx01_EXTERNAL_NET="bde88fa4-78d7-4082-9fba-1b3491da094d"
    lvs01_EXTERNAL_NET="c817eee7-17ff-4efa-828e-f0c871567e57"

    #LB Subnets for VIP creation
    slc01_LB_SUBNET="4541b667-17ab-42fd-a38d-83fc824de43c"
    phx01_LB_SUBNET="61b46c05-3b15-43ae-93e0-9301321bfd52"
    lvs01_LB_SUBNET="d546f4ad-2268-4848-8dc4-120015c73390"
elif [ "$VPC" = "eaz" ]; then
    NETWORK_MODE="overlay"
    DUAL_NIC=true
    #External Networks for creating Floating ips
    phx01_EXTERNAL_NET="12bba0de-5911-4b2f-bb60-6270152bd3c3"
    lvs01_EXTERNAL_NET="dc92a5df-65d8-4bbb-b44e-06e10db484bc"

    #LB Subnets for VIP creation
    phx01_LB_SUBNET="7d677b6b-eeba-4138-bca3-54eed1c807d4"
    lvs01_LB_SUBNET="90f5c931-2e7f-43e8-ad27-9d6c41a5e636"
elif [ "$VPC" = "mpt-prod" ]; then
    NETWORK_MODE="bridged"
    DUAL_NIC=false
    #External Networks for creating Floating ips
    slc01_EXTERNAL_NET="c0667e7d-a6ff-4fda-8994-d96b23050a5a"
    phx01_EXTERNAL_NET="bde88fa4-78d7-4082-9fba-1b3491da094d"
    lvs01_EXTERNAL_NET="c817eee7-17ff-4efa-828e-f0c871567e57"

    #LB Subnets for VIP creation
    slc01_LB_SUBNET="108b717e-79b5-4b8e-93b4-3fac1b856f4f"
    phx01_LB_SUBNET="2a5aa4b3-3ee0-41df-8ac5-1d14ca7114d9"
    lvs01_LB_SUBNET="d546f4ad-2268-4848-8dc4-120015c73390"
else
    echo "VPC of tenant could not be determined"
    exit 1
fi


export ENABLE_ETCD_CINDER_VOLUME="true"
export SALT_MASTER=""
export SALT_MASTER_FQDN=""

# Do not over ride this. This is set during master flex
export MASTER_FLEX="false"
export ENABLE_API_SERVER_LB=${ENABLE_API_SERVER_LB:-'false'}
export APISERVER_LB_IP=${APISERVER_LB_IP:-''}
if [[ "${ENABLE_API_SERVER_LB}" == "true" ]]; then
    export APISERVER_PORT=443
else
    export APISERVER_PORT=6443
fi

export TAB_PREFIX="---->"

# The openstack swift binary to use
export SWIFT=${SWIFT:-'swift'}
export OS_VOLUME_API_VERSION=1
