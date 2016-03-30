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
source "${KUBE_ROOT}/cluster/c3/${KUBE_CONFIG_FILE-"config-default.sh"}"

function provision-cinder-volume {
    if [[ "$ENABLE_ETCD_CINDER_VOLUME" != "true" ]];
    then
        echo -e "${color_yellow}+++ Skipping provisioning of etcd volume for cinder. ${color_norm}"
        #export CINDER_VOLUME_UUID=""
        return
    fi

    if [[ -z "$1" ]];
    then
        echo -e "${color_red} Please pass compute name to attach. ${color_norm}"
        exit 1
    fi
    MASTER_NAME=$1
    local details="${KUBE_TEMP}/$MASTER_NAME-volume_details"

    echo -e "${color_yellow}+++ Provisioning cinder volume $CLUSTER_METADATA_VOLUME of size $CLUSTER_METADATA_VOLUME_SIZE ${color_norm}" >> $details
    cinder create --display-name $CLUSTER_METADATA_VOLUME-$MASTER_NAME $CLUSTER_METADATA_VOLUME_SIZE > $details
    local uuid=`cat $details | grep -w  id | cut -d'|' -f3`
    if [[ -z $uuid ]]
    then
        echo -e "${color_red} Cinder create failed. ${color_norm}" >> $details
        exit 1
    fi
    count=1
    for (( c=0; c<10; c++ ))
    do
        status=`cinder show $uuid | grep -w " status " | cut -d '|' -f3`
        echo "$TAB_PREFIX Cinder Volume status: $status" >> $details
        if [ $status == available ];
        then
            break;
        fi
        sleep 3
    done
    if [[ $c -eq 10 ]]
    then
        echo -e "${color_red} Cinder volume: $uuid for ETCD was not provision properly. ${color_norm}" >> $details
        exit 1
    fi
    echo -e "${color_green}+++ Created cinder volume: $uuid ${color_norm}" >> $details
    echo $uuid
}

function master-attach-volume {
    if [[ "$ENABLE_ETCD_CINDER_VOLUME" != "true" ]];
    then
        echo -e "${color_yellow}+++ Skipping attaching of etcd volume for cinder. ${color_norm}"
        return
    fi

    if [[ -z "$1" ]];
    then
        echo -e "${color_red} Please pass compute name to attach. ${color_norm}"
        exit 1
    fi
    MASTER_NAME=$1
    local compute_uuid=$(cat $KUBE_TEMP/$MASTER_NAME-tess.conf | python -c 'import json,sys;print json.load(sys.stdin)["compute"]["uuid"]')
    local volume_uuid=$(cat $KUBE_TEMP/$MASTER_NAME-tess.conf | python -c 'import json,sys;print json.load(sys.stdin)["volume"]["uuid"]')
    local details="${KUBE_TEMP}/volume_attach_details"
    #cinder rename $volume_uuid $CLUSTER_METADATA_VOLUME-$compute_uuid
    nova volume-attach $compute_uuid $volume_uuid > $details
    #check details if everything went well
    for (( c=0; c<10; c++ ))
    do
        local attachments=`cinder show $volume_uuid | grep -w "attachments" | cut -d'|' -f 3`
        if [[ $attachments == *"$compute_uuid"* ]]
        then
            echo -e "${color_yellow}+++ Attached cinder volume: $volume_uuid to master compute: $MASTER_NAME ${color_norm}"
            break
        fi
        sleep 3
    done
    if [[ $c -eq 10 ]]
    then
        echo -e "${color_red} Failed to attach cinder volume: $volume_uuid to master compute: $MASTER_NAME; check attach logs at: $details ${color_norm}"
        exit 1
    fi
}

function master-detach-volume {
    if [[ -z "$1" ]];
    then
        echo -e "${color_red} Please pass compute name to detach. ${color_norm}"
    fi
    MASTER_NAME=$1
    delete_volume=false
    for arg in $@
    do
        if [[ ${arg} == "--delete-etcd-volume" ]]
        then
            delete_volume=true
            break
        fi
    done
    echo -e "${color_yellow}+++ Attempting to detach cinder volume attached to $MASTER_NAME for etcd${color_norm}"

    local compute_uuid=`nova show $MASTER_NAME --minimal | grep '| id ' | awk '{print $4}'`
    if [[ -z $compute_uuid ]]; then
        echo -e "${color_red} Unable to find kubernetes-master from cloud provider. ${color_norm}"
        return
    fi
    local volume_uuid=`nova show $compute_uuid | grep "os-extended-volumes:volumes_attached" | cut -d':' -f3| cut -d'}' -f1 | xargs`
    if [[ -z $volume_uuid ]]
    then
        echo -e "${color_red} $compute_uuid does not seem to be attached to any cinder volume. Skipping cinder teardown. ${color_norm}"
        return
    fi
    nova volume-detach $compute_uuid $volume_uuid

    for (( c=0; c<10; c++ ))
    do
        local attachments=`cinder show $volume_uuid | grep -w "attachments" | cut -d'|' -f 3`
        if [[ $attachments == *"$compute_uuid"* ]]
        then
            echo "$TAB_PREFIX ETCD cinder volume: $volume_uuid still not detached."
            sleep 3
            continue
        fi
        echo "$TAB_PREFIX Detached cinder volume: $volume_uuid from master compute: $compute_uuid"
        break
    done
    if [[ $c -eq 10 ]]
    then
        echo -e "${color_red} Failed to detach cinder volume: $volume_uuid to master compute: $compute_uuid; check attach logs at: $details ${color_norm}"
        exit 1
    fi

    if [ "$delete_volume" = true ]; then
        echo -e "${color_yellow}+++ Do you want to delete the cinder volume $volume_uuid; \nThis might hold the clusters metadata; without which is not possible to start/restore the cluster [y/n]?[n]${color_norm}"
        read response
        if [[ "$response" == "y" ]];
        then
            echo -e "${color_yellow}+++ Deleting cinder volume: $volume_uuid ${color_norm}"
            cinder delete $volume_uuid
            return
        fi
    fi
}
