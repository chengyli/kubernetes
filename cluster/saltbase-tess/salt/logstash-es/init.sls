/etc/kubernetes/manifests/logstash-es.yaml:
  file.managed:
    - source: salt://logstash-es/logstash-es.yaml
    - template: jinja
    - user: root
    - group: root
    - mode: 644
    - makedirs: true
    - dir_mode: 755
