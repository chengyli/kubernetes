.PHONY:	build push

TAG = 4.2.0-u1
NAMESPACE = kubernetes
IMAGE = kibana

build:
	docker build -t ecr.vip.ebayc3.com/$(NAMESPACE)/$(IMAGE):$(TAG) .

push:
	docker push ecr.vip.ebayc3.com/$(NAMESPACE)/$(IMAGE):$(TAG)
