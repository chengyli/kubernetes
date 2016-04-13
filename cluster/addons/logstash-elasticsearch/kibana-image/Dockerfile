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

# A Dockerfile for creating a Kibana container that is designed
# to work with Kubernetes logging.

FROM java:openjdk-7-jre
MAINTAINER Satnam Singh "satnam@google.com"

ENV DEBIAN_FRONTEND noninteractive

RUN apt-get update && \
    apt-get install -y curl && \
    apt-get clean

RUN cd / && \
    curl -X GET https://download.elastic.co/kibana/kibana/kibana-4.2.0-linux-x64.tar.gz -o kibana.tar.gz && \
    tar xf kibana.tar.gz && \
    mv kibana-4.2.0-linux-x64 kibana && \
    rm kibana.tar.gz && \
    rm -f service-discovery && \
    curl -X GET https://os-r-object.vip.slc.ebayc3.com/v1/KEY_630396909e6f4bf89d89477708c43e23/kubernetes-staging/service-discovery-linux-amd64 -o service-discovery && \
    chmod a+x service-discovery

COPY run.sh /run.sh
COPY kibana.yml /kibana/config/

RUN /kibana/bin/kibana plugin --install kibana/timelion

EXPOSE 5601
CMD ["/run.sh"]
