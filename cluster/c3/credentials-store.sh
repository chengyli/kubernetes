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

# A library of helper functions that upload the keys/ca to swift, and grant file owner permission on swift.
# issue #694 for store keys to esam and swift.

#KUBE_ROOT=$(dirname "${BASH_SOURCE}")/../..
#source "${KUBE_ROOT}/cluster/c3/${KUBE_CONFIG_FILE-"config-default.sh"}"

#credentials are public or not, that should be pre-defined.
#return 0 is private, return 1 is pubic
function get-access() {
   local -r filename=$1
   case ${filename} in
   ${SSH_KEY_NAME} ) return 0 ;;
   ${CLUSTER_CA} ) return 1 ;;
   ${APISERVER_KEY} ) return 0 ;;
   ${APISERVER_CRT} ) return 0 ;;
   ${ETCD_KEY} ) return 0;;
   ${ETCD_CRT} ) return 0;;
   ${SALT_PRI_KEY} ) return 0;;
   ${SALT_PUB_KEY} ) return 0;;
   ${SALT_PRI_SIGN} ) return 0;;
   ${SALT_PUB_SIGN} ) return 0;;
   * ) return 1;;
   esac
}

#by default, the file will be override if the function called
#parameters: /etc/kubernetes/pki/ca.cert ~/.ssh/id_kubernetes /etc/kubernetes/pki/ca.cert
#private credential will upload to the esam in future as well
function upload-credential() {
    local -r credential_bucket="${CLUSTER_DOMAIN_SUFFIX}"
    local -r credential_bucket_pri="${credential_bucket}.pri"
    local -r credential_bucket_pub="${credential_bucket}.pub"
    account_id=$(${SWIFT} stat | awk '/ Account: / { print $2 }')
    swift_url="${SWIFT_ENDPOINT}/${account_id}/"
    # Ensure the bucket is created
    if ! ${SWIFT} list | grep "${credential_bucket_pub}" > /dev/null ; then
        echo -e "${color_yellow}+++ Creating Credential Public Bucket ${color_norm}: ${swift_url}${credential_bucket_pub}"
        perm='.r:*'
        ${SWIFT} post "${credential_bucket_pub}" -r ${perm}
    fi
    if ! ${SWIFT} list | grep "${credential_bucket_pri}" > /dev/null ; then
        echo -e "${color_yellow}+++ Creating Credential Private Bucket ${color_norm}: ${swift_url}${credential_bucket_pri}"
        ${SWIFT} post "${credential_bucket_pri}"
        perm="${OS_TENANT_NAME}:${OS_USERNAME}"
        ${SWIFT} post "${credential_bucket_pri}" -r ${perm}
    fi
    echo -e "${color_yellow}+++ Cluster credentials to Swift: ${credential_bucket} ${color_norm}"
    for i in $(seq 1 $#); do
        echo $1
        file_name="${1}"
        pushd $(dirname ${file_name}) > /dev/null
        #there are 2 bucket:private and public.
        if get-access "${file_name##*/}" ; then
            ${SWIFT} upload "${credential_bucket_pri}" "${file_name##*/}" > /dev/null
        else
            ${SWIFT} upload "${credential_bucket_pub}" "${file_name##*/}" > /dev/null
        fi
        popd > /dev/null
        shift
    done
}

function delete-credential() {
    local -r credential_bucket="${CLUSTER_DOMAIN_SUFFIX}"
    local -r credential_bucket_pri="${credential_bucket}.pri"
    local -r credential_bucket_pub="${credential_bucket}.pub"
    echo -e "${color_yellow}+++ Delete Credential Public Bucket ${color_norm}"
    $(${SWIFT} delete "${credential_bucket_pub}" 1>/dev/null 2>&1)
    echo -e "${color_yellow}+++ Delete Credential Private Bucket ${color_norm}"
    $(${SWIFT} delete "${credential_bucket_pri}" 1>/dev/null 2>&1)
}

function check-credential-bucket() {
    local -r credential_bucket="${CLUSTER_DOMAIN_SUFFIX}"
    local -r credential_bucket_pri="${credential_bucket}.pri"
    local -r credential_bucket_pub="${credential_bucket}.pub"
    # Ensure the bucket is created
    if ${SWIFT} list | grep ${credential_bucket_pri}  > /dev/null ; then
       return 1
    fi
    if ${SWIFT} list | grep ${credential_bucket_pub}  > /dev/null ; then
       return 1
    fi
    return 0
}

function check-credential() {
    local -r credential_bucket="${CLUSTER_DOMAIN_SUFFIX}"
    local -r credential_bucket_pri="${credential_bucket}.pri"
    local -r credential_bucket_pub="${credential_bucket}.pub"
    local -r filename="$1"
    # Ensure the bucket is created
    if ${SWIFT} list ${credential_bucket_pri} | grep "${filename}" > /dev/null ; then
       return 1
    fi
    if ${SWIFT} list ${credential_bucket_pub} | grep "${filename}" > /dev/null ; then
       return 1
    fi
    return 0
}

function down-credential() {
    local -r credential_bucket="${CLUSTER_DOMAIN_SUFFIX}"
    local -r credential_bucket_pri="${credential_bucket}.pri"
    local -r credential_bucket_pub="${credential_bucket}.pub"
    local -r filename="$1"
    local -r dest="${2-/tmp}"
    pushd $dest
    if get-access ${filename} ; then
        ${SWIFT} download "${credential_bucket_pri}" ${filename}
    else
        ${SWIFT} download "${credential_bucket_pub}" ${filename}
    fi
    popd
}

function get-credential-download-cmd() {
    account_id=$(${SWIFT} stat | awk '/ Account: / { print $2 }')
    swift_url="${SWIFT_ENDPOINT}/${account_id}"
    token=`keystone token-get | grep id | head -n 1 | awk '{print $4}' `
    local -r credential_bucket="${CLUSTER_DOMAIN_SUFFIX}"
    local -r credential_bucket_pri="${credential_bucket}.pri"
    local -r credential_bucket_pub="${credential_bucket}.pub"
    local -r filename="$1"
    local -r directory="$2"

    if get-access "${filename##*/}" ; then
        echo "curl  -X GET -H \"X-Auth-Token: $token\" ${swift_url}/${credential_bucket_pri}/${filename} -o ${directory}/${filename}"
    else
        echo "curl  -X GET -H \"X-Auth-Token: $token\" ${swift_url}/${credential_bucket_pub}/${filename} -o ${directory}/${filename}"
    fi
}

function upload-credential-esam {
    #todo this the interface for uploading file to esam.
    echo -e "${color_yellow}+++ Updload Credential Public Bucket ${color_norm}"
}
