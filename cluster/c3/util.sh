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

# A library of helper functions that each provider hosting Kubernetes must implement to use cluster/kube-*.sh scripts.

KUBE_ROOT=$(dirname "${BASH_SOURCE}")/../..

source "${KUBE_ROOT}/cluster/c3/config-default.sh"
source "${KUBE_ROOT}/cluster/c3/credentials-store.sh"
source "${KUBE_ROOT}/cluster/c3/ETCD-cinder-volume.sh"

function long-sleep() {
    echo
    printf "Waiting $1 seconds "
    start=$SECONDS
    while true; do
        printf "."
        sleep 2
        duration=$(( SECONDS - start ))
        if [[ $duration -gt $1 ]]; then
            break
        fi
    done
    printf " DONE\n"
}

# FIXME
function detect-master () {
    KUBE_MASTER_IP=$MASTER_IP
    echo -e "${color_green}+++ KUBE_MASTER_IP: ${KUBE_MASTER_IP} ${color_norm}" 1>&2
}

function detect-master-hostname () {
    local master=${SALT_MASTER:-kubernetes-master-1}
    master_data=$(nova show $master | awk '/ metadata / {print $0}' | awk -F '|' '{print $3}')
    MASTER_FQDN=$(echo $master_data | python -c 'import json,sys;print json.load(sys.stdin)["fqdn"]')
    echo -e "${color_green}+++ MASTER_FQDN is ${MASTER_FQDN} ${color_norm}"
}

