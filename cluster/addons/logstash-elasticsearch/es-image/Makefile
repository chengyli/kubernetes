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

.PHONY:	elasticsearch_logging_discovery build push

# The current value of the tag to be used for building and
# pushing an image to ECR
TAG = 2.0.0-u1

build:
	docker build -t ecr.vip.ebayc3.com/kubernetes/elasticsearch:$(TAG) .

push:
	docker push ecr.vip.ebayc3.com/kubernetes/elasticsearch:$(TAG)

elasticsearch_logging_discovery:
	go build elasticsearch_logging_discovery.go

clean:
	rm elasticsearch_logging_discovery
