base:
  '*':
    - base
    - debian-auto-upgrades
    - c3
    - salt

  'roles:kubernetes-pool':
    - match: grain
    - hosts
    - certs
    - kubecfg
    - docker
    - sdn
    - helpers
    - cadvisor
    - kube-client-tools
    - kubelet
    - kube-proxy
    - rsyslog
{% if pillar.get('enable_node_logging', '').lower() == 'true' and pillar['logging_destination'] is defined %}
  {% if pillar['logging_destination'] == 'elasticsearch' %}
    - fluentd-es
  {% elif pillar['logging_destination'] == 'logstash-elasticsearch' %}
    - logstash-es
  {% endif %}
{% endif %}
    - logrotate
    - monit
    - sys-tunables

  'roles:salt-master':
    - match: grain
    - bootstrap-gen-pillars
    - hosts
    - certs
    - kubecfg

  'roles:kubernetes-master':
    - match: grain
    - hosts
    - certs
    - sdn
    - etcd
    - pod-master
    - kube-apiserver
    - kube-controller-manager
    - kube-scheduler
    - kube-proxy
    - monit
    - rsyslog
    - cadvisor
    - kube-client-tools
    - kube-master-addons
    - sys-tunables
{% if pillar.get('enable_node_logging', '').lower() == 'true' and pillar['logging_destination'] is defined %}
  {% if pillar['logging_destination'] == 'elasticsearch' %}
    - fluentd-es
  {% elif pillar['logging_destination'] == 'logstash-elasticsearch' %}
    - logstash-es
  {% endif %}
{% endif %}
    - logrotate
    - kube-addons
    - sdn
    - docker
    - kubelet
