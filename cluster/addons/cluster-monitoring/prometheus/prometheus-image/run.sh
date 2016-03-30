#!/bin/sh

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

export PROMETHEUS_ALERTMANAGER_URL=${PROMETHEUS_ALERTMANAGER_URL:-"http://prometheus-alertmanager:9093"}
export PROMETHEUS_RETENTION=${PROMETHEUS_RETENTION:-"168h"}
export PROMETHEUS_MEMORY_CHUNKS=${PROMETHEUS_MEMORY_CHUNKS:-"204800"}

SERVICE_DETAILS="$(/service-discovery -service_name=kubernetes -namespace=default)"
echo "$SERVICE_DETAILS"
CLUSTER_IP=$(echo "$SERVICE_DETAILS" |grep CLUSTER_IP|cut -d "=" -f 2)
PORT=$(echo "$SERVICE_DETAILS" |grep PORTS|cut -d "=" -f 2)
if [ -z "$CLUSTER_IP" ] || [ -z "$PORT" ]; then
    # If we can't auto discover it, fall back to using its DNS name
    export KUBERNETES_URL="https://kubernetes.default.svc"
else
    export KUBERNETES_URL="https://$CLUSTER_IP:$PORT"
fi

export TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
status=$(curl --header "Authorization: Bearer $TOKEN" --cacert /var/run/secrets/kubernetes.io/serviceaccount/ca.crt \
 --silent --head --location --output /dev/null --write-out '%{http_code}' "${KUBERNETES_URL}")
if [[ ${status} -eq 200 ]]; then
  echo "Kubernetes service is accessible."
  echo "Using ${KUBERNETES_URL}"
else
  echo "Trying to fall back to Kubernetes via ENV vars"
  echo "Trying https://$KUBERNETES_SERVICE_HOST:$KUBERNETES_SERVICE_PORT/"
  status=$(curl --header "Authorization: Bearer $TOKEN" --cacert /var/run/secrets/kubernetes.io/serviceaccount/ca.crt \
  --silent --head --location --output /dev/null --write-out '%{http_code}' "https://$KUBERNETES_SERVICE_HOST:$KUBERNETES_SERVICE_PORT/")
  if [[ ${status} -eq 200 ]]; then
    echo "Kubernetes service is up. Continuing with Prometheus via env vars."
    export KUBERNETES_URL="https://$KUBERNETES_SERVICE_HOST:$KUBERNETES_SERVICE_PORT"
  else
    echo "Unable to reach Kubernetes Service. Killing self"
    exit
  fi
fi

#Weird way to substitute env vars in alpine linux
echo $KUBERNETES_URL | xargs -I {} sed -i 's@KUBERNETES_SERVICE@{}@' /etc/prometheus/prometheus.yml

ALERT_SERVICE_DETAILS="$(/service-discovery -service_name=prometheus-alertmanager -namespace=kube-system)"
echo "$ALERT_SERVICE_DETAILS"
ALERT_CLUSTER_IP=$(echo "$ALERT_SERVICE_DETAILS" |grep CLUSTER_IP|cut -d "=" -f 2)
ALERT_PORT=$(echo "$ALERT_SERVICE_DETAILS" |grep PORTS|cut -d "=" -f 2)
if [ -z "$ALERT_CLUSTER_IP" ] || [ -z "$ALERT_PORT" ]; then
    # If we can't auto discover it, fall back to using its DNS name
    export PROMETHEUS_ALERTMANAGER_URL="http://prometheus-alertmanager:9093"
else
    export PROMETHEUS_ALERTMANAGER_URL="http://$ALERT_CLUSTER_IP:$ALERT_PORT"
fi

status=$(curl --silent --head --location --output /dev/null --write-out '%{http_code}' "${PROMETHEUS_ALERTMANAGER_URL}")
if [[ ${status} -eq 200 ]]; then
  echo "Alertmanager is up."
  echo "Trying ${PROMETHEUS_ALERTMANAGER_URL}"
else
  echo "Trying to fall back to Alertmanager via ENV vars"
  echo "Trying http://${PROMETHEUS_ALERTMANAGER_SERVICE_HOST}:${PROMETHEUS_ALERTMANAGER_SERVICE_PORT}"
  status=$(curl --silent --head --location --output /dev/null --write-out '%{http_code}' \
  "http://${PROMETHEUS_ALERTMANAGER_SERVICE_HOST}:${PROMETHEUS_ALERTMANAGER_SERVICE_PORT}")
  if [[ ${status} -eq 200 ]]; then
    echo "Alertmanager is up. Continuing with Prometheus via env vars."
    export PROMETHEUS_ALERTMANAGER_URL="http://${PROMETHEUS_ALERTMANAGER_SERVICE_HOST}:${PROMETHEUS_ALERTMANAGER_SERVICE_PORT}"
  else
    echo "Unable to reach Alertmanager. Killing self"
    exit
  fi
fi

prometheus -alertmanager.url=$PROMETHEUS_ALERTMANAGER_URL -config.file=/etc/prometheus/prometheus.yml \
    -storage.local.path=/prometheus \
    -web.console.libraries=/etc/prometheus/console_libraries \
    -web.console.templates=/etc/prometheus/consoles \
    -storage.local.memory-chunks=$PROMETHEUS_MEMORY_CHUNKS \
    -storage.local.max-chunks-to-persist=$PROMETHEUS_MEMORY_CHUNKS \
    -storage.local.retention=$PROMETHEUS_RETENTION
