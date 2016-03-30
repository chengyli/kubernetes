# Logstash Image For Kubernetes

## What's In It
This directory contains the source files needed to make a Docker image
that collects log files using [Logstash](https://www.elastic.co/products/logstash)
and sends them to an instance of [Elasticsearch](http://www.elasticsearch.org/).
This image is designed to be used as part of the [Kubernetes](https://github.com/kubernetes/kubernetes)
cluster bring up process. It contains the following:

* Logstash.
* Configuration files with patterns to parse various logs.
* ElasticSearch mappings for fields extracted by these patterns.
* Default Kibana dashboards based on extracted fields.
* Output to ElasticSearch.

## How To Build It

1. cd $GOPATH/src/k8s.io/kubernetes/cluster/addons/logstash-elasticsearch/logstash-es-image

2. make build

[![Analytics](https://kubernetes-site.appspot.com/UA-36037335-10/GitHub/cluster/addons/logstash-elasticsearch/logstash-es-image/README.md?pixel)]()
