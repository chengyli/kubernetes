logrotate:
  pkg:
    - installed

/etc/logrotate.conf:
  file:
    - managed
    - source: salt://logrotate/logrotate
    - template: jinja
    - user: root
    - group: root
    - mode: 644

{% set logrotate_files = ['kube-scheduler', 'kube-proxy', 'kubelet', 'kube-apiserver', 'kube-controller-manager'] %}
{% for file in logrotate_files %}
/etc/logrotate.d/{{ file }}:
  file:
    - managed
    - source: salt://logrotate/conf
    - template: jinja
    - user: root
    - group: root
    - mode: 644
    - context:
      file: {{ file }}
{% endfor %}

/etc/logrotate.d/docker:
  file:
    - managed
    - source: salt://logrotate/docker
    - template: jinja
    - user: root
    - group: root
    - mode: 644

/etc/logrotate.d/syslog:
  file:
    - managed
    - source: salt://logrotate/syslog
    - template: jinja
    - user: root
    - group: root
    - mode: 644

/etc/cron.hourly/logrotate:
  file:
    - managed
    - source: salt://logrotate/cron
    - template: jinja
    - user: root
    - group: root
    - mode: 755
