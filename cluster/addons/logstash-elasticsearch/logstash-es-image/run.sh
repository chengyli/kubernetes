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

export ELASTICSEARCH_HOST_PORT=${ELASTICSEARCH_HOST_PORT:-"elasticsearch-logging:9200"}

# Wait for ES to come up. Kibana fails if it can't access ES anyways.
status=$(curl --silent --head --location --output /dev/null --write-out '%{http_code}' "http://${ELASTICSEARCH_HOST_PORT}")
if [[ ${status} -eq 200 ]]; then
  echo "ES is up. Continuing with Logstash."
  echo "Trying http://${ELASTICSEARCH_HOST_PORT}"
else
  echo "Trying to fall back to ES via ENV vars"
  echo "Trying http://${ELASTICSEARCH_LOGGING_SERVICE_HOST}:${ELASTICSEARCH_LOGGING_SERVICE_PORT}"
  status=$(curl --silent --head --location --output /dev/null --write-out '%{http_code}' "http://${ELASTICSEARCH_LOGGING_SERVICE_HOST}:${ELASTICSEARCH_LOGGING_SERVICE_PORT}")
  if [[ ${status} -eq 200 ]]; then
    echo "ES is up. Continuing with Logstash via env vars."
    export ELASTICSEARCH_HOST_PORT="${ELASTICSEARCH_LOGGING_SERVICE_HOST}:${ELASTICSEARCH_LOGGING_SERVICE_PORT}"
  else
    echo "Unable to reach ES. Killing self"
    exit
  fi
fi

export ELASTICSEARCH_URL=http://${ELASTICSEARCH_HOST_PORT}
echo $ELASTICSEARCH_URL

sed -i s/\$hosts/\"$ELASTICSEARCH_HOST_PORT\"/ /etc/logstash/output.conf
cat /etc/logstash/output.conf
echo "Updating logstash mappings..."
curl -i -XPUT --data "@/logstash_mapping_template.json" "${ELASTICSEARCH_URL}/_template/logstash_mapping_template"

# Then import the default dashboards
echo "Importing dashboards"
elasticdump --input=/kibana_dashboard_data.json --output="${ELASTICSEARCH_URL}/.kibana" --type=data

echo "Starting logstash..."
logstash -f /etc/logstash
