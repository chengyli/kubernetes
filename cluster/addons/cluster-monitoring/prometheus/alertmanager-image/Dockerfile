FROM    ecr.vip.ebayc3.com/kubernetes/prometheus-alertmanager:0.0.4

COPY ./alertmanager.conf /etc/alertmanager/alertmanager.conf
COPY ./run.sh /
ENTRYPOINT ["sh", "/run.sh"]