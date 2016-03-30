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

HEADER_CONTENT_TYPE="Content-Type: application/json"
HEADER_ACCEPT="Accept: application/json"

GRAFANA_USER=${GRAFANA_USER:-admin}
GRAFANA_PASSWD=${GRAFANA_PASSWD:-admin}
GRAFANA_PORT=${GRAFANA_PORT:-3000}

INFLUXDB_HOST=${INFLUXDB_HOST:-"monitoring-influxdb"}
INFLUXDB_DATABASE=${INFLUXDB_DATABASE:-k8s}
INFLUXDB_PASSWORD=${INFLUXDB_PASSWORD:-root}
INFLUXDB_PORT=${INFLUXDB_PORT:-8086}
INFLUXDB_USER=${INFLUXDB_USER:-root}

DASHBOARD_LOCATION=${DASHBOARD_LOCATION:-"/dashboards"}

# Allow access to dashboards without having to log in
export GF_AUTH_ANONYMOUS_ENABLED=true
export GF_SERVER_HTTP_PORT=${GRAFANA_PORT}

BACKEND_ACCESS_MODE=${BACKEND_ACCESS_MODE:-proxy}
INFLUXDB_SERVICE_URL=${INFLUXDB_SERVICE_URL}
if [ -n "$INFLUXDB_SERVICE_URL" ]; then
  echo "Influxdb service URL is provided."
else
  echo "Discovering influxdb service URL..."
  INFLUXDB_SERVICE_URL=$(/influxdb_service_discovery)
  if [ -n "$INFLUXDB_SERVICE_URL" ]; then
    echo "Use InfluxDB external service, and 'direct' access mode from Grafana."
    BACKEND_ACCESS_MODE=direct
  else
    echo "Unable to get external service URL for InfluxDB."
    echo "Use internal/proxy URL, and 'proxy' access mode from Grafana."
    INFLUXDB_SERVICE_URL="http://${INFLUXDB_HOST}:${INFLUXDB_PORT}"
    BACKEND_ACCESS_MODE=proxy
  fi
fi

echo "Using the following URL for InfluxDB: ${INFLUXDB_SERVICE_URL}"
echo "Using the following backend access mode for InfluxDB: ${BACKEND_ACCESS_MODE}"

PROMETHEUS_SERVICE_DETAILS="$(/service-discovery -service_name=monitoring-prometheus -namespace=kube-system)"
echo "$PROMETHEUS_SERVICE_DETAILS"
PROMETHEUS_CLUSTER_IP=$(echo "$PROMETHEUS_SERVICE_DETAILS" |grep CLUSTER_IP|cut -d "=" -f 2)
PROMETHEUS_PORT=$(echo "$PROMETHEUS_SERVICE_DETAILS" |grep PORTS|cut -d "=" -f 2)
if [ -z "$PROMETHEUS_CLUSTER_IP" ] || [ -z "$PROMETHEUS_PORT" ]; then
    # If we can't auto discover it, fall back to using its DNS name
    export PROMETHEUS_URL="http://monitoring-prometheus:9090"
else
    export PROMETHEUS_URL="http://$PROMETHEUS_CLUSTER_IP:$PROMETHEUS_PORT"
fi

# Check if the endpoint returned above is reachable. If not fall back to ENV vars. If that too fails then exit.

#Prometheus alone requires status 405 check as it doesnt seem to allow calls through curl
#If status is 405 then we know that the end point is open and hence connection can be established.
status=$(curl --silent --head --location --output /dev/null --write-out '%{http_code}' "${PROMETHEUS_URL}")
if [ ${status} -eq 200 ] || [ ${status} -eq 405 ]; then
  echo "Prometheus is up. Continuing with Grafana."
  echo "Trying ${PROMETHEUS_URL}"
else
  echo "Trying to fall back to Prometheus via ENV vars"
  echo "Trying http://${MONITORING_PROMETHEUS_SERVICE_HOST}:${MONITORING_PROMETHEUS_SERVICE_PORT}"
  status=$(curl --silent --head --location --output /dev/null --write-out '%{http_code}' "http://${MONITORING_PROMETHEUS_SERVICE_HOST}:${MONITORING_PROMETHEUS_SERVICE_PORT}")
  if [ ${status} -eq 200 ] || [ ${status} -eq 405 ]; then
    echo "Prometheus is up. Continuing with Grafana via env vars."
    export PROMETHEUS_URL="http://${MONITORING_PROMETHEUS_SERVICE_HOST}:${MONITORING_PROMETHEUS_SERVICE_PORT}"
  else
    echo "Unable to reach Prometheus. Killing self"
    exit
  fi
fi

export PROMETHEUS_SERVICE_URL=${PROMETHEUS_URL}
echo "Using the following URL for Prometheus: ${PROMETHEUS_SERVICE_URL}"

ELASTIC_SERVICE_DETAILS="$(/service-discovery -service_name=elasticsearch-logging -namespace=kube-system)"
echo "$ELASTIC_SERVICE_DETAILS"
ELASTIC_CLUSTER_IP=$(echo "$ELASTIC_SERVICE_DETAILS" |grep CLUSTER_IP|cut -d "=" -f 2)
ELASTIC_PORT=$(echo "$ELASTIC_SERVICE_DETAILS" |grep PORTS|cut -d "=" -f 2)
if [ -z "$ELASTIC_CLUSTER_IP" ] || [ -z "$ELASTIC_PORT" ]; then
    # If we can't auto discover it, fall back to using its DNS name
    export ELASTICSEARCH_URL="http://elasticsearch-logging:9200"
else
    export ELASTICSEARCH_URL="http://$ELASTIC_CLUSTER_IP:$ELASTIC_PORT"
fi

# Check if the endpoint returned above is reachable. If not fall back to ENV vars. If that too fails then exit.

status=$(curl --silent --head --location --output /dev/null --write-out '%{http_code}' "${ELASTICSEARCH_URL}")
if [[ ${status} -eq 200 ]]; then
  echo "ES is up. Continuing with Grafana."
  echo "Trying ${ELASTICSEARCH_URL}"
else
  echo "Trying to fall back to ES via ENV vars"
  echo "Trying http://${ELASTICSEARCH_LOGGING_SERVICE_HOST}:${ELASTICSEARCH_LOGGING_SERVICE_PORT}"
  status=$(curl --silent --head --location --output /dev/null --write-out '%{http_code}' "http://${ELASTICSEARCH_LOGGING_SERVICE_HOST}:${ELASTICSEARCH_LOGGING_SERVICE_PORT}")
  if [[ ${status} -eq 200 ]]; then
    echo "ES is up. Continuing with Grafana via env vars."
    export ELASTICSEARCH_URL="http://${ELASTICSEARCH_LOGGING_SERVICE_HOST}:${ELASTICSEARCH_LOGGING_SERVICE_PORT}"
  else
    echo "Unable to reach ES. Killing self"
    exit
  fi
fi

export ELASTICSEARCH_SERVICE_URL=${ELASTICSEARCH_URL}
echo "Using the following URL for ElasticSearch: ${ELASTICSEARCH_SERVICE_URL}"

ELASTICSEARCH_INDEX=${ELASTICSEARCH_INDEX:-"heapster-metrics"}
echo "Using the following ES Index: ${ELASTICSEARCH_INDEX}"


set -m
echo "Starting Grafana in the background"
exec /usr/sbin/grafana-server --homepath=/usr/share/grafana --config=/etc/grafana/grafana.ini cfg:default.paths.data=/var/lib/grafana cfg:default.paths.logs=/var/log/grafana &

echo "Waiting for Grafana to come up..."
until $(curl --fail --output /dev/null --silent http://${GRAFANA_USER}:${GRAFANA_PASSWD}@localhost:${GRAFANA_PORT}/api/org); do
  printf "."
  sleep 2
done
echo "Grafana is up and running."
echo "Creating influxdb datasource..."
curl -i -XPOST -H "${HEADER_ACCEPT}" -H "${HEADER_CONTENT_TYPE}" "http://${GRAFANA_USER}:${GRAFANA_PASSWD}@localhost:${GRAFANA_PORT}/api/datasources" -d '
{ 
  "name": "influxdb-datasource",
  "type": "influxdb",
  "access": "'"${BACKEND_ACCESS_MODE}"'",
  "isDefault": false,
  "url": "'"${INFLUXDB_SERVICE_URL}"'",
  "password": "'"${INFLUXDB_PASSWORD}"'",
  "user": "'"${INFLUXDB_USER}"'",
  "database": "'"${INFLUXDB_DATABASE}"'"
}'

echo "Creating Prometheus datasource..."
curl -i -XPOST -H "${HEADER_ACCEPT}" -H "${HEADER_CONTENT_TYPE}" "http://${GRAFANA_USER}:${GRAFANA_PASSWD}@localhost:${GRAFANA_PORT}/api/datasources" -d '
{
  "name": "prometheus-datasource",
  "type": "prometheus",
  "access": "'"proxy"'",
  "isDefault": true,
  "url": "'"${PROMETHEUS_SERVICE_URL}"'"
}'

echo "Creating ElasticSearch datasource..."
curl -i -XPOST -H "${HEADER_ACCEPT}" -H "${HEADER_CONTENT_TYPE}" "http://${GRAFANA_USER}:${GRAFANA_PASSWD}@localhost:${GRAFANA_PORT}/api/datasources" -d '
{
  "name": "elasticsearch-datasource",
  "type": "elasticsearch",
  "access": "'"proxy"'",
  "isDefault": false,
  "url": "'"${ELASTICSEARCH_SERVICE_URL}"'",
  "database": "'"${ELASTICSEARCH_INDEX}"'"
}'

echo ""
echo "Importing default dashboards..."
for filename in ${DASHBOARD_LOCATION}/*.json; do
  echo "Importing ${filename} ..."
  curl -i -XPOST --data "@${filename}" -H "${HEADER_ACCEPT}" -H "${HEADER_CONTENT_TYPE}" "http://${GRAFANA_USER}:${GRAFANA_PASSWD}@localhost:${GRAFANA_PORT}/api/dashboards/db"
  echo ""
  echo "Done importing ${filename}"
done
echo ""
echo "Bringing Grafana back to the foreground"
fg

