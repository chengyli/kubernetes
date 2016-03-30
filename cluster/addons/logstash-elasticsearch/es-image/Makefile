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
