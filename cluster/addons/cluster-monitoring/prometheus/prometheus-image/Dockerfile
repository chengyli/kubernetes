FROM       ecr.vip.ebayc3.com/kubernetes/prometheus:47e3bdc
MAINTAINER Marcin Wielgus <mwielgus@google.com>

RUN apk add --update -t curl
RUN apk add findutils
RUN apk add sed

RUN cd / && \
    rm -f service-discovery && \
    curl -X GET https://os-r-object.vip.slc.ebayc3.com/v1/KEY_630396909e6f4bf89d89477708c43e23/kubernetes-staging/service-discovery-linux-amd64 -o service-discovery && \
    chmod a+x service-discovery


COPY ./prometheus.yml /etc/prometheus/prometheus.yml
COPY ./rules.txt /etc/prometheus/rules.txt
COPY ./run.sh /

ENTRYPOINT ["sh", "/run.sh"]