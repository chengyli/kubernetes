.PHONY:	build push

IMAGE = logstash-elasticsearch
TAG = 2.0.0-u1

build:	
	docker build -t ecr.vip.ebayc3.com/kubernetes/$(IMAGE):$(TAG) .

push:	
	docker push ecr.vip.ebayc3.com/kubernetes/$(IMAGE):$(TAG)
