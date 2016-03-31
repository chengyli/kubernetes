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

# Provided for backwards compatibility

KUBE_ROOT=$(dirname "${BASH_SOURCE}")/..
echo $KUBE_ROOT
${KUBE_VERSION_ROOT:=${KUBE_ROOT}}
${KUBECTL:=${KUBE_VERSION_ROOT}/cluster/kubectl.sh}
IP=""
VERSION_CHECK=true
TEST_ARGS=""
TENANT_NAME=tess-ci
declare TESTS_ONLY=false

#Get the cluster name
function getcontextname() {
	TENANT_NAME=`keystone tenant-get $tenant | grep name | cut -d "|" -f3`
	TENANT_NAME=`echo ${TENANT_NAME//[[:blank:]]/}`
}

#Set context is required for the tests to run. kubectl is being used for running tests
function setcontext() {
        echo "Setting Context with IP: $IP"
        getcontextname
	export KUBE_MASTER_URL=http://$IP:8080
        ${KUBECTL} config set-cluster $TENANT_NAME --server=http://$IP:8080
        ${KUBECTL} config set-context $TENANT_NAME --cluster=$TENANT_NAME
        ${KUBECTL} config use-context $TENANT_NAME
}

function findmaster() {
	IP=""
	ID=`nova list --tenant $tenant | grep kubernetes-master | head -n 1 | cut -d "|" -f2`
	ID=`echo ${ID//[[:blank:]]/}`
	if [ "$ID" != "" ];then
		ID=`echo ${ID//[[:blank:]]/}`
        	IP=`nova show $ID | grep shared | cut -d "|" -f3`
		IP=`echo ${IP//[[:blank:]]/}`
        	if [[ $IP == *[[:space:],]* ]]
        	then
                	echo "Tess master contains multiple floating ips:$IP"
                	IP=`echo $IP | cut -d "," -f1 | cut -d " " -f1`
        	fi
	fi
	echo "======IP:$IP===="
}

function set_env_variables() {
	findmaster
	echo "Setting environment variables for $IP"
        setcontext $IP
        export MASTER_IP="$IP:8080"
}

function error() {
        echo "Kube command:$1"
	go run "$(dirname $0)/e2e.go" -v -down
	echo "Kube command:$1"
        exit 1
}

#If no parameters passed to the script, Error it out.
if [ $# -ne 0 ]; then
	echo "Arguments passed: $*"
else
	echo "No arguments passed. Skipping the tests"
	exit $?
fi


function usage()
{
    echo "This is how your script should look like"
    echo ""
    echo "hack/tess-e2e-test.sh"
    echo "--tenant_id=$tenants"
    echo "--check_version_skew=$VERSION_CHECK"
    echo "--test_args=$TEST_ARGS"
    echo "--tests_only=$TESTS_ONLY"
    echo ""
}

#Parameter checking
while [ "$1" != "" ]; do
    PARAM=`echo $1 | awk -F= '{print $1}'`
    VALUE=`echo $1 | awk -F= '{print $2}'`
    case $PARAM in
        -h | --help)
            usage
            exit
            ;;
	--tenant_id)
	    tenants=$VALUE
	    ;;
        --check_version_skew)
            VERSION_CHECK=$VALUE
	    ;;
        --tests_only)
	    TESTS_ONLY=$VALUE
            ;;
        --test_args)
            TEST_ARGS=$VALUE
            ;;
        *)
            echo "ERROR: unknown parameter \"$PARAM\""
            usage
            exit 1
            ;;
    esac
    shift
done

declare CHOSEN=false
echo ${tenants//,/$'\n'}
for tenant in ${tenants//,/$'\n'}
#`echo "$tenants" | grep -o -e "[^,]*"`;
do
	echo "Chosen tenant is $tenant"
	findmaster
	if $TESTS_ONLY; then
		set_env_variables
                echo "Running only Tests on the cluster $IP"
        	go run "$(dirname $0)/e2e.go" -v -check_version_skew=$VERSION_CHECK -test --test_args="--ginkgo.focus=$TEST_ARGS"
		CHOSEN=true
		break
        elif [[ -z $IP ]]; then
                echo "Master not found. Cluster is empty."
                export OS_TENANT_ID=$tenant
		set_env_variables
                go run "$(dirname $0)/e2e.go" -v -up
                if [ $? -ne 0 ]; then
                        error "e2e Tests: kube-up failed"
                fi
		set_env_variables
                go run "$(dirname $0)/e2e.go" -v -check_version_skew=$VERSION_CHECK -test --test_args="--ginkgo.focus=$TEST_ARGS"
		if [ $? -ne 0 ]; then
                                error "e2e Tests failed."
                fi
		go run "$(dirname $0)/e2e.go" -v -down
		CHOSEN=true
                break
        else
                echo "Cluster exists at $IP and tenant is $tenant. Checking to see if its running"
                content=`curl --connect-timeout 600 --silent -X GET http://$IP:8080/api/v1`

		#Check if cluster is running. If its not CI cluster, just run tests. If its a CI cluster, do kube-down, up, test and down.
                if [[ (-n $content) ]]; then
                        echo "Cluster $IP at tenant $tenant is up and running. Moving to next cluster"
                else
			CHOSEN=true
			echo "Cluster exists. But its either down or it belongs to CI cluster."
                        export OS_TENANT_ID=$tenant
                        go run "$(dirname $0)/e2e.go" -v -down
                        go run "$(dirname $0)/e2e.go" -v -up
                        if [ $? -ne 0 ]; then
                                 error "e2e Tests: kube-up failed."
                        fi
			#Tests on the cluster use kubectl. So we have to update the kubectl with the new server
			set_env_variables
			go run "$(dirname $0)/e2e.go" -v -check_version_skew=$VERSION_CHECK -test --test_args="--ginkgo.focus=$TEST_ARGS"
			if [ $? -ne 0 ]; then
                                error "e2e Tests failed."
                        fi
                        go run "$(dirname $0)/e2e.go" -v -down
                        if [ $? -ne 0 ]; then
                                error "e2e Tests: kube-down failed."
                        fi
                        break
        	fi
	fi

done
if [ "$CHOSEN" == false ]; then
	echo "No CI cluster available to run the tests."
        exit 1
fi

exit $?

