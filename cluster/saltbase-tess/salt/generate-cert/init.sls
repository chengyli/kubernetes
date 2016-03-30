{% set master_extra_sans=grains.get('master_extra_sans', '') %}
{% if grains.cloud is defined %}
  {% if grains.cloud == 'gce' %}
    {% set cert_ip='_use_gce_external_ip_' %}
  {% endif %}
  {% if grains.cloud == 'aws' %}
    {% set cert_ip='_use_aws_external_ip_' %}
  {% endif %}
  {% if grains.cloud == 'azure' %}
    {% set cert_ip='_use_azure_dns_name_' %}
  {% endif %}
  {% if grains.cloud == 'vagrant' %}
    {% set cert_ip=grains.ip_interfaces.eth1[0] %}
  {% endif %}
  {% if grains.cloud == 'vsphere' %}
    {% set cert_ip=grains.ip_interfaces.eth0[0] %}
  {% endif %}
  {% if grains.cloud == 'c3' %}
    {% set ips = salt['mine.get']('roles:kubernetes-master', 'network.ip_addrs', 'grain').values() -%}
    {% set cert_ip=ips[0][0] -%}
  {% endif %}
{% endif %}

# If there is a pillar defined, override any defaults.
{% if pillar['cert_ip'] is defined %}
  {% set cert_ip=pillar['cert_ip'] %}
{% endif %}

{% set certgen="make-cert.sh" %}
{% if cert_ip is defined %}
  {% set certgen="make-ca-cert.sh" %}
{% endif %}

kube-cert:
  group.present:
    - system: True

kubernetes-cert:
  cmd.script:
    - unless: test -f /srv/kubernetes/server.cert
    - source: salt://generate-cert/{{certgen}}
{% if cert_ip is defined %}
    - args: {{cert_ip}} {{master_extra_sans}}
{% if not grains.os_distribution is defined or grains.os_distribution != 'atomic' %}
    - require:
      - pkg: curl
{% endif %}
{% endif %}
{% if grains.os_distribution is defined and grains.os_distribution == 'atomic' %}
    - cwd: /tmp
{% else %}
    - cwd: /
{% endif %}
    - user: root
    - group: root
    - shell: /bin/bash
