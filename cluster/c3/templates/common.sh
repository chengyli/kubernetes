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

reset-master-password() {
passwd ${MASTER_USER}<<EOF
${MASTER_PASSWD}
${MASTER_PASSWD}
EOF
}

download-or-bust() {
  local -r url="$1"
  local -r file="${url##*/}"
  rm -f "$file"
  until [[ -e "${1##*/}" ]]; do
    echo "Downloading file ($1)"
    curl --ipv4 -Lo "$file" --connect-timeout 20 --retry 6 --retry-delay 10 "$1"
    md5sum "$file"
  done
}

mount-config-driver() {
  echo "Mounting cloud configuration"
  mkdir -p /mnt/config
  mount /dev/disk/by-label/config-2 /mnt/config
  echo "LABEL=config-2 /mnt/config vfat defaults 1 1" >> /etc/fstab
}

populate-master-fqdn() {
  local -r MASTER_FQDN=$1
  # Prepopulate the name of the Master
  mkdir -p /etc/salt/minion.d
  # This the salt-master
  cat <<EOF >/etc/salt/minion.d/master.conf
master: '$(echo "${SALT_MASTER_FQDN:-$MASTER_FQDN}" | sed -e "s/'/''/g")'
EOF
}

gen-openstack-rc() {
  cat <<EOF >/etc/sysconfig/openstack.rc
[Global]
auth-url=$(echo "$OS_AUTH_URL" | sed -e "s/'/''/g")
username=$(echo "$OS_USERNAME")
password=$(echo "$OS_PASSWORD")
region=$(echo "$OS_REGION_NAME")
tenant-id=$(echo "$OS_TENANT_ID")
EOF

  if [[ ${1:-} == "master" ]]; then
    (
      echo "[LoadBalancer]"
      echo "floating-network-id=${FLOATINGIP_NET_ID}"
      echo "subnet-id=${LB_SUBNET_ID}"
    ) >> /etc/sysconfig/openstack.rc
  fi
}

gen-keystone-auth() {
  cat <<EOF >/etc/sysconfig/keystoneauthorization.json
{
  "auth-url": "$(echo "$OS_AUTH_URL" | sed -e "s/'/''/g" | sed -e "s/5443/443/g")",
  "user-name": "$(echo "$OS_USERNAME")",
  "password": "$(echo "$OS_PASSWORD")",
  "region": "$(echo "$OS_REGION_NAME")",
  "tenant-id": "$(echo "$OS_TENANT_ID")",
  "tenant-name": "$(echo "$OS_TENANT_NAME")",
  "domain-name": "default"
}
EOF
}

gen-salt-log-conf() {
  cat <<EOF >/etc/salt/minion.d/log-level-debug.conf
log_level: debug
log_level_logfile: debug
EOF
}

gen-salt-master-conf() {
  mkdir -p /etc/salt/master.d

  cat <<EOF >/etc/salt/master.d/reactor.conf
# React to new minions starting by running highstate on them.
reactor:
  - 'salt/minion/*/start':
    - /srv/reactor/highstate-new.sls
EOF

  cat <<EOF >/etc/salt/master.d/salt-output.conf
state_verbose: False
state_output: mixed
log_level: debug
log_level_logfile: debug
EOF
}

# parameters:
# master: true or false. if it is kube-master
# atomic: true or false. if it is atomic os
# SUBNET: the subnet used by a node
# BRIDGE_IP: the ip address of cbr0 bridge
# DOCKER_FIXED_SUBNET: the cidr sued by docker
#
# other parameters in this function are from outside
gen-grains() {
  local -r master=$1
  local -r atomic=$2
  local -r SUBNET=$3
  local -r BRIDGE_IP=$4
  local -r DOCKER_FIXED_SUBNET=$5

  if [[ "${master}" == "true" ]]; then
    local salt_role=kubernetes-master
  else
    local salt_role=kubernetes-pool
  fi

  if [[ "${atomic}" == "true" ]]; then
    local host_domain=""
  else
    local host_domain=$DOMAIN_SUFFIX
  fi

  cat <<EOF >/etc/salt/minion.d/grains.conf
grains:
  roles:
    - $(echo $salt_role)
  ${IS_SALT_MASTER:+  - salt-master}
  cloud: c3
  cloud_provider: openstack
  cbr_cidr: '$(echo "$SUBNET" | sed -e "s/'/''/g")'
  cbr_ip: '$(echo "$BRIDGE_IP" | sed -e "s/'/''/g")'
  network_mode: 'openvswitch'
  ovs_tunnel_mode: 'ovs-flat'
  bridgeable_device: '$(echo "$BRIDGEABLE_DEVICE")'
  cloud_config: /etc/sysconfig/openstack.rc
  docker_fixed_cidr: '$(echo "$DOCKER_FIXED_SUBNET" | sed -e "s/'/''/g")'
  obr0_gateway: '$(echo "$OBR0_GATEWAY" | sed -e "s/'/''/g")'
  hostname_override: '$(hostname)$(echo "$host_domain" | sed -e "s/'/''/g")'
EOF

  if [[ "${atomic}" == "true" ]]; then
    echo "  os_distribution: atomic" >> /etc/salt/minion.d/grains.conf
  fi

  if [[ "${master}" == "true" ]]; then
    cat <<EOF >>/etc/salt/minion.d/grains.conf
  node_ip: '$(echo "$node_ip" | sed -e "s/'/''/g")'
  master_ip: '$(echo "$MASTER_IP" | sed -e "s/'/''/g")'
  networkInterfaceName: eth0
  runtime_config: '$(echo "$RUNTIME_CONFIG" | sed -e "s/'/''/g")'
  etcd_discovery_url: '$(echo "$DISCOVERY_URL")'
  kube_master_ha: '$(echo "$KUBE_MASTER_HA")'
  node_name: '$(echo "$MASTER_NAME")'
  api_device: '$(echo "$API_DEVICE")'
EOF
  else
    if [[ "$ENABLE_API_SERVER_LB" == "true" ]]; then
      echo "  api_servers_with_port: $(echo "$APISERVER_LB_IP":443)" >> /etc/salt/minion.d/grains.conf
    else
      echo "  apiservers: $(echo "$APISERVER_LB_IP")" >> /etc/salt/minion.d/grains.conf
    fi
  fi

  DOCKER_OPTS=""
  if [[ -n "${EXTRA_DOCKER_OPTS}" ]]; then
    DOCKER_OPTS="${EXTRA_DOCKER_OPTS}"
  fi

  if [[ -n "${DOCKER_OPTS}" ]]; then
    cat <<EOF >>/etc/salt/minion.d/grains.conf
  docker_opts: '$(echo "$DOCKER_OPTS" | sed -e "s/'/''/g")'
EOF
  fi
}

