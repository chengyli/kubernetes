# Copyright 2016 The Kubernetes Authors All rights reserved.
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

#
# Stock Grafana + a few custom dashboards
#

FROM grafana/grafana:2.6.0

RUN apt-get update && \
    apt-get install -y curl

COPY dashboards /dashboards
COPY influxdb_service_discovery /influxdb_service_discovery
COPY run.sh /run.sh

RUN cd / && \
    rm -f service-discovery && \
    curl -X GET https://os-r-object.vip.slc.ebayc3.com/v1/KEY_630396909e6f4bf89d89477708c43e23/kubernetes-staging/service-discovery-linux-amd64 -o service-discovery && \
    chmod a+x service-discovery

EXPOSE 3000
ENTRYPOINT /run.sh
