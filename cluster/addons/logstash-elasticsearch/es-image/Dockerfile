# A Dockerfile for creating an Elasticsearch instance that is designed
# to work with Kubernetes logging. Inspired by the Dockerfile
# dockerfile/elasticsearch

FROM java:openjdk-7-jre
MAINTAINER Satnam Singh "satnam@google.com"

ENV DEBIAN_FRONTEND noninteractive

# add our user and group first to make sure their IDs get assigned consistently
RUN groupadd -r elastic && useradd -r -m -g elastic elastic

RUN apt-get update && \
    apt-get install -y curl cron python-pip && \
    apt-get clean

RUN pip install elasticsearch-curator

RUN cd / && \
    curl -O https://download.elasticsearch.org/elasticsearch/release/org/elasticsearch/distribution/tar/elasticsearch/2.0.0/elasticsearch-2.0.0.tar.gz && \
    tar xf elasticsearch-2.0.0.tar.gz && \
    rm elasticsearch-2.0.0.tar.gz && \
    mv elasticsearch-2.0.0 elasticsearch && \
    /elasticsearch/bin/plugin install mobz/elasticsearch-head && \
    /elasticsearch/bin/plugin install royrusso/elasticsearch-HQ && \
    /elasticsearch/bin/plugin install license && \
    /elasticsearch/bin/plugin install lmenezes/elasticsearch-kopf/ && \
    /elasticsearch/bin/plugin install lang-javascript && \
    /elasticsearch/bin/plugin install lang-python


RUN touch /var/log/cron.log
RUN mkdir -p /etc/cron.daily
ADD crontab /


COPY elasticsearch.yml /elasticsearch/config/elasticsearch.yml
COPY run.sh /
COPY elasticsearch_logging_discovery /

RUN cd / && \
    chown -R elastic:elastic /elasticsearch && \
    mkdir -p /data/kubernetes-logging && \
    chown -R elastic:elastic /data/kubernetes-logging && \
    chown elastic:elastic /elasticsearch_logging_discovery

VOLUME ["/data"]
EXPOSE 9200 9300

CMD ["/run.sh"]