cp-credentials() {
  #issue 802 store salt keys. cp to tmp, and bootstrap can get them to upload
  cp /etc/salt/pki/master/master.pem /tmp/
  cp /etc/salt/pki/master/master.pub /tmp/
  cp /etc/salt/pki/master/master_sign.pem /tmp/
  cp /etc/salt/pki/master/master_sign.pub /tmp
  cp /etc/ssl/kubernetes/server.crt /tmp/
  cp /etc/ssl/kubernetes/server.key /tmp/
  cp  /etc/ssl/kubernetes/ca.crt /tmp/
  cp  /etc/ssl/kubernetes/etcd.crt /tmp/
  cp  /etc/ssl/kubernetes/etcd.key /tmp/
  pushd /tmp/
  chmod 644 *.pem *.crt *.key
  popd
}

set-salt-autoaccept() {
# issue 877 enable salt master key gpg sign
# Auto accept all keys from minions that try to join
mkdir -p /etc/salt/master.d
cat <<EOF >/etc/salt/master.d/auto-accept.conf
# TODO(qiuyu): open_mode needs to be reviewed
open_mode: True
auto_accept: True
EOF
}

config-atomic-network() {
  # change interface name first, or the network restart will hang
  ifconfig ens3 down
  ip link set ens3 name eth0
  ifconfig eth0 up
  # append the mac address of interface to this file
  # udev will set the interface name to eth0 if HWADDR in file ifcfg-eth0 matches the mac address
  echo HWADDR=`ifconfig eth0 | grep ether | awk '{print $2}'` >> /etc/sysconfig/network-scripts/ifcfg-eth0

  ifconfig ens4 down
  ip link set ens4 name eth1
  ifconfig eth1 up
  echo HWADDR=`ifconfig eth1 | grep ether | awk '{print $2}'` >> /etc/sysconfig/network-scripts/ifcfg-eth1

  rm -rf /etc/sysconfig/network-scripts/ifcfg-ens3 > /dev/null 2>&1
  rm -rf /etc/sysconfig/network-scripts/ifcfg-ens4 > /dev/null 2>&1

  domain=`cat /mnt/config/openstack/latest/meta_data.json | python -c 'import json,sys;print json.load(sys.stdin)["meta"]["domainname"]'`
  echo domain $domain > /etc/resolv.conf
  if [ -f /etc/sysconfig/network-scripts/ifcfg-eth0 ]; then
    echo "DOMAIN=$domain" >> /etc/sysconfig/network-scripts/ifcfg-eth0
  fi

  search=`cat /mnt/config/openstack/latest/meta_data.json | python -c 'import json,sys;print json.load(sys.stdin)["meta"]["searchdomains"]'`
  echo search $search | sed -e "s/,/ /g" >> /etc/resolv.conf

  nameservers=`cat /mnt/config/openstack/latest/meta_data.json | python -c 'import json,sys;print json.load(sys.stdin)["meta"]["nameservers"]'`
  IFS=',' read -r -a arr <<< "$nameservers"
  ((i=1))
  for ele in "${arr[@]}"; do
    echo nameserver $ele >> /etc/resolv.conf
    if [ -f /etc/sysconfig/network-scripts/ifcfg-eth0 ]; then
      echo "DNS$i=$ele" >> /etc/sysconfig/network-scripts/ifcfg-eth0
    fi
    ((i=i+1))
  done
  systemctl restart network
  chkconfig network on
}
