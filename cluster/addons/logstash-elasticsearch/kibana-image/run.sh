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

# Discover cluster IP and port for elasticsearch
SERVICE_DETAILS="$(/service-discovery -service_name=elasticsearch-logging -namespace=kube-system)"
echo "$SERVICE_DETAILS"
CLUSTER_IP=$(echo "$SERVICE_DETAILS" |grep CLUSTER_IP|cut -d "=" -f 2)
PORT=$(echo "$SERVICE_DETAILS" |grep PORTS|cut -d "=" -f 2)
if [ -z "$CLUSTER_IP" ] || [ -z "$PORT" ]; then
    # If we can't auto discover it, fall back to using its DNS name
    export ELASTICSEARCH_URL="http://elasticsearch-logging:9200"
else
    export ELASTICSEARCH_URL="http://$CLUSTER_IP:$PORT"
fi

# Check if the endpoint returned above is reachable. If not fall back to ENV vars. If that too fails then exit.

status=$(curl --silent --head --location --output /dev/null --write-out '%{http_code}' "${ELASTICSEARCH_URL}")
if [[ ${status} -eq 200 ]]; then
  echo "ES is up. Continuing with Kibana."
  echo "Trying ${ELASTICSEARCH_URL}"
else
  echo "Trying to fall back to ES via ENV vars"
  echo "Trying http://${ELASTICSEARCH_LOGGING_SERVICE_HOST}:${ELASTICSEARCH_LOGGING_SERVICE_PORT}"
  status=$(curl --silent --head --location --output /dev/null --write-out '%{http_code}' "http://${ELASTICSEARCH_LOGGING_SERVICE_HOST}:${ELASTICSEARCH_LOGGING_SERVICE_PORT}")
  if [[ ${status} -eq 200 ]]; then
    echo "ES is up. Continuing with Logstash via env vars."
    export ELASTICSEARCH_URL="http://${ELASTICSEARCH_LOGGING_SERVICE_HOST}:${ELASTICSEARCH_LOGGING_SERVICE_PORT}"
  else
    echo "Unable to reach ES. Killing self"
    exit
  fi
fi

echo ELASTICSEARCH_URL=${ELASTICSEARCH_URL}
echo "" >> /kibana/config/kibana.yml
echo "elasticsearch.url: \"${ELASTICSEARCH_URL}\"" >> /kibana/config/kibana.yml
cat /kibana/config/kibana.yml
/kibana/bin/kibana
