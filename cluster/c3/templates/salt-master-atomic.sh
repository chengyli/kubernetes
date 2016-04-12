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

MASTER_FQDN=$(hostname)

# This logic is to properly set salt-master in the hosts file so that the salt-call would properly execute
# Only one of the kubernetes master is a salt-master, so that is set appropriately.
if [ ! "$(cat /etc/hosts | grep $MASTER_FQDN)" ]; then
    if [ "$SALT_MASTER" = "$MASTER_NAME" ];
    then
        echo "Adding $MASTER_FQDN to hosts file"
        echo "127.0.0.1 $MASTER_FQDN $MASTER_NAME" >> /etc/hosts
    else
        echo "Adding $SALT_MASTER_FQDN to hosts file"
        echo "$SALT_MASTER_PUBLIC_IP $SALT_MASTER_FQDN" >> /etc/hosts
    fi
fi

# reset master password
reset-master-password

mount-config-driver

populate-master-fqdn ${MASTER_FQDN}

gen-openstack-rc master

gen-salt-log-conf

gen-keystone-auth

# TODO Do this via salt
node_ip=`ifconfig eth0 2>/dev/null|awk '/inet / {print $2}'`
cat <<EOF > /etc/sysconfig/.kubernetes_auth
{"BearerToken":"$(echo "$kubelet_token")","Insecure":true, "Host":"http://$(echo "$node_ip"):8080"}
EOF

gen-grains true true "$MASTER_SUBNET" "$MASTER_DOCKER_BRIDGE_IP" "$MASTER_DOCKER_CIDR"

# Auto accept all keys from minions that try to join
gen-salt-master-conf

# Function in etcd-mount.sh
mount-etcd

echo "root:password" | chpasswd

set-salt-autoaccept

if [ "$SALT_MASTER" = "$MASTER_NAME" ];
then
  printf '%s\n\n%s\n  %s\n' 'extension_modules: /srv/modules' 'ext_pillar:' '- custom_pillar:' >> /etc/salt/master
  chkconfig salt-master on
  # issue 877 enable salt master key gpg sign
  printf 'master_sign_pubkey: True' >> /etc/salt/master
  systemctl restart salt-master
  systemctl restart salt-api
  #issue 802 store salt keys. wait for salt key generate
  sleep 30
fi

# issue 877 enable salt master key gpg sign
printf 'verify_master_pubkey_sign: True' >> /etc/salt/minion
chkconfig salt-minion on
systemctl restart salt-minion

#issue 802 store salt keys. cp to tmp, and bootstrap can get them to upload
sleep 3
if [ -f /etc/salt/pki/master/master_sign.pub -a -f /etc/salt/pki/master/master.pub ]; then
   cp /etc/salt/pki/master/master_sign.pub /etc/salt/pki/minion/ >/dev/null
   cp /etc/salt/pki/master/master.pub /etc/salt/pki/minion/ >/dev/null
else
   eval  "${SALT_PUB_KEY_CMD}"
   eval  "${SALT_SIGN_KEY_CMD}"
fi

systemctl restart salt-minion
# Wait a few minutes and trigger another Salt run to better recover from
# any transient errors.
echo "Sleeping 180"
sleep 180
salt-call state.highstate || true
if [ -f /etc/salt/pki/master/master_sign.pub -a -f /etc/salt/pki/master/master.pub ]; then
   cp-credentials
fi