# Get minion IP addresses and store in KUBE_MINION_IP_ADDRESSES[]
function detect-minions() {
    KUBE_MINION_IP_ADDRESSES=()
    for (( i=0; i<${#MINION_NAMES[@]}; i++)); do
        local minion_ip=$(nova show --minimal ${MINION_NAMES[$i]} \
          | grep network | awk '{print $5}')
        KUBE_MINION_IP_ADDRESSES+=("${minion_ip}")
        echo "$TAB_PREFIX Detected ${MINION_NAMES[$i]} with IP ${minion_ip}"
    done
    if [ -z "$KUBE_MINION_IP_ADDRESSES" ]; then
        echo -e "${color_red} Could not detect Kubernetes minion nodes. Make sure you've launched a cluster with 'kube-up.sh' ${color_norm}"
        exit 1
    fi
}

# Set MASTER_HTPASSWD
function set-master-htpasswd {
    python "${KUBE_ROOT}/third_party/htpasswd/htpasswd.py" \
    -b -c "${KUBE_TEMP}/htpasswd" "$KUBE_USER" "$KUBE_PASSWORD"
    local htpasswd
    MASTER_HTPASSWD=$(cat "${KUBE_TEMP}/htpasswd")
}


function verify-prereqs {
  # Make sure that prerequisites are installed.
  for x in nova ${SWIFT} cinder openstack; do
    if ! which "$x" >/dev/null; then
      echo -e "${color_red} Can't find $x in PATH, please fix and retry. ${color_norm}"
      exit 1
    fi
  done

  # Mac OS X has swfit programming language, ensure that we are not dealing with it
  version_check=$(${SWIFT} --version)
  if [[ ! ${version_check} =~ .*python-swiftclient.* ]]; then
    echo -e "${color_red} swift does not seem to be the openstack type, please export SWIFT to point at the right binary. ${color_norm}"
    exit 1
  fi

  if [[ -z "${OS_AUTH_URL-}" ]]; then
    echo -e "${color_red} OS_AUTH_URL not set. ${color_norm}"
    echo "  export OS_AUTH_URL=https://os-identity.vip.<az>.ebayc3.com/v2.0/"
    return 1
  fi

  if [[ -z "${OS_TENANT_NAME-}" ]]; then
    echo -e "${color_red} OS_TENANT_NAME not set. ${color_norm}"
    echo "  export OS_TENANT_NAME=<tenantname>"
    return 1
  fi

  if [[ -z "${OS_USERNAME-}" ]]; then
    echo -e "${color_red} OS_USERNAME not set. ${color_norm}"
    echo "  export OS_USERNAME=<username>"
    return 1
  fi

  if [[ -z "${OS_REGION_NAME-}" ]]; then
    echo -e "${color_red} OS_REGION_NAME not set. ${color_norm}"
    echo "  export OS_REGION_NAME=<region_name>"
    return 1
  elif [[ "${OS_REGION_NAME}" != "slc01" ]]; then
    # only enabled atomic image on slc01
    export ATOMIC_NODE="false"
  fi

  if [[ -z "${OS_PASSWORD-}" ]]; then
    echo -e "${color_red} OS_PASSWORD not set. ${color_norm}"
    echo "  export OS_PASSWORD=<password>"
    return 1
  fi

  # Ensure that we have the right cinder client version ?
  cinder_version=$(cinder --version 2>&1 )
  if [[ ${cinder_version} != "1.3.1" ]]; then
      echo -e "${color_red}cinder client version 1.3.1 is needed, found ${cinder_version}, this might not work${color_norm}"
  fi

}

# Create a temp dir that'll be deleted at the end of this bash session.
#
# Vars set:
#   KUBE_TEMP
function ensure-temp-dir {
  if [[ -z ${KUBE_TEMP-} ]]; then
    export KUBE_TEMP=$(mktemp -d -t kubernetes.XXXXXX)
    echo -e "${color_green}+++ KUBE_TEMP=${KUBE_TEMP} ${color_norm}"
    #trap 'rm -rf "${KUBE_TEMP}"' EXIT
  fi
}

function create-master-tess-confs {
    echo "Total masters: $NUM_MASTERS, 1st master: ${MASTER_NAMES[0]}"

    for (( c=0; c<${NUM_MASTERS}; c++ ))
    do
        create-master-tess-conf ${MASTER_NAMES[${c}]}
    done
}

function create-master-tess-conf {
    R_VAR=${OS_REGION_NAME}_EXTERNAL_NET
    EXTERNAL_NET="${!R_VAR}"
    S_VAR=${OS_REGION_NAME}_LB_SUBNET
    LB_SUBNET_ID="${!S_VAR}"
    if [ -z "$1" ]
    then
         echo -e "${color_red} Pass the master name while calling create master tess conf. ${color_norm}"
         exit 1
    fi
    MASTER_NAME=$1
    echo -e "${color_yellow}+++ Provisioning cinder volume for etcd. ${color_norm}"
    local etcd_cinder_volume=$(provision-cinder-volume $1)
    if [[ -z "$etcd_cinder_volume" ]];
    then
        echo -e "${color_red} Unable to provision cinder volume for: $MASTER_NAME; see ${KUBE_TEMP}/$MASTER_NAME-volume_details for failures. ${color_norm}"
        exit 1
    fi
    echo -e "${color_green}+++ Cinder volume created: $etcd_cinder_volume for master $MASTER_NAME ${color_norm}"
    echo -e "${color_yellow}+++ Generating master tess conf. ${color_norm}"
    cat <<EOF >${KUBE_TEMP}/${MASTER_NAME}-tess.conf
{
    "ha": {
        "etcd-cinder-enabled":"${ENABLE_ETCD_CINDER_VOLUME}"
    },
    "network": {
        "bridge": "obr0",
        "device": "eth0",
        "pipework": "/opt/pipework/bin/pipework",
        "ovs_docker": "/usr/local/bin/ovs-docker",
        "container_subnet_prefix": "${MINION_CONTAINER_SUBNET_BASE}.",
        "external_network_id": "${EXTERNAL_NET}",
        "lb_subnet_id": "${LB_SUBNET_ID}"
    },
    "compute": {
        "name": "${MASTER_NAME}-${OS_TENANT_ID}",
        "metafile": "/mnt/config/openstack/latest/meta_data.json"
    },
    "volume": {
        "uuid": "$etcd_cinder_volume"
    },
    "openstack": {
        "identityEndpoint": "${OS_AUTH_URL}",
        "username": "${OS_USERNAME}",
        "password": "${OS_PASSWORD}",
        "tenantId": "${OS_TENANT_ID}",
        "region": "${OS_REGION_NAME}"
    },
    "docker": {
        "socket": "unix:///var/run/docker.sock",
        "backupFile": "${KUBE_TEMP}/${MASTER_NAME}-tess.conf"
    },
    "kube": {
        "authconfig": "/var/lib/kubelet/kubernetes_auth",
        "apiserver": "http://127.0.0.1:8080",
        "hostname": "127.0.0.1"
    }
}
EOF

}

function create-minions-tess-confs {

    R_VAR=${OS_REGION_NAME}_EXTERNAL_NET
    EXTERNAL_NET="${!R_VAR}"
    for (( c=0; c<${NUM_NODES}; c++ ))
    do
        create-minion-tess-conf ${MINION_NAMES[${c}]}
    done

}

function create-minion-tess-conf {

    if [ -z "$1" ]
    then
         echo -e "${color_red} Pass the minion name while calling create minion tess conf. ${color_norm}"
         exit 1
    fi

    MINION_NAME=$1

    echo -e "${color_yellow}+++ Generating minion tess conf. ${color_norm}"
    cat <<EOF >${KUBE_TEMP}/$MINION_NAME-tess.conf
{
    "network": {
        "bridge": "obr0",
        "device": "eth0",
        "pipework": "/opt/pipework/bin/pipework",
        "ovs_docker": "/usr/local/bin/ovs-docker",
        "container_subnet_prefix": "${MINION_CONTAINER_SUBNET_BASE}.",
        "external_network_id": "${EXTERNAL_NET}",
        "public_network_id": ""
    },
    "compute": {
        "name": "$MINION_NAME-${OS_TENANT_ID}",
        "metafile": "/mnt/config/openstack/latest/meta_data.json"
    },
    "openstack": {
        "identityEndpoint": "${OS_AUTH_URL}",
        "username": "${OS_USERNAME}",
        "password": "${OS_PASSWORD}",
        "tenantId": "${OS_TENANT_ID}",
        "region": "${OS_REGION_NAME}"
    },
    "docker": {
        "socket": "unix:///var/run/docker.sock",
        "backupFile": "${KUBE_TEMP}/$MINION_NAME-tess.conf"
    },
    "kube" : {
       "authconfig" : "/var/lib/kubelet/kubernetes_auth",
       "apiserver"  :  "http://${APISERVER_LB_IP}:8080",
       "hostname"  :  "${APISERVER_LB_IP}"
    }
}
EOF

}

function download-tessnet-binary {
    local skipDownloadTessnet=${SKIP_DOWNLOAD_TESSELATE:-false}
    for arg in $@
    do
        if [[ ${arg} == "--skip-download-tessnet=true" ]]
        then
            skipDownloadTessnet=true
            break
        fi
    done

    if ${skipDownloadTessnet}; then
        echo -e "${color_yellow}+++ Skipped downloading tessnet binary! Previously downloaded tessnet will be used. ${color_norm}"
    else
        local tess_binary
        local platform=`uname -s`
        local arch=`uname -m`
        tess_binary=${TESSNET_BINARY_LOCATION}-${platform}-${arch}

        echo -e "${color_yellow}+++ Downloading tessnet binary: ${tess_binary} ${color_norm}"
        curl -s -o tessnet ${tess_binary}
    fi
    chmod 755 tessnet
    pwd=`pwd`
    export PATH=$PATH:$pwd
}


# Verify and find the various tar files that we are going to use on the server.
#
# Vars set:
#   SERVER_BINARY_TAR
#   SALT_TAR
function find-release-tars {
  SERVER_BINARY_TAR="${KUBE_ROOT}/server/kubernetes-server-linux-amd64.tar.gz"
  if [[ ! -f "$SERVER_BINARY_TAR" ]]; then
    SERVER_BINARY_TAR="${KUBE_ROOT}/_output/release-tars/kubernetes-server-linux-amd64.tar.gz"
  fi
  if [[ ! -f "$SERVER_BINARY_TAR" ]]; then
    echo -e "${color_red} Cannot find kubernetes-server-linux-amd64.tar.gz ${color_norm}"
    exit 1
  fi

  SALT_TAR="${KUBE_ROOT}/server/kubernetes-salt.tar.gz"
  if [[ ! -f "$SALT_TAR" ]]; then
    SALT_TAR="${KUBE_ROOT}/_output/release-tars/kubernetes-salt.tar.gz"
  fi
  if [[ ! -f "$SALT_TAR" ]]; then
    echo -e "${color_red} Cannot find kubernetes-salt.tar.gz ${color_norm}"
    exit 1
    echo -e "${color_yellow}release tar files found at $SERVER_BINARY_TAR $SALT_TAR{color_norm}"
  fi
}

function upload-server-tars() {
  local -r staging_bucket=${STAGING_BUCKET:-kuberentes-staging}
  if [[ $staging_bucket == "kuberentes-staging" ]]; then
    STAGING_PATH="${staging_bucket}/devel"
  else
    STAGING_PATH="${staging_bucket}"
  fi
  echo $STAGING_PATH
  ACCOUNT_ID=$(${SWIFT} stat | awk '/ Account: / { print $2 }')
  SERVER_BINARY_TAR_URL=
  SALT_TAR_URL=

  local skipUploadTars=${SKIP_UPLOAD_TARS:-false}
  for arg in $@
  do
    if [[ ${arg} == "--skip-upload-tars=true" ]]
    then
        skipUploadTars=true
        break
    fi
  done
  if ${skipUploadTars}; then
      echo -e "${color_yellow}+++ Skipped uploading build binaries to Swift! Previously uploaded binaries will be used. ${color_norm}"
  else
      # Ensure the bucket is created
      if ! ${SWIFT} list | grep "$staging_bucket" > /dev/null ; then
        echo -e "${color_yellow}+++ Creating $staging_bucket ${color_norm}"
        ${SWIFT} post "${staging_bucket}"
      fi
      echo -e "${color_yellow}+++ Staging binaries to Swift: ${STAGING_PATH} ${color_norm}"
      pushd $(dirname ${SERVER_BINARY_TAR}) > /dev/null
      ${SWIFT} upload $STAGING_PATH "${SERVER_BINARY_TAR##*/}" > /dev/null
      popd > /dev/null
      pushd $(dirname ${SALT_TAR}) > /dev/null
      ${SWIFT} upload $STAGING_PATH "${SALT_TAR##*/}" > /dev/null
      popd > /dev/null
      ${SWIFT} post $staging_bucket -r '.r:*' > /dev/null
  fi

  local server_binary_url="${STAGING_PATH}/${SERVER_BINARY_TAR##*/}"
  local salt_url="${STAGING_PATH}/${SALT_TAR##*/}"
  R_VAR=${OS_REGION_NAME}_SWIFT_ENDPOINT
  SWIFT_ENDPOINT="${!R_VAR}"
  echo "$TAB_PREFIX Swift end point for the binaries: $SWIFT_ENDPOINT"
  SERVER_BINARY_TAR_URL="${SWIFT_ENDPOINT}/${ACCOUNT_ID}/${server_binary_url}"
  SALT_TAR_URL="${SWIFT_ENDPOINT}/${ACCOUNT_ID}/${salt_url}"
  echo "$TAB_PREFIX SERVER_BINARY_TAR_URL=${SERVER_BINARY_TAR_URL}"
  echo "$TAB_PREFIX SALT_TAR_URL=${SALT_TAR_URL}"
}

function scp-tars {
    echo "scping the tars"
    echo "${SERVER_BINARY_TAR}"
    echo "${SALT_TAR##*/}"
    scp -i ~/.ssh/"${SSH_KEY_NAME}" "${SERVER_BINARY_TAR}" "${MASTER_USER}"@"$MASTER_IP":
    scp -i ~/.ssh/"${SSH_KEY_NAME}" "${SALT_TAR}" "${MASTER_USER}"@"$MASTER_IP":
    echo "Done scp ing the server tar"
    echo "Moving the tar to root"
    ssh -i ~/.ssh/"${SSH_KEY_NAME}" "${MASTER_USER}"@"$MASTER_IP" 'sudo mv kubernetes-server-linux-amd64.tar.gz /.'
    echo "moved 1"
    ssh -i ~/.ssh/"${SSH_KEY_NAME}" "${MASTER_USER}"@"$MASTER_IP" 'sudo mv kubernetes-salt.tar.gz /.'
}

function get-password {

  local k8sAuthFile="$HOME/.kubernetes_auth"
  if [[ -r "$k8sAuthFile" ]]; then
    KUBE_USER=$(cat "$k8sAuthFile" | python -c 'import json,sys;print json.load(sys.stdin)["User"]')
    KUBE_PASSWORD=$(cat "$k8sAuthFile" | python -c 'import json,sys;print json.load(sys.stdin)["Password"]')
    return
  fi
  KUBE_USER=admin
  KUBE_PASSWORD=$(python -c 'import string,random; print "".join(random.SystemRandom().choice(string.ascii_letters + string.digits) for _ in range(16))')

  # Store password for reuse.
  cat << EOF > "$k8sAuthFile"
{
  "User": "$KUBE_USER",
  "Password": "$KUBE_PASSWORD"
}
EOF
  chmod 0600 "$k8sAuthFile"

}

function get-ssh-key() {
  if [ ! -f $HOME/.ssh/${SSH_KEY_NAME} ]; then
    echo -e "${color_yellow}+++ Generating SSH KEY ${HOME}/.ssh/${SSH_KEY_NAME} ${color_norm}"
    ssh-keygen -f ${HOME}/.ssh/${SSH_KEY_NAME} -N '' > /dev/null
    upload-credential $HOME/.ssh/${SSH_KEY_NAME}
  fi

  if ! $(nova keypair-list | grep $SSH_KEY_NAME > /dev/null 2>&1); then
    echo -e "${color_yellow}+++ Uploading SSH key to OpenStack with following command: ${color_norm}"
    echo -e "\tnova keypair-add ${SSH_KEY_NAME} --pub-key ${HOME}/.ssh/${SSH_KEY_NAME}.pub"
    nova keypair-add ${SSH_KEY_NAME} --pub-key ${HOME}/.ssh/${SSH_KEY_NAME}.pub > /dev/null
  else
    echo -e "${color_yellow}+++ Found existing SSH key ${SSH_KEY_NAME}.pub ${color_norm}"
  fi
  echo -e "${color_green}+++ SSH_KEY_NAME=${SSH_KEY_NAME} ${color_norm}"
}

function remove-ssh-key() {
    if [ -f $HOME/.ssh/${SSH_KEY_NAME} ]; then
        echo -e "${color_yellow}+++ Deleting SSH KEY ${HOME}/.ssh/${SSH_KEY_NAME} ${color_norm}"
        mv -f ${HOME}/.ssh/${SSH_KEY_NAME} ${HOME}/.ssh/${SSH_KEY_NAME}.${OS_USERNAME}.bkp
    fi
    if [ -f $HOME/.ssh/${SSH_KEY_NAME}.pub ]; then
        echo -e "${color_yellow}+++ Deleting SSH KEY ${HOME}/.ssh/${SSH_KEY_NAME}.pub ${color_norm}"
        mv -f ${HOME}/.ssh/${SSH_KEY_NAME}.pub ${HOME}/.ssh/${SSH_KEY_NAME}.${OS_USERNAME}.pub.bkp
    fi
    if $(nova keypair-list | grep $SSH_KEY_NAME > /dev/null 2>&1); then
        echo -e "${color_yellow}+++ Deleting SSH key from OpenStack with following command: ${color_norm}"
        echo -e "\tnova keypair-delete ${SSH_KEY_NAME}"
        nova keypair-delete ${SSH_KEY_NAME} > /dev/null
    fi
}

# Generate etcd discovery id -- this will work only for dev, will have to be changed for prod
function generate-etcd-discover-id {
  local attempt=0
  local etcd_url="https://discovery.etcd.io/new?size=${NUM_MASTERS}"
  echo -e "${color_yellow}+++ Generating etcd discovery URL using $etcd_url. ${color_norm}"
  while true; do
    export DISCOVERY_URL=$(curl -s $etcd_url)
    if [[ ${DISCOVERY_URL} == *"Unable"* ]]; then
      if (( attempt > 5 )); then
        echo -e "${color_red} Failed to get discovery URL. ${color_norm}"
        exit 2
      fi
      sleep 2
      attempt=$(($attempt+1))
      echo "$TAB_PREFIX Attempt $(($attempt)) to get discovery URL."
    else
      break
    fi
  done

  echo -e "${color_green}+++ ETCD discovery URL: ${DISCOVERY_URL} ${color_norm}"
  echo ${DISCOVERY_URL} > ${KUBE_TEMP}/etcd_discovery
}

# Creates provision script and boots masters
function create-provision-script-and-boot-masters {
    ensure-temp-dir
    generate-etcd-discover-id
    for (( i=0; i<${#MASTER_NAMES[@]}; i++)); do
        create-provision-script-and-boot-master  ${MASTER_NAMES[${i}]}
    done
}

# Generate docker cidr based on subnet passed in.
function generate-docker-cidr {
    if [ -z "$1" ]
    then
        echo -e "${color_red} Pass the /24 docker cidr. ${color_norm}"
        exit 1
    fi
    local docker_cidr=$1
    local MASK=`echo $docker_cidr | awk -F "/" '{print $2}'`
    master_docker_cidr=""
    if [[ $MASK -eq 24 ]] ; then
        local ip=`echo $docker_cidr | awk -F "/" '{print $1}'`
        IFS=. read -r i1 i2 i3 i4 <<< "$ip";
        local master_docker_cidr=`printf "%d.%d.%d.128/27" $i1 $i2 $i3`;
        OBR0_GATEWAY=`printf "%d.%d.%d.1" $i1 $i2 $i3`;
        #echo $OBR0_GATEWAY
    else
        echo -e "${color_red} Failed to reserve IPs for pods. We only support /24 networks to master and nodes now. ${color_norm}"
        exit 1
    fi
    echo $master_docker_cidr $OBR0_GATEWAY
}

function create-provision-script-and-boot-master {
  if [ -z "$1" ]
  then
    echo -e "${color_red} Pass the master name while calling create master script. ${color_norm}"
    exit 1
  fi
  MASTER_NAME=$1
  create-provision-script-for-master $MASTER_NAME
  tessnet-boot-master $MASTER_NAME
}

# Create provision script for the master
function create-provision-script-for-master {
  if [ -z "$1" ]
  then
    echo -e "${color_red} Pass the master name while calling create master script. ${color_norm}"
    exit 1
  fi
  echo -e "${color_yellow}+++ Generating provision script for master node. ${color_norm}"
  MASTER_NAME=$1
  if [ -z "$SALT_MASTER" ];
  then
    SALT_MASTER="$MASTER_NAME"
    echo "$TAB_PREFIX Salt master is: $SALT_MASTER"
  fi

  F_VAR=${OS_REGION_NAME}_EXTERNAL_NET
  FLOATINGIP_NET_ID="${!F_VAR}"
  echo "$TAB_PREFIX Using external network: ${FLOATINGIP_NET_ID} for region ${OS_REGION_NAME}"

  S_VAR=${OS_REGION_NAME}_LB_SUBNET
  LB_SUBNET_ID="${!S_VAR}"
  echo "$TAB_PREFIX Using load balancer subnet: ${LB_SUBNET_ID} for region ${OS_REGION_NAME}"

  # TODO https://github.corp.ebay.com/tess/tess/issues/140
  MASTER_SUBNET=`cat $KUBE_TEMP/$MASTER_NAME-tess.conf | python -c 'import json,sys;print json.load(sys.stdin)["network"]["cidr"]'`
  MASTER_DOCKER_BRIDGE_IP=`cat ${KUBE_TEMP}/$MASTER_NAME-tess.conf | python -c 'import json,sys;print json.load(sys.stdin)["network"]["docker_bridge_ip"]'`
  read MASTER_DOCKER_CIDR OBR0_GATEWAY < <(generate-docker-cidr ${MASTER_SUBNET})
  echo "$TAB_PREFIX Master ${MASTER_NAME} has a cidr: ${MASTER_DOCKER_CIDR} and 0br0 is: $OBR0_GATEWAY"

  (
    echo mkdir -p "/var/lib/tess"
    echo "cat <<EOF >/etc/sysconfig/tess"
    grep -v "^#" "${KUBE_TEMP}/${MASTER_NAME}-tess.conf"
    echo "EOF"
  ) > "${KUBE_TEMP}/create-${MASTER_NAME}-tess-conf.sh"

  if [ $DUAL_NIC = true ]; then
        BRIDGEABLE_DEVICE="eth1"
  else
        BRIDGEABLE_DEVICE="eth0"
  fi

  #issue 877 enable salt master auto-accept with key gpg sign soultion
  if [ "$SALT_MASTER" != "$MASTER_NAME" ]; then
        export SALT_PUB_KEY_CMD=`get-credential-download-cmd ${SALT_PUB_KEY} ${SALT_MINION_PKI}`
        export SALT_SIGN_KEY_CMD=`get-credential-download-cmd ${SALT_PUB_SIGN} ${SALT_MINION_PKI}`
  fi
  (
    echo "#! /bin/bash"
    echo "readonly ATOMIC_NODE='${ATOMIC_NODE}'"
    echo "readonly NODE_INSTANCE_PREFIX='${INSTANCE_PREFIX}-master'"
    echo "readonly SERVER_BINARY_TAR_URL='${SERVER_BINARY_TAR_URL}'"
    echo "readonly SALT_TAR_URL='${SALT_TAR_URL}'"
    echo "readonly MASTER_USER='${MASTER_USER}'"
    echo "readonly MASTER_PASSWD='${MASTER_PASSWD}'"
    echo "readonly MASTER_HTPASSWD='${MASTER_HTPASSWD:-htpasswd}'"
    echo "DOMAIN_SUFFIX=.${OS_REGION_NAME}.$DOMAIN_SUFFIX"
    echo "SERVICE_CLUSTER_IP_RANGE='${SERVICE_CLUSTER_IP_RANGE}'"
    echo "readonly ENABLE_CLUSTER_MONITORING='${ENABLE_CLUSTER_MONITORING:-false}'"
    echo "readonly ENABLE_NODE_MONITORING='${ENABLE_NODE_MONITORING:-false}'"
    echo "readonly GRAFANA_MEMORY_LIMIT_MB='${GRAFANA_MEMORY_LIMIT_MB:-}'"
    echo "readonly HEAPSTER_MEMORY_LIMIT_MB='${HEAPSTER_MEMORY_LIMIT_MB:-}'"
    echo "readonly ALERTMANAGER_MEMORY_LIMIT_MB='${ALERTMANAGER_MEMORY_LIMIT_MB:-}'"
    echo "readonly PROMETHEUS_MEMORY_LIMIT_MB='${PROMETHEUS_MEMORY_LIMIT_MB:-}'"
    echo "readonly PROMETHEUS_MEMORY_CHUNKS='${PROMETHEUS_MEMORY_CHUNKS:-}'"
    echo "readonly PROMETHEUS_RETENTION='${PROMETHEUS_RETENTION:-}'"
    echo "readonly INFLUXDB_MEMORY_LIMIT_MB='${INFLUXDB_MEMORY_LIMIT_MB:-}'"
    echo "readonly ENABLE_CLUSTER_LOGGING='${ENABLE_CLUSTER_LOGGING:-false}'"
    echo "readonly ENABLE_NODE_LOGGING='${ENABLE_NODE_LOGGING:-false}'"
    echo "readonly LOGGING_DESTINATION='${LOGGING_DESTINATION:-}'"
    echo "readonly ELASTICSEARCH_LOGGING_REPLICAS='${ELASTICSEARCH_LOGGING_REPLICAS:-}'"
    echo "readonly ELASTICSEARCH_LOGGING_MASTER_REPLICAS='${ELASTICSEARCH_LOGGING_MASTER_REPLICAS:-}'"
    echo "readonly ELASTICSEARCH_HEAP_SIZE_GB='${ELASTICSEARCH_HEAP_SIZE_GB:-}'"
    echo "readonly ELASTICSEARCH_HOST_PORT='${ELASTICSEARCH_HOST_PORT:-}'"
    echo "readonly ENABLE_CLUSTER_DNS='${ENABLE_CLUSTER_DNS:-false}'"
    echo "readonly DNS_REPLICAS='${DNS_REPLICAS:-}'"
    echo "readonly BRIDGEABLE_DEVICE='${BRIDGEABLE_DEVICE:-}'"
    echo "readonly API_DEVICE='${API_DEVICE:-}'"
    echo "readonly OBR0_GATEWAY='${OBR0_GATEWAY}'"
    echo "readonly DNS_SERVER_IP='${DNS_SERVER_IP:-}'"
    echo "readonly DNS_DOMAIN='${DNS_DOMAIN:-}'"
    echo "readonly OS_AUTH_URL=${OS_AUTH_URL}"
    echo "readonly OS_USERNAME=${OS_USERNAME}"
    echo "readonly OS_PASSWORD=${OS_PASSWORD}"
    echo "readonly OS_TENANT_ID=${OS_TENANT_ID}"
    echo "readonly OS_TENANT_NAME=${OS_TENANT_NAME}"
    echo "readonly FLOATINGIP_NET_ID=${FLOATINGIP_NET_ID}"
    echo "readonly LB_SUBNET_ID=${LB_SUBNET_ID}"
    echo "OS_REGION_NAME='${OS_REGION_NAME}'"
    echo "RUNTIME_CONFIG='${RUNTIME_CONFIG:-}'"
    echo "readonly MASTER_DOCKER_BRIDGE_IP='${MASTER_DOCKER_BRIDGE_IP}'"
    echo "readonly MASTER_DOCKER_CIDR='${MASTER_DOCKER_CIDR}'"
    echo "readonly MASTER_SUBNET='${MASTER_SUBNET}'"
    echo "readonly DISCOVERY_URL='${DISCOVERY_URL:-}'"
    echo "readonly KUBE_MASTER_HA='${KUBE_MASTER_HA}'"
    echo "readonly MASTER_NAME='${MASTER_NAME}'"
    echo "readonly SALT_MASTER='${SALT_MASTER}'"
    echo "readonly SALT_MASTER_FQDN='${SALT_MASTER_FQDN:-}'"
    echo "readonly SALT_MASTER_IP='${SALT_MASTER_IP:-}'"
    echo "readonly SALT_MASTER_PUBLIC_IP='${SALT_MASTER_PUBLIC_IP:-}'"
    echo "readonly CLUSTER_DOMAIN_SUFFIX='${CLUSTER_DOMAIN_SUFFIX:-}'"
    grep -v "^#" "${KUBE_ROOT}/cluster/c3/templates/common.sh"
    if [ $ATOMIC_NODE == "false" ]; then
      grep -v "^#" "${KUBE_ROOT}/cluster/c3/templates/installers.sh"
    fi
    if [ "$SALT_MASTER" = "$MASTER_NAME" ]; then
        echo "readonly IS_SALT_MASTER=true"
        echo "readonly CLUSTER_APISERVER_DNS_NAME='${CLUSTER_APISERVER_DNS_NAME:-}'"
        echo "readonly ENABLE_API_SERVER_LB='${ENABLE_API_SERVER_LB:-false}'"
        echo "readonly APISERVER_PORT='${APISERVER_PORT:-}'"
        grep -v "^#" "${KUBE_ROOT}/cluster/c3/templates/create-dynamic-salt-files.sh"
        grep -v "^#" "${KUBE_ROOT}/cluster/c3/templates/download-release.sh"
    fi
    echo "readonly SALT_PUB_KEY_CMD='${SALT_PUB_KEY_CMD:-}'"
    echo "readonly SALT_SIGN_KEY_CMD='${SALT_SIGN_KEY_CMD:-}'"
    grep -v "^#" "${KUBE_ROOT}/cluster/c3/templates/etcd-mount.sh"
    grep -v "^#" "${KUBE_TEMP}/create-${MASTER_NAME}-tess-conf.sh"
    if [ $ATOMIC_NODE == "true" ]; then
      grep -v "^#" "${KUBE_ROOT}/cluster/c3/templates/salt-master-atomic.sh"
    else
      grep -v "^#" "${KUBE_ROOT}/cluster/c3/templates/salt-master.sh"
    fi
  ) > "${KUBE_TEMP}/${MASTER_NAME}-master-start.sh"

}

# Create provision script for minions
function create-provision-script-for-minions {
  ensure-temp-dir
  for (( i=0; i<${#MINION_NAMES[@]}; i++)); do
    create-provision-script-for-minion  ${MINION_NAMES[${i}]}
  done
}

function create-provision-script-for-minion {

    if [ -z "$1" ]
    then
         echo -e "${color_red} Pass the minion name while calling create minion script. ${color_norm}"
         exit 1
    fi
    echo -e "${color_yellow}+++ Generating provision script for minion node. ${color_norm}"
    MINION_NAME=$1
    (
        echo "cat <<EOF >/etc/sysconfig/tess"
        grep -v "^#" "${KUBE_TEMP}/$MINION_NAME-tess.conf"
        echo "EOF"
    ) > "${KUBE_TEMP}/create-$MINION_NAME-tess-conf.sh"

    MINION_SUBNET=`cat ${KUBE_TEMP}/$MINION_NAME-tess.conf | python -c 'import json,sys;print json.load(sys.stdin)["network"]["cidr"]'`
    MINION_CONTAINER_ADDRS=`cat ${KUBE_TEMP}/$MINION_NAME-tess.conf | python -c 'import json,sys;print json.load(sys.stdin)["network"]["docker_bridge_ip"]'`

    mask=`echo $MINION_SUBNET | awk -F "/" '{print $2}'`
    if [[ $mask -eq 24 ]] ; then
        ip=`echo $MINION_SUBNET | awk -F "/" '{print $1}'`
        IFS=. read -r i1 i2 i3 i4 <<< "$ip";
        DOCKER_FIXED_SUBNET=`printf "%d.%d.%d.128/27" $i1 $i2 $i3`;
        OBR0_GATEWAY=`printf "%d.%d.%d.1" $i1 $i2 $i3`;
    fi

    if [ $DUAL_NIC = true ]; then
        BRIDGEABLE_DEVICE="eth1"
    else
        BRIDGEABLE_DEVICE="eth0"
    fi
    echo "$TAB_PREFIX Salt master is: $SALT_MASTER_FQDN"
    echo "$TAB_PREFIX Minion subnet is: ${MINION_SUBNET}"
    #issue 877 enable salt master auto-accept with key gpg sign soultion
    export SALT_PUB_KEY_CMD=`get-credential-download-cmd ${SALT_PUB_KEY} ${SALT_MINION_PKI}`
    export SALT_SIGN_KEY_CMD=`get-credential-download-cmd ${SALT_PUB_SIGN} ${SALT_MINION_PKI}`
    (
      echo "#! /bin/bash"
      echo "ATOMIC_NODE='${ATOMIC_NODE}'"
      echo "MASTER_NAME='${MASTER_FQDN}'"
      echo "MASTER_IP='${MASTER_IP}'"
      echo "MASTER_USER='${MASTER_USER}'"
      echo "MASTER_FQDN='${MASTER_FQDN}'"
      echo "MASTER_PASSWD='${MASTER_PASSWD}'"
      echo "DOMAIN_SUFFIX=.${OS_REGION_NAME}.$DOMAIN_SUFFIX"
      echo "MINION_CONTAINER_ADDR='${MINION_CONTAINER_ADDRS}'"
      echo "MINION_CONTAINER_SUBNET='${MINION_SUBNET}'"
      echo "DOCKER_FIXED_SUBNET='${DOCKER_FIXED_SUBNET}'"
      echo "readonly OS_AUTH_URL=${OS_AUTH_URL}"
      echo "readonly OS_USERNAME=${OS_USERNAME}"
      echo "readonly OS_PASSWORD=${OS_PASSWORD}"
      echo "readonly OS_TENANT_ID=${OS_TENANT_ID}"
      echo "readonly BRIDGEABLE_DEVICE=${BRIDGEABLE_DEVICE}"
      echo "readonly OBR0_GATEWAY=${OBR0_GATEWAY}"
      echo "DOCKER_OPTS='${EXTRA_DOCKER_OPTS-}'"
      echo "OS_AUTH_URL='${OS_AUTH_URL}'"
      echo "OS_REGION_NAME='${OS_REGION_NAME}'"
      echo "OS_USERNAME='${OS_USERNAME}'"
      echo "OS_TENANT_ID='${OS_TENANT_ID}'"
      echo "OS_PASSWORD='${OS_PASSWORD}'"
      echo "readonly SALT_MASTER='${SALT_MASTER}'"
      echo "readonly SALT_MASTER_FQDN='${SALT_MASTER_FQDN}'"
      echo "readonly SALT_MASTER_IP='${SALT_MASTER_IP}'"
      echo "readonly SALT_MASTER_PUBLIC_IP='${SALT_MASTER_PUBLIC_IP}'"
      echo "readonly CLUSTER_DOMAIN_SUFFIX='${CLUSTER_DOMAIN_SUFFIX:-}'"
      echo "readonly SALT_PUB_KEY_CMD='${SALT_PUB_KEY_CMD:-}'"
      echo "readonly SALT_SIGN_KEY_CMD='${SALT_SIGN_KEY_CMD:-}'"
      if [ $ATOMIC_NODE == "true" ]; then
        grep -v "^#" "${KUBE_ROOT}/cluster/c3/templates/common.sh"
        grep -v "^#" "${KUBE_TEMP}/create-$MINION_NAME-tess-conf.sh"
        grep -v "^#" "${KUBE_ROOT}/cluster/c3/templates/salt-minion-atomic.sh"
      else
        grep -v "^#" "${KUBE_ROOT}/cluster/c3/templates/installers.sh"
        grep -v "^#" "${KUBE_ROOT}/cluster/c3/templates/common.sh"
        grep -v "^#" "${KUBE_TEMP}/create-$MINION_NAME-tess-conf.sh"
        grep -v "^#" "${KUBE_ROOT}/cluster/c3/templates/salt-minion.sh"
      fi
    ) > "${KUBE_TEMP}/$MINION_NAME-start.sh"

}

function tessnet-router-create() {
    TESSNET_CMD="tessnet router-create $1 -c $2"
    echo -e "${color_yellow}+++ Creating router $1 with following command: ${color_norm}"
    echo -e "\t$TESSNET_CMD\n"
    ${TESSNET_CMD}
}

function create-master-routers() {
    for (( c=0; c<${NUM_MASTERS}; c++ ))
    do
        tessnet-router-create kube-router-${OS_TENANT_ID} ${KUBE_TEMP}/${MASTER_NAMES[$c]}-tess.conf
        local ROUTER_ID=$(cat $KUBE_TEMP/${MASTER_NAMES[$c]}-tess.conf | python -c 'import json,sys;print json.load(sys.stdin)["network"]["router_id"]')
        if [[ -z "${ROUTER_ID}" ]]; then
            echo -e "${color_red} Could not create router, check the neutron logs above. Possible issue with neutron API. ${color_norm}"
            exit 1
        fi
    done

}

function update-minions-router-conf {
    echo -e "${color_yellow}+++ Updating router configuration for minions. ${color_norm}"
    for (( c=0; c<${NUM_NODES}; c++ ))
    do
        tessnet-router-create kube-router-${OS_TENANT_ID} ${KUBE_TEMP}/${MINION_NAMES[$c]}-tess.conf
    done
}

function tessnet-bootstrap() {
    local nodeName=$1
    local selectPublicNetwork=$2
    local allowNewRouter=$3
    local dualNic=$4
    if [ $dualNic = true ]; then
        TESSNET_CMD="tessnet bootstrap -c ${KUBE_TEMP}/$nodeName-tess.conf --selectPublicNetwork=$selectPublicNetwork --allowNewRouter=$allowNewRouter"
    else
        TESSNET_CMD="tessnet bootstrap -c ${KUBE_TEMP}/$nodeName-tess.conf"
    fi
    echo -e "${color_yellow}+++ Running tessnet bootstrap for node: $nodeName with following command: ${color_norm}"
    echo -e "\t$TESSNET_CMD\n"
    ${TESSNET_CMD}
}

function tessnet-generate-apikey() {
    TESSNET_CMD="tessnet generate-apikey -c $1"
    echo -e "${color_yellow}+++ Running tessnet generate-apikey with following command: ${color_norm}"
    echo -e "\t$TESSNET_CMD\n"
    ${TESSNET_CMD}
}

function tessnet-master-bootstrap {
    for (( c=0; c<${NUM_MASTERS}; c++ ))
    do
        local allow_new_router="false"
        if [ -z "$SALT_MASTER" ];
        then
            allow_new_router="true"
            echo "$TAB_PREFIX Salt master not set yet; making ${MASTER_NAMES[${c}]} as salt master"
            export SALT_MASTER=${MASTER_NAMES[${c}]}
        fi
        tessnet-bootstrap ${MASTER_NAMES[${c}]} true $allow_new_router $DUAL_NIC

        validate-network ${MASTER_NAMES[${c}]}

        #TODO validate  this actually generated the api key
        tessnet-generate-apikey ${KUBE_TEMP}/${MASTER_NAMES[${c}]}-tess.conf
    done
}

function validate-network {
    if [ -z "$1" ]
    then
         echo -e "${color_red} Pass the master name while calling validate network. ${color_norm}"
         exit 1
    fi
    MASTER_NAME=$1
    echo -e "${color_yellow}+++ Validating network config for: $MASTER_NAME ${color_norm}"
    local NETWORK_ID=$(cat $KUBE_TEMP/${MASTER_NAME}-tess.conf | python -c 'import json,sys;print json.load(sys.stdin)["network"]["network_id"]')
    if [[ -z "${NETWORK_ID}" ]]; then
        echo -e "${color_red} Could not create neutron network, check the neutron logs above. Possible issue with neutron API. ${color_norm}"
        echo -e "${color_red} Did you make sure you're an admin? ${color_norm}"
        exit 1
    fi

    local SUBNET_ID=$(cat $KUBE_TEMP/${MASTER_NAME}-tess.conf | python -c 'import json,sys;print json.load(sys.stdin)["network"]["subnet_id"]')
    if [[ -z "${SUBNET_ID}" ]]; then
        echo -e "${color_red} Could not create subnet, check the neutron logs above. Possible issue with neutron API. ${color_norm}"
        echo -e "${color_red} Did you make sure you're an admin? ${color_norm}"
        exit 1
    fi
    if [ $DUAL_NIC = true ]; then
        PUBLIC_NETWORK_ID=$(cat $KUBE_TEMP/${MASTER_NAME}-tess.conf | python -c 'import json,sys;print json.load(sys.stdin)["network"]["public_network_id"]')
        if [[ -z "${PUBLIC_NETWORK_ID}" ]]; then
            echo -e "${color_red} Could not find a public neutron network, check the neutron logs above. Possible issue with neutron API. ${color_norm}"
            echo -e "${color_red} Did you make sure you're an admin? ${color_norm}"
            exit 1
        fi
    fi
}



function tessnet-minions-bootstrap {
    for (( c=0; c<${NUM_NODES}; c++ ))
    do
        tessnet-bootstrap ${MINION_NAMES[$c]} true false $DUAL_NIC
        tessnet-generate-apikey ${KUBE_TEMP}/${MINION_NAMES[$c]}-tess.conf
    done
}

function tessnet-boot-master {
    if [ -z "$1" ]
    then
         echo -e "${color_red} Pass the master name while calling boot master. ${color_norm}"
         exit 1
    fi
    MASTER_NAME=$1
    local volume_uuid=$(cat $KUBE_TEMP/$MASTER_NAME-tess.conf | python -c 'import json,sys;print json.load(sys.stdin)["volume"]["uuid"]')
    volume_uuid=`echo $volume_uuid | xargs`
    R_VAR=${OS_REGION_NAME}_KUBE_IMAGE
    KUBE_IMAGE="${!R_VAR}"

    local metadata="volume_id=$volume_uuid"
    if [[ "$MASTER_FLEX" == "true" ]]; then
        metadata="$metadata,etcd_server=https://$MASTER_PUBLIC_IP:4001,etcd_cluster_state=existing"
    fi

    # Boot master node using tessnet
    TESS_BOOT_CMD="tessnet node-create ${MASTER_NAME} \
--image=${KUBE_IMAGE} \
--key=${SSH_KEY_NAME} \
--flavor=${KUBE_MASTER_FLAVOR} \
--userdata=${KUBE_TEMP}/${MASTER_NAME}-master-start.sh \
--createFloatingIp=true \
-c ${KUBE_TEMP}/${MASTER_NAME}-tess.conf -m $metadata"
    echo -e "${color_yellow}+++ Booting ${MASTER_NAME} with following command: ${color_norm}"
    echo -e "\t$TESS_BOOT_CMD\n"
    ${TESS_BOOT_CMD}

    # Wait nova to bring master node up
    local attempt=0
    local details="${KUBE_TEMP}/master_details"
    while true; do
        nova show ${MASTER_NAME} > $details
        export MASTER_IP=$(cat $KUBE_TEMP/${MASTER_NAME}-tess.conf | python -c 'import json,sys;print json.load(sys.stdin)["compute"]["public_ip"]')
        if [[ -z "${MASTER_IP}" ]]; then
          if (( attempt > 10 )); then
            echo -e "${color_red} Failed to retrieve master IP. ${color_norm}"
            exit 2
          fi
          echo "$TAB_PREFIX Attempt $(($attempt+1)) to read master IP."
          attempt=$(($attempt+1))
        else
          MASTER_FQDN=$(cat $KUBE_TEMP/${MASTER_NAME}-tess.conf | python -c 'import json,sys;print json.load(sys.stdin)["compute"]["fqdn"]')
          echo -e "${color_green}+++ Master info: ${color_norm}"
          echo -e "${color_green}\tIP: $MASTER_IP ${color_norm}"
          echo -e "${color_green}\tFQDN: $MASTER_FQDN ${color_norm}\n"
          break
        fi
    done

    echo -e "${color_yellow}+++ Validating ${MASTER_NAME} for boot failures. ${color_norm}"
    local PORT_ID=$(cat $KUBE_TEMP/${MASTER_NAME}-tess.conf | python -c 'import json,sys;print json.load(sys.stdin)["compute"]["port_id"]')
    local UUID=$(cat $KUBE_TEMP/${MASTER_NAME}-tess.conf | python -c 'import json,sys;print json.load(sys.stdin)["compute"]["uuid"]')
    if [[ -z "${PORT_ID}" ]]; then
        echo -e "${color_red} Could not boot ${MASTER_NAME}, check the tessnet log above. Possible that the VM went into an error state."
        echo -e "${color_red} Run nova console-log ${UUID} to get more details. ${color_norm}"
        exit 1
    fi

    echo -e "${color_yellow}+++ Validating ${MASTER_NAME} network connectivity. ${color_norm}"
    local FLOATING_IP=$(cat $KUBE_TEMP/${MASTER_NAME}-tess.conf | python -c 'import json,sys;print json.load(sys.stdin)["compute"]["floating_ip"]')
    if [[ -z "${FLOATING_IP}" ]]; then
        echo -e "${color_red} Could not create floating ip for ${MASTER_NAME}, check the tessnet log above. Possible neutron issue."
        echo -e "${color_red} BTW, did you check if you're an admin? ${color_norm}"
        exit 1
    fi

    # Try to ping master node floating IP
    success=false
    for (( ping_count=0; ping_count<10; ping_count++ )); do
        if ping -c 1 $FLOATING_IP >& /dev/null
        then
            success=true
            echo "$TAB_PREFIX Floating IP pingable $FLOATING_IP"
            break
        else
            sleep 2
        fi
    done;

    if [ "${success}" = true ]; then                  # Make final determination.
        echo -e "${color_yellow}+++ Master node is UP and installing Kubernetes binaries. ${color_norm}"
    else
        echo -e "${color_red} Validations failed."
        echo -e "${color_red} Could not ping floating IP ${FLOATING_IP} for ${MASTER_NAME}, check the console logs for a network issue."
        echo -e "${color_red} Run nova console-log ${UUID} to get more details. ${color_norm}"
        exit 1
    fi

    local master_subnet=`cat $KUBE_TEMP/$MASTER_NAME-tess.conf | python -c 'import json,sys;print json.load(sys.stdin)["network"]["cidr"]'`
    echo "$TAB_PREFIX Master $MASTER_NAME has subnet: $master_subnet"
    read master_docker_cidr obr0_gateway < <(generate-docker-cidr ${master_subnet})
    echo "$TAB_PREFIX Master $MASTER_NAME has docker cidr: $master_docker_cidr"

    echo -e "${color_yellow}+++ Updating ${MASTER_NAME} with new IPs for pods with following command: ${color_norm}"
    TESS_PORT_UPDATE_CMD="tessnet pre-create-ips \
--count=32 \
--cidr=${master_docker_cidr} \
-c ${KUBE_TEMP}/${MASTER_NAME}-tess.conf"

    echo -e "\t$TESS_PORT_UPDATE_CMD\n"
    ${TESS_PORT_UPDATE_CMD}
    local API_KEY_ID=$(cat $KUBE_TEMP/${MASTER_NAME}-tess.conf | python -c 'import json,sys;print json.load(sys.stdin)["openstack"]["username"]')
    tessnet update-apikey --apiKeyID=${API_KEY_ID} --ip=${FLOATING_IP} -c $KUBE_TEMP/${MASTER_NAME}-tess.conf
    echo ""
    if [[ -z "$SALT_MASTER_FQDN" ]] || [[ -z "$SALT_MASTER_IP" ]] || [[ -z "$SALT_MASTER_PUBLIC_IP" ]]; then
        export SALT_MASTER_FQDN=`cat $KUBE_TEMP/$SALT_MASTER-tess.conf | python -c 'import json,sys;print json.load(sys.stdin)["compute"]["fqdn"]'`
        export SALT_MASTER_IP=`cat $KUBE_TEMP/$SALT_MASTER-tess.conf | python -c 'import json,sys;print json.load(sys.stdin)["compute"]["ip"]'`
        export SALT_MASTER_PUBLIC_IP=`cat $KUBE_TEMP/$SALT_MASTER-tess.conf | python -c 'import json,sys;print json.load(sys.stdin)["compute"]["public_ip"]'`
        echo -e "${color_green}+++ Salt master info: ${color_norm}"
        echo -e "${color_green}\tIP: $SALT_MASTER_IP ${color_norm}"
        echo -e "${color_green}\tPublic IP: $SALT_MASTER_PUBLIC_IP ${color_norm}"
        echo -e "${color_green}\tFQDN: $SALT_MASTER_FQDN ${color_norm}\n"
    fi
    master-attach-volume ${MASTER_NAME}

    #issue 877 enable salt master auto-accept with key gpg sign soultion
    if [ "$SALT_MASTER" = "$MASTER_NAME" ]; then
        echo -e "${color_yellow}+++ Waiting extra time for salt master being ready  ${color_norm}"
        local attempt=0
        while true; do
          if (( attempt > 15 )); then
                echo -e "${color_red} Failed to find the salt master public key on swift ${color_norm}"
                exit 2
          fi
          SALT_PUB_SIGN="master_sign.pub"
          attempt=$(($attempt+1))
          if ssh -o stricthostkeychecking=no -i ~/.ssh/"${SSH_KEY_NAME}" "${MASTER_USER}"@"$MASTER_IP" stat "/tmp/${ETCD_KEY}" \> /dev/null 2\>\&1; then
             scp -o stricthostkeychecking=no -i ~/.ssh/"${SSH_KEY_NAME}" "${MASTER_USER}"@"$MASTER_IP":"/tmp/${CLUSTER_CA}" "${KUBE_TEMP}/"
             scp -o stricthostkeychecking=no -i ~/.ssh/"${SSH_KEY_NAME}" "${MASTER_USER}"@"$MASTER_IP":"/tmp/${APISERVER_KEY}" "${KUBE_TEMP}/"
             scp -o stricthostkeychecking=no -i ~/.ssh/"${SSH_KEY_NAME}" "${MASTER_USER}"@"$MASTER_IP":"/tmp/${APISERVER_CRT}" "${KUBE_TEMP}/"
             scp -o stricthostkeychecking=no -i ~/.ssh/"${SSH_KEY_NAME}" "${MASTER_USER}"@"$MASTER_IP":"/tmp/${ETCD_KEY}" "${KUBE_TEMP}/"
             scp -o stricthostkeychecking=no -i ~/.ssh/"${SSH_KEY_NAME}" "${MASTER_USER}"@"$MASTER_IP":"/tmp/${ETCD_CRT}" "${KUBE_TEMP}/"
             scp -o stricthostkeychecking=no -i ~/.ssh/"${SSH_KEY_NAME}" "${MASTER_USER}"@"$MASTER_IP":"/tmp/${SALT_PRI_KEY}" "${KUBE_TEMP}/"
             scp -o stricthostkeychecking=no -i ~/.ssh/"${SSH_KEY_NAME}" "${MASTER_USER}"@"$MASTER_IP":"/tmp/${SALT_PUB_KEY}" "${KUBE_TEMP}/"
             scp -o stricthostkeychecking=no -i ~/.ssh/"${SSH_KEY_NAME}" "${MASTER_USER}"@"$MASTER_IP":"/tmp/${SALT_PRI_SIGN}" "${KUBE_TEMP}/"
             scp -o stricthostkeychecking=no -i ~/.ssh/"${SSH_KEY_NAME}" "${MASTER_USER}"@"$MASTER_IP":"/tmp/${SALT_PUB_SIGN}" "${KUBE_TEMP}/"
             pushd "${KUBE_TEMP}/"
             upload-credential ${CLUSTER_CA} ${APISERVER_KEY} ${APISERVER_CRT} ${ETCD_KEY} ${ETCD_CRT} ${SALT_PRI_KEY}  ${SALT_PUB_KEY} ${SALT_PRI_SIGN} ${SALT_PUB_SIGN}
             rm -rf   ${CLUSTER_CA} ${APISERVER_KEY} ${APISERVER_CRT} ${ETCD_KEY} ${ETCD_CRT} ${SALT_PRI_KEY}  ${SALT_PUB_KEY} ${SALT_PRI_SIGN} ${SALT_PUB_SIGN}
             popd
             break
          else
            sleep 60
          fi
        done
    fi
}

function tessnet-boot-minions {
    for (( c=0; c<${NUM_NODES}; c++ ))
    do
        tessnet-boot-minion ${MINION_NAMES[${c}]}
    done
}

function tessnet-boot-minion {

    if [ -z "$1" ]
    then
         echo -e "${color_red} Pass the minion name while calling boot minion. ${color_norm}"
         exit 1
    fi

    MINION_NAME=$1
    R_VAR=${OS_REGION_NAME}_KUBE_IMAGE
    KUBE_IMAGE="${!R_VAR}"
    TESS_BOOT_CMD="tessnet node-create ${MINION_NAME} \
--image=${KUBE_IMAGE} \
--key=${SSH_KEY_NAME} \
--flavor=${KUBE_MINION_FLAVOR}  \
--userdata=${KUBE_TEMP}/${MINION_NAME}-start.sh \
--createFloatingIp=true \
-c ${KUBE_TEMP}/${MINION_NAME}-tess.conf"
    echo -e "${color_yellow}+++ Booting ${MINION_NAME} with following command: ${color_norm}"
    echo -e "\t$TESS_BOOT_CMD\n"
    ${TESS_BOOT_CMD}

    # TODO Make other ranges possible https://github.corp.ebay.com/tess/tess/issues/140
    MINION_SUBNET=`cat $KUBE_TEMP/${MINION_NAME}-tess.conf | python -c 'import json,sys;print json.load(sys.stdin)["network"]["cidr"]'`
    local MASK=`echo $MINION_SUBNET | awk -F "/" '{print $2}'`
    if [[ $MASK -eq 24 ]]; then
        local ip=`echo $MINION_SUBNET | awk -F "/" '{print $1}'`
        IFS=. read -r i1 i2 i3 i4 <<< "$ip";
        local CIDR=`printf "%d.%d.%d.128/27" $i1 $i2 $i3`;
    else
        echo -e "${color_red} Failed to reserve IPs for pods for the minion. We only support /24 networks to master and nodes now. ${color_norm}"
        exit 1
    fi

    echo -e "${color_yellow}+++ Updating ${MINION_NAME} with new IPs for pods with following commands: ${color_norm}"
    TESS_PORT_UPDATE_CMD="tessnet pre-create-ips \
--count=32 \
--cidr=${CIDR} \
-c ${KUBE_TEMP}/${MINION_NAME}-tess.conf"

    echo -e "\t$TESS_PORT_UPDATE_CMD\n"
    ${TESS_PORT_UPDATE_CMD}

    local FLOATING_IP=$(cat ${KUBE_TEMP}/${MINION_NAME}-tess.conf | python -c 'import json,sys;print json.load(sys.stdin).get("compute").get("floating_ip")')
    local API_KEY_ID=$(cat ${KUBE_TEMP}/${MINION_NAME}-tess.conf | python -c 'import json,sys;print json.load(sys.stdin)["openstack"]["username"]')
    if [[ ! -z "${FLOATING_IP}" ]]; then
      tessnet update-apikey --apiKeyID=${API_KEY_ID} --ip=${FLOATING_IP} -c ${KUBE_TEMP}/${MINION_NAME}-tess.conf
    fi

#    local minion_fqdn=$(cat $KUBE_TEMP/${MINION_NAME}-tess.conf | python -c 'import json,sys;print json.load(sys.stdin)["compute"]["fqdn"]')
#    if [ ! -z $minion_fqdn ]; then
#        long-sleep 90
#        accept-minion-key ${SALT_MASTER_PUBLIC_IP} ${SALT_MASTER_FQDN} ${minion_fqdn}
#    fi
}

# This function is vagrant centric; needs to be ported to tess
function verify-cluster {
  echo "Each machine instance has been created/updated."
  echo "  Now waiting for the Salt provisioning process to complete on each machine."
  echo "  This can take some time based on your network, disk, and CPU speed."
  echo "  It is possible for an error to occur during Salt provision of cluster and this could loop forever."

  # verify master has all required daemons
  echo -e "${color_yellow}+++ Validating master. ${color_norm}"
  local machine="master"
  local -a required_daemon=("salt-master" "salt-minion" "kube-apiserver" "nginx" "kube-controller-manager" "kube-scheduler")
  local validated="1"
  until [[ "$validated" == "0" ]]; do
    validated="0"
    local daemon
    for daemon in "${required_daemon[@]}"; do
      vagrant ssh "$machine" -c "which '${daemon}'" >/dev/null 2>&1 || {
        printf "."
        validated="1"
        sleep 2
      }
    done
  done

  # verify each minion has all required daemons
  local i
  for (( i=0; i<${#MINION_NAMES[@]}; i++)); do
    echo -e "${color_yellow}+++ Validating ${VAGRANT_MINION_NAMES[$i]} ${color_norm}"
    local machine=${VAGRANT_MINION_NAMES[$i]}
    local -a required_daemon=("salt-minion" "kubelet" "docker")
    local validated="1"
    until [[ "$validated" == "0" ]]; do
      validated="0"
      local daemon
      for daemon in "${required_daemon[@]}"; do
        vagrant ssh "$machine" -c "which $daemon" >/dev/null 2>&1 || {
          printf "."
          validated="1"
          sleep 2
        }
      done
    done
  done

  echo
  echo -e "${color_yellow}+++ Waiting for each minion to be registered with cloud provider. ${color_norm}"
  for (( i=0; i<${#MINION_IPS[@]}; i++)); do
    local machine="${MINION_IPS[$i]}"
    local count="0"
    until [[ "$count" == "1" ]]; do
      local minions
      minions=$("${KUBE_ROOT}/cluster/kubectl.sh" get minions -o template -t '{{range.items}}{{.id}}:{{end}}')
      count=$(echo $minions | grep -c "${MINION_IPS[i]}") || {
        printf "."
        sleep 2
        count="0"
      }
    done
  done

  (
    echo
    echo "  Kubernetes cluster is running. The master is running at:"
    echo
    echo "    https://${MASTER_IP}"
    echo
    echo "  The user name and password to use is located in ~/.kubernetes_vagrant_auth."
    echo
    )
}

function welcome {
  echo ""
  str="Welcome to Kubernetes setup, powered by Tess.io"
  len=$((${#str}+4))
  for i in $(seq $len); do echo -ne "${color_green}*${color_norm}"; done;
  echo; echo -e "${color_yellow}* "$str" *";
  for i in $(seq $len); do echo -ne "${color_green}*${color_norm}"; done;
  echo
  echo ""
}

function print-cluster-info() {
  export KUBERNETES_MASTER=http://$1:8080

  echo
  echo "  All cluster nodes may not be online yet, this is okay."
  echo "  Kubernetes cluster is running. Here are the details:"
  echo
  ${KUBE_ROOT}/cluster/kubectl.sh --server=http://$1:8080 cluster-info
  echo
  echo "  To use it either do:"
  echo "    export KUBERNETES_MASTER=http://$1:8080"
  echo
  echo "  Or "
  echo "    cluster/kubectl.sh config set-cluster <current-cluster-name> --server=http://$1:8080"
  echo
  echo "  The user name and password to use is located in ~/.kubernetes_auth."
  echo "  Have fun !!"
  echo
}

#issue #804 store api/etcd keys to swift/esam
function check-cluster-credentials {
    if ! check-credential-bucket ; then
       echo -e "${color_red} Kubernetes cluster ${DOMAIN_SUFFIX} bucket already existed in swift. Please 'kube-down' to clear old credentials."
       exit 1
    fi
}

# Instantiate a kubernetes cluster
function kube-up {
  welcome
  check-cluster-credentials
  download-tessnet-binary $@
  find-release-tars
  upload-server-tars $@
  ensure-temp-dir
  get-password
  get-ssh-key

  #provision-cinder-volume
  create-master-tess-confs
  create-master-routers
  tessnet-master-bootstrap
  # This will create scripts and also boot the master
  create-provision-script-and-boot-masters

  validate-apiserver-vip

  #master-attach-volume
  create-minions-tess-confs
  update-minions-router-conf
  tessnet-minions-bootstrap
  create-provision-script-for-minions
  tessnet-boot-minions

  # TODO change this to create a vip and add all masters as members
  #master_floatingip=$(cat $KUBE_TEMP/kubernetes-master-tess.conf | python -c 'import json,sys;print json.load(sys.stdin)["compute"]["floating_ip"]')
  #master_fqdn=$(cat $KUBE_TEMP/kubernetes-master-tess.conf | python -c 'import json,sys;print json.load(sys.stdin)["compute"]["fqdn"]')
  export KUBE_MASTER_IP=${APISERVER_LB_IP}

  detect-master

  echo "  Waiting for cluster initialization."
  echo
  echo "  This will continually check to see if the API for Kubernetes is reachable."
  echo "  This might loop forever if there was some uncaught error during start up."
  echo

  clusterCreated=true
  start=$SECONDS
  #This will fail until apiserver salt is updated
  until $(curl --insecure --user ${KUBE_USER}:${KUBE_PASSWORD} --max-time 5 \
          --fail --output /dev/null --silent http://${KUBE_MASTER_IP}:8080/api/v1/pods); do
      printf "."
      sleep 2
      duration=$(( SECONDS - start ))
      if [ $duration -gt 600 ]; then
        clusterCreated=false
        break
      fi
  done

  if [ $clusterCreated = false ]; then
    echo
    echo -e "${color_red} Kubernetes cluster failed to be created in 10 minutes. Please check detailed log or use 'kube-down' to clean up allocated resources. ${color_norm}"
    exit 1
  fi

  echo
  echo -e "${color_green}+++ Kubernetes cluster created. ${color_norm}\n"

  # Don't bail on errors, we want to be able to print some info.
  set +e

  detect-minions
  print-cluster-info ${KUBE_MASTER_IP}
}

function create-dnsrecords {
    if [ -z "$KUBE_TEMP" ]; then
        echo -e "${color_red} KUBE_TEMP not set; required to find config files. ${color_norm}"
        exit 1
    fi

    master_floatingip=$(cat $KUBE_TEMP/kubernetes-master-tess.conf | python -c 'import json,sys;print json.load(sys.stdin)["compute"]["floating_ip"]')
    master_fqdn=$(cat $KUBE_TEMP/kubernetes-master-tess.conf | python -c 'import json,sys;print json.load(sys.stdin)["compute"]["fqdn"]')

    curl -X POST --header "Content-Type:application/json" --header "Accept:application/json" -d '{"fqdn":"'${master_fqdn}'", "ip":"'${master_floatingip}'"}' http://cmiaas.vip.ebay.com/dnsproxy/v1/records/aptr
    echo -e "${color_green}+++ Successfully created DNS records for $master_fqdn:$master_floatingip ${color_norm}"

    for (( c=1; c<=${NUM_NODES}; c++ ));do
        minion_floatingip=$(cat $KUBE_TEMP/kubernetes-minion-$c-tess.conf | python -c 'import json,sys;print json.load(sys.stdin)["compute"]["floating_ip"]')
        minion_fqdn=$(cat $KUBE_TEMP/kubernetes-minion-$c-tess.conf | python -c 'import json,sys;print json.load(sys.stdin)["compute"]["fqdn"]')
        curl -X POST --header "Content-Type:application/json" --header "Accept:application/json" -d '{"fqdn":"'${minion_fqdn}'", "ip":"'${minion_floatingip}'"}' http://cmiaas.vip.ebay.com/dnsproxy/v1/records/aptr
        echo -e "${color_green}+++ Successfully created DNS records for $minion_fqdn:$minion_floatingip ${color_norm}"
    done
}

# Delete a kubernetes cluster
function kube-down {
  for master in `nova list |  cut -d "|" -f3 | grep ${MASTER_NAME}`
  do
    master-detach-volume $master $@
  done
  download-tessnet-binary $@
  echo -e "${color_yellow}+++ Tear down cluster with following command: ${color_norm}"
  TESSNET_CMD="tessnet teardown-cluster --skipValidations=true"
  echo -e "\t$TESSNET_CMD\n"
  ${TESSNET_CMD}

  for arg in $@
  do
    if [[ ${arg} == "--remove-ssh-key=true" ]]
    then
      remove-ssh-key
      break
    fi
  done
  # issue #694 for store keys to esam and swift.
  delete-credential
}

# Update a kubernetes cluster with latest source
function kube-push {
  # find kube-nodes before push upgrade
  nodes_status=$("${KUBE_ROOT}/cluster/kubectl.sh" get nodes -o template --template='{{range .items}}{{with index .status.conditions 0}}{{.type}}:{{.status}},{{end}}{{end}}' --api-version=v1) || true
  found=$(echo "${nodes_status}" | tr "," "\n" | grep -c 'Ready:') || true
  ready=$(echo "${nodes_status}" | tr "," "\n" | grep -c 'Ready:True') || true
  if (( $found != $ready )); then
    while true; do
      read -p "Only $ready out of $found nodes are in ready state. Do you want to continue? (y/n)  " yn
      case $yn in
        [Yy]* ) break;;
        [Nn]* ) exit;;
        * ) echo "Please answer y(yes) or n(no).";;
      esac
    done
  fi
  export NUM_NODES=$found # reset NUM_NODES to current cluster's minion num

  detect-master
  ensure-temp-dir
  get-password
  detect-master-hostname
  set-master-htpasswd
  # Make sure we have the tar files staged on Google Storage
  find-release-tars
  upload-server-tars $@

  if [ $DUAL_NIC = true ]; then
    BRIDGEABLE_DEVICE="eth1"
  else
    BRIDGEABLE_DEVICE="eth0"
  fi

  (
    echo "#! /bin/bash"
    echo "cd /"
    echo "echo Executing configuration"
    echo "readonly SERVER_BINARY_TAR_URL='${SERVER_BINARY_TAR_URL}'"
    echo "readonly SALT_TAR_URL='${SALT_TAR_URL}'"
    echo "readonly NODE_INSTANCE_PREFIX='${INSTANCE_PREFIX}-minion'"
    echo "readonly MASTER_USER='${MASTER_USER}'"
    echo "readonly MASTER_PASSWD='${MASTER_PASSWD}'"
    echo "readonly MASTER_HTPASSWD='${MASTER_HTPASSWD}'"
    echo "readonly SERVICE_CLUSTER_IP_RANGE='${SERVICE_CLUSTER_IP_RANGE}'"
    echo "readonly ENABLE_CLUSTER_MONITORING='${ENABLE_CLUSTER_MONITORING:-false}'"
    echo "readonly ENABLE_NODE_MONITORING='${ENABLE_NODE_MONITORING:-false}'"
    echo "readonly GRAFANA_MEMORY_LIMIT_MB='${GRAFANA_MEMORY_LIMIT_MB:-}'"
    echo "readonly HEAPSTER_MEMORY_LIMIT_MB='${HEAPSTER_MEMORY_LIMIT_MB:-}'"
    echo "readonly ALERTMANAGER_MEMORY_LIMIT_MB='${ALERTMANAGER_MEMORY_LIMIT_MB:-}'"
    echo "readonly PROMETHEUS_MEMORY_LIMIT_MB='${PROMETHEUS_MEMORY_LIMIT_MB:-}'"
    echo "readonly PROMETHEUS_MEMORY_CHUNKS='${PROMETHEUS_MEMORY_CHUNKS:-}'"
    echo "readonly PROMETHEUS_RETENTION='${PROMETHEUS_RETENTION:-}'"
    echo "readonly INFLUXDB_MEMORY_LIMIT_MB='${INFLUXDB_MEMORY_LIMIT_MB:-}'"
    echo "readonly ENABLE_CLUSTER_LOGGING='${ENABLE_CLUSTER_LOGGING:-false}'"
    echo "readonly ENABLE_NODE_LOGGING='${ENABLE_NODE_LOGGING:-false}'"
    echo "readonly LOGGING_DESTINATION='${LOGGING_DESTINATION:-}'"
    echo "readonly ELASTICSEARCH_LOGGING_REPLICAS='${ELASTICSEARCH_LOGGING_REPLICAS:-}'"
    echo "readonly ELASTICSEARCH_LOGGING_MASTER_REPLICAS='${ELASTICSEARCH_LOGGING_MASTER_REPLICAS:-}'"
    echo "readonly ELASTICSEARCH_HEAP_SIZE_GB='${ELASTICSEARCH_HEAP_SIZE_GB:-}'"
    echo "readonly ELASTICSEARCH_HOST_PORT='${ELASTICSEARCH_HOST_PORT:-}'"
    echo "readonly OS_TENANT_NAME=${OS_TENANT_NAME}"
    echo "readonly ENABLE_CLUSTER_DNS='${ENABLE_CLUSTER_DNS:-false}'"
    echo "readonly BRIDGEABLE_DEVICE='${BRIDGEABLE_DEVICE:-}'"
    echo "readonly DNS_REPLICAS='${DNS_REPLICAS:-}'"
    echo "readonly DNS_SERVER_IP='${DNS_SERVER_IP:-}'"
    echo "readonly DNS_DOMAIN='${DNS_DOMAIN:-}'"
    echo "RUNTIME_CONFIG='${RUNTIME_CONFIG:-}'"
    grep -v "^#" "${KUBE_ROOT}/cluster/c3/templates/installers.sh"
    grep -v "^#" "${KUBE_ROOT}/cluster/c3/templates/common.sh"
    grep -v "^#" "${KUBE_ROOT}/cluster/c3/templates/download-release.sh"
    echo "salt '*' mine.update"
    # set the sequence of applying salt state. salt-master needs doing something first, then the rest roles.
    echo "salt --force-color -G 'roles:salt-master' state.highstate"
    echo "salt --force-color '*' state.highstate"
  ) > kube-push-master.sh

  echo -e "${color_yellow}+++ Starting to execute kube-push script. ${color_norm}"
  ssh -i ~/.ssh/"${SSH_KEY_NAME}" "${MASTER_USER}"@"$MASTER_IP" 'sudo bash -s' < kube-push-master.sh
  echo "$TAB_PREFIX Done executing kube-push script."
  rm kube-push-master.sh

  echo "  Master FQDN ${MASTER_FQDN}"
  echo
  echo "  Kubernetes cluster is running. The master is running at:"
  echo
  echo "    https://${KUBE_MASTER_IP}"
  echo
  echo "  The user name and password to use is located in ~/.kubernetes_auth."
  echo
}

function kube-push-scp {
  detect-master
  ensure-temp-dir
  get-password
  detect-master-hostname
  set-master-htpasswd
  # Make sure we have the tar files staged on Google Storage
  find-release-tars
  # upload-server-tars
  scp-tars

  if [ $DUAL_NIC = true ]; then
    BRIDGEABLE_DEVICE="eth1"
  else
    BRIDGEABLE_DEVICE="eth0"
  fi

  (
    echo "#! /bin/bash"
    echo "cd /"
    echo "echo Executing configuration"
    echo "readonly SERVER_BINARY_TAR_URL='${SERVER_BINARY_TAR}'"
    echo "readonly SALT_TAR_URL='${SALT_TAR}'"
    echo "readonly NODE_INSTANCE_PREFIX='${INSTANCE_PREFIX}-minion'"
    echo "readonly MASTER_USER='${MASTER_USER}'"
    echo "readonly MASTER_PASSWD='${MASTER_PASSWD}'"
    echo "readonly MASTER_HTPASSWD='${MASTER_HTPASSWD}'"
    echo "SERVICE_CLUSTER_IP_RANGE='${SERVICE_CLUSTER_IP_RANGE}'"
    echo "readonly ENABLE_CLUSTER_MONITORING='${ENABLE_CLUSTER_MONITORING:-false}'"
    echo "readonly ENABLE_NODE_MONITORING='${ENABLE_NODE_MONITORING:-false}'"
    echo "readonly GRAFANA_MEMORY_LIMIT_MB='${GRAFANA_MEMORY_LIMIT_MB:-}'"
    echo "readonly HEAPSTER_MEMORY_LIMIT_MB='${HEAPSTER_MEMORY_LIMIT_MB:-}'"
    echo "readonly ALERTMANAGER_MEMORY_LIMIT_MB='${ALERTMANAGER_MEMORY_LIMIT_MB:-}'"
    echo "readonly PROMETHEUS_MEMORY_LIMIT_MB='${PROMETHEUS_MEMORY_LIMIT_MB:-}'"
    echo "readonly PROMETHEUS_MEMORY_CHUNKS='${PROMETHEUS_MEMORY_CHUNKS:-}'"
    echo "readonly PROMETHEUS_RETENTION='${PROMETHEUS_RETENTION:-}'"
    echo "readonly INFLUXDB_MEMORY_LIMIT_MB='${INFLUXDB_MEMORY_LIMIT_MB:-}'"
    echo "readonly ENABLE_CLUSTER_LOGGING='${ENABLE_CLUSTER_LOGGING:-false}'"
    echo "readonly ENABLE_NODE_LOGGING='${ENABLE_NODE_LOGGING:-false}'"
    echo "readonly LOGGING_DESTINATION='${LOGGING_DESTINATION:-}'"
    echo "readonly ELASTICSEARCH_LOGGING_REPLICAS='${ELASTICSEARCH_LOGGING_REPLICAS:-}'"
    echo "readonly ELASTICSEARCH_LOGGING_MASTER_REPLICAS='${ELASTICSEARCH_LOGGING_MASTER_REPLICAS:-}'"
    echo "readonly ELASTICSEARCH_HEAP_SIZE_GB='${ELASTICSEARCH_HEAP_SIZE_GB:-}'"
    echo "readonly ELASTICSEARCH_HOST_PORT='${ELASTICSEARCH_HOST_PORT:-}'"
    echo "readonly OS_TENANT_NAME=${OS_TENANT_NAME}"
    echo "readonly ENABLE_CLUSTER_DNS='${ENABLE_CLUSTER_DNS:-false}'"
    echo "readonly BRIDGEABLE_DEVICE='${BRIDGEABLE_DEVICE:-}'"
    echo "readonly DNS_REPLICAS='${DNS_REPLICAS:-}'"
    echo "readonly DNS_SERVER_IP='${DNS_SERVER_IP:-}'"
    echo "readonly DNS_DOMAIN='${DNS_DOMAIN:-}'"
    echo "RUNTIME_CONFIG='${RUNTIME_CONFIG:-}'"
    grep -v "^#" "${KUBE_ROOT}/cluster/c3/templates/installers.sh"
    grep -v "^#" "${KUBE_ROOT}/cluster/c3/templates/common.sh"
    grep -v "^#" "${KUBE_ROOT}/cluster/c3/templates/release.sh"
    echo "salt '*' mine.update"
    # set the sequence of applying salt state. salt-master needs doing something first, then the rest roles.
    echo "salt --force-color -G 'roles:salt-master' state.highstate"
    echo "salt --force-color '*' state.highstate"
  ) > kube-push-master.sh

  echo -e "${color_yellow}+++ Starting to execute kube-push script. ${color_norm}"
  ssh -i ~/.ssh/"${SSH_KEY_NAME}" "${MASTER_USER}"@"$MASTER_IP" 'sudo bash -s' < kube-push-master.sh
  echo "$TAB_PREFIX Done executing kube-push script."
  #rm kube-push-master.sh

  echo "  Master FQDN ${MASTER_FQDN}"
  echo
  echo "  Kubernetes cluster is running. The master is running at:"
  echo
  echo "    https://${KUBE_MASTER_IP}"
  echo
  echo "  The user name and password to use is located in ~/.kubernetes_auth."
  echo
}

function kube-flex {
    if [ $# -lt 1 ]; then
        echo -e "${color_red} Illegal number of parameters to kube flex. ${color_norm}"
        exit 1
    fi
    export SALT_MASTER_FQDN=${MASTER_FQDN}
    export SALT_MASTER_IP=${MASTER_IP}
    export SALT_MASTER_PUBLIC_IP=${MASTER_PUBLIC_IP}
    export SALT_MASTER=${CURRENT_SALT_MASTER}
    echo -e "${color_green}+++ Master info: ${color_norm}"
    echo -e "${color_green}\tIP: $SALT_MASTER_IP ${color_norm}"
    echo -e "${color_green}\tPublic IP: $SALT_MASTER_PUBLIC_IP ${color_norm}"
    echo -e "${color_green}\tFQDN: $SALT_MASTER_FQDN ${color_norm}"
    echo -e "${color_green}\tCurrent salt master: $SALT_MASTER ${color_norm}"

    download-tessnet-binary $@
    #TODO check for master_ip and master_fqdn env variables
    detect-master
    ensure-temp-dir
    get-password
    # Detect the 1st master node
    detect-master-hostname
    set-master-htpasswd
    # Make sure we have the tar files staged on Swift Storage
    find-release-tars
    upload-server-tars $@
    # This is required to salt-master in master.conf
    args=("$@")
    minion_count=$#
    R_VAR=${OS_REGION_NAME}_EXTERNAL_NET
    EXTERNAL_NET="${!R_VAR}"
    for (( c=1; c<$minion_count; c++ ))
    do
        if [[ ${args[${c}]} == --* ]]; then
            continue
        fi
        create-minion-tess-conf ${args[${c}]}
        tessnet-router-create kube-router-${OS_TENANT_ID} ${KUBE_TEMP}/${args[${c}]}-tess.conf
        tessnet-bootstrap ${args[${c}]} true false true
        tessnet-generate-apikey ${KUBE_TEMP}/${args[${c}]}-tess.conf
        create-provision-script-for-minion ${args[${c}]}
        tessnet-boot-minion ${args[${c}]}
    done

    print-cluster-info ${MASTER_PUBLIC_IP}
}

function kube-master-flex {
    if [ $# -lt 1 ]; then
        echo -e "${color_red} Illegal number of parameters to kube master flex. ${color_norm}"
        exit 1
    fi
    export SALT_MASTER_FQDN=${MASTER_FQDN}
    export SALT_MASTER_IP=${MASTER_IP}
    export SALT_MASTER_PUBLIC_IP=${MASTER_PUBLIC_IP}
    export SALT_MASTER=${CURRENT_SALT_MASTER}
    echo -e "${color_green}+++ Master info: ${color_norm}"
    echo -e "${color_green}\tIP: $SALT_MASTER_IP ${color_norm}"
    echo -e "${color_green}\tPublic IP: $SALT_MASTER_PUBLIC_IP ${color_norm}"
    echo -e "${color_green}\tFQDN: $SALT_MASTER_FQDN ${color_norm}"
    echo -e "${color_green}\tCurrent salt master: $SALT_MASTER ${color_norm}\n"

    download-tessnet-binary $@
    #TODO check for master_ip and master_fqdn env variables
    detect-master
    ensure-temp-dir
    get-password
    # Detect the 1st master node
    detect-master-hostname
    set-master-htpasswd
    # Make sure we have the tar files staged on Swift Storage
    find-release-tars
    upload-server-tars $@
    # This is required to salt-master in master.conf

    export MASTER_FLEX="true"
    args=("$@")
    R_VAR=${OS_REGION_NAME}_EXTERNAL_NET
    EXTERNAL_NET="${!R_VAR}"
    MASTER_NAME=${args[1]}
    create-master-tess-conf ${MASTER_NAME}
    tessnet-router-create kube-router-${OS_TENANT_ID} ${KUBE_TEMP}/${MASTER_NAME}-tess.conf
    local ROUTER_ID=$(cat $KUBE_TEMP/${args[1]}-tess.conf | python -c 'import json,sys;print json.load(sys.stdin)["network"]["router_id"]')
    if [[ -z "${ROUTER_ID}" ]]; then
        echo -e "${color_red} Could not create router, check the neutron logs above. Possible issue with neutron API. ${color_norm}"
        exit 1
    fi
    tessnet-bootstrap ${MASTER_NAME} true false ${DUAL_NIC}
    validate-network ${MASTER_NAME}

    #TODO validate  this actually generated the api key
    tessnet-generate-apikey ${KUBE_TEMP}/${MASTER_NAME}-tess.conf
    create-provision-script-and-boot-master ${MASTER_NAME}

    print-cluster-info ${MASTER_PUBLIC_IP}
}

# Execute prior to running tests to build a release if required for env
function test-build-release {
  # Make a release
  "${KUBE_ROOT}/build/release.sh"
}

function get-joke {
    if [ -z "$FIRST_TIME" ];
    then
        echo -e "${color_green}While we wait for the api server lb, here are some Chuck Norris Facts!${color_norm}"
        FIRST_TIME="set"
    fi
    id=`jot -r 1 1 550`
    result=`curl -silent --fail http://api.icndb.com/jokes/$id | python -c 'import json,sys; print json.load(sys.stdin)["value"]["joke"]'` 2>/dev/null
    echo $result
}

function validate-apiserver-vip {
    #SALT_MASTER_PUBLIC_IP=10.9.151.121
    #MASTER_FQDN=kubernetes-master-1-5991.phx01.dev.ebayc3.com

    if [[ "$ENABLE_API_SERVER_LB" == "false" ]]; then
        export APISERVER_LB_IP=$SALT_MASTER_PUBLIC_IP
        echo -e "${color_yellow}+++ Skipped creating LB for API server; configurable via config-default.sh ${color_norm}"
        echo
        return
    fi
    if [ -z "$SALT_MASTER_PUBLIC_IP" ];
    then
        echo -e "${color_red} SALT master is not set, honestly I can't believe you got so far long. ${color_norm}"
        exit
    fi
    echo ""
    echo -e "${color_yellow}+++ Attempting to get LB IP of the API server on $SALT_MASTER_PUBLIC_IP, this can loop forever if there was any uncaught exception during earlier phases. ${color_norm}"

    export FIRST_TIME=""
    result=""
    echo -e "${color_yellow}+++ Checking for API server. ${color_norm}"

    clusterValidated=true
    start=$SECONDS
    #This will fail until apiserver salt is updated
    until $(curl --insecure --user ${KUBE_USER}:${KUBE_PASSWORD} --max-time 5 \
          --fail --output /dev/null --silent http://${SALT_MASTER_PUBLIC_IP}:8080/api/v1/pods); do
      printf "."
      sleep 2
      duration=$(( SECONDS - start ))
      if [ $duration -gt 600 ]; then
        clusterValidated=false
        break
      fi
    done

    if [ $clusterValidated = false ]; then
    echo
    echo -e "${color_red} Kubernetes cluster failed to be validated in 10 minutes. ${color_norm}"
    exit 1
    fi

    echo "$TAB_PREFIX API server is UP."
    long-sleep 30
    # Download kubectl from swift?

#    chmod 755 kubectl
    pwd=`pwd`
    export PATH=$PATH:$pwd
    server="http://$SALT_MASTER_PUBLIC_IP:8080"
    service_yaml_template="${KUBE_ROOT}/cluster/c3/templates/kube-apiserver-service.yaml"
    sed -e "s/{{loadBalancerIP}}/${APISERVER_LB_IP}/g" $service_yaml_template > "${KUBE_TEMP}/kube-apiserver-service.yaml"
    result=`kubectl -s $server create -f "${KUBE_TEMP}/kube-apiserver-service.yaml" --namespace=default`
    echo "$result"
    for ((i=1; i <= 10; i++)) do
        if [[ "$result" != *"created"* ]]; then
            echo "$TAB_PREFIX API Service creation failed -- attempt $i"
            sleep 3
        else
            while [[ true ]] ; do
                result=`curl -s $server/api/v1/namespaces/default/services/kube-apiserver`
                status=`echo "$result" | python -c 'import json,sys; print json.load(sys.stdin)["status"]'`
                if [[ "$status" != "Failure" ]] && [[ "$status" == *"ingress"* ]]; then
                    export APISERVER_LB_IP=`echo "$result" | python -c 'import json,sys; print json.load(sys.stdin)["status"]["loadBalancer"]["ingress"][0]["ip"]'`
                    echo "$TAB_PREFIX API server LB: $APISERVER_LB_IP"
                    break;
                fi
                sleep 3
            done
        fi
        if [[ ! -z "$APISERVER_LB_IP" ]]; then
            break;
        fi
    done
}

# Perform preparations required to run e2e tests
function prepare-e2e() {
    :
}

function test-teardown {
  "${KUBE_ROOT}/cluster/kube-down.sh"
}

function test-setup {
  ${KUBE_ROOT}/cluster/kube-up.sh --skip-upload-tars=true
  echo "test-setup complete"
}
