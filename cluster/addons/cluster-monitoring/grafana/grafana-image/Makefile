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

TAG = 2.6.0-u1
PREFIX = ecr.vip.ebayc3.com/kubernetes

all: clean build container

build:
	GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -a -installsuffix cgo --ldflags '-w' ./influxdb_service_discovery.go

container:
	docker build -t $(PREFIX)/grafana:$(TAG) .

push:
	docker push $(PREFIX)/grafana:$(TAG)

clean:
	rm -f influxdb_service_discovery

