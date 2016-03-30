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

echo "Adding $SALT_MASTER_FQDN to hosts file"
echo "$SALT_MASTER_PUBLIC_IP $SALT_MASTER_FQDN" >> /etc/hosts
mount-config-driver

config-atomic-network

populate-master-fqdn

gen-openstack-rc

gen-salt-log-conf

gen-grains false true "$MINION_CONTAINER_SUBNET" "$MINION_CONTAINER_ADDR" "$DOCKER_FIXED_SUBNET"

if [ ! "$(cat /etc/hosts | grep $MASTER_FQDN)" ]; then
  echo "Adding $MASTER_FQDN to hosts file"
  echo "$MASTER_IP $MASTER_FQDN" >> /etc/hosts
fi

systemctl restart salt-minion
# set auto start salt after vm reboot
chkconfig salt-minion on

# Wait a few minutes and trigger another Salt run to better recover from
# any transient errors.
echo "Sleeping 180"
sleep 180
salt-call state.highstate || true
