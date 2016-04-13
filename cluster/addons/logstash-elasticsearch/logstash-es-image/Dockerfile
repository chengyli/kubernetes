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

# This Dockerfile will build an image that is configured
# to run Logstash

FROM logstash:2.0.0
MAINTAINER Thuc Nguyen "thuc@ebay.com"

RUN apt-get update && \
    apt-get install -y curl && \
    apt-get clean

# Install node/npm which is needed for elasticdump.
# elasticdump is used to import Kibana dashboards
RUN curl -sL https://deb.nodesource.com/setup_0.12 | bash - && \
    apt-get install -y nodejs && \
    npm install elasticdump -g

# This plugin is to inject environment variables
# into the log messages
RUN /opt/logstash/bin/plugin install logstash-filter-environment

# Additional patterns specific to kubernetes
COPY kube-grok-patterns /etc/logstash/patterns/kube-grok-patterns

# Various input/output configuration files
COPY environment_variables_filter.conf /etc/logstash/environment_variables_filter.conf
COPY kube-apiserver.conf /etc/logstash/kube-apiserver.conf
COPY kube-controller-manager.conf /etc/logstash/kube-controller-manager.conf
COPY messages.conf /etc/logstash/messages.conf
COPY etcd.conf /etc/logstash/etcd.conf
COPY kube-scheduler.conf /etc/logstash/kube-scheduler.conf
COPY output.conf /etc/logstash/output.conf

# ElasticSearch mappings
COPY logstash_mapping_template.json /logstash_mapping_template.json

# Default Kibana dashboards
COPY kibana_dashboard_data.json /kibana_dashboard_data.json

COPY run.sh /run.sh
CMD ["/run.sh"]
