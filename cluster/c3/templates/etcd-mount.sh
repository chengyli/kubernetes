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

function mount-etcd() {

    ## Attach metadata volume for etcd
    local vol_id=`cat /mnt/config/openstack/latest/meta_data.json | python -c 'import json,sys;print json.load(sys.stdin)["meta"]["volume_id"]'`
    if [[ -z $vol_id ]]; then
        echo "Volume id is not populated; skipping mount/format of etcd volume"
        return
    fi
    #this is the path that gets mounted in to the etcd pod
    local data_dir=/mnt/master-pd/var/etcd
    local attached=0
    local max_attempts=50
    local disks=/dev/disk/by-id/*;

    for (( c=0;c<$max_attempts;c++ ));
    do
        udevadm trigger;
        for f in $disks;
        do
            disk=`echo $f | awk -F "/virtio-" '{print $2}'`;
            #echo $disk
            if [[ "$vol_id" == *"$disk"* && -n "$disk" ]]
            then
                echo "Disk attached"
                attached=1
                disk=$f
            fi

        done
        if [[ $attached -eq 1 ]]
        then
                break;
        fi
        echo "Disk $vol_id not attached...attempt: $c"
        sleep 6
    done

    if [[ $c -eq  $max_attempts ]]
    then
            echo "Disk not attached after $c attempts"
            exit 1
    fi

    #mount disk here
    echo $disk
    details=`/bin/lsblk -f $disk`
    if [[ "$details" == *"ext4"* ]] ; then
            echo "Disk is already ext4 formatted";
    else
            echo -e "${color_yellow} Formatting $disk with ext4 fs ${color_norm}"
            /sbin/mkfs.ext4 $disk
    fi

    mkdir -p $data_dir
    mount $disk $data_dir
    if [[ $? -ne 0 ]]; then
            echo "Failed to mount $disk $data_dir"
            exit 1
    fi
    echo "Disk Mounted at: $data_dir"
}

