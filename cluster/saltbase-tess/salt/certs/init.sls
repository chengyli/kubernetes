kube-cert:
  group.present:
    - system: True


# Generate certificates on the salt-master under the following directory tree, we then symlink it to be under the
# salt tree, so that it can be copied to the minions using salt file system. When we have vault, minions would copy
# directly from vault

/srv/certs:
   file.directory:
     - group: root
     - user: root
     - dir_mode: 700
     - file_mode: 600


{% if 'salt-master' in grains.roles -%}

{% set master_extra_sans=pillar['master_extra_sans'] %}
{% if grains.cloud is defined %}
  {% if grains.cloud == 'vagrant' %}
    {% set cert_ip=grains.ip_interfaces.eth1[0] %}
  {% endif %}
  {% if grains.cloud == 'c3' %}
     {% set api_device = grains.get('api_device', 'eth0') -%}
     {% set cert_ip =  salt['network.interfaces']()[api_device].inet[0].address -%}
  {% endif %}
{% endif %}

# If there is a pillar defined, override any defaults.
{% if pillar['cert_ip'] is defined %}
  {% set cert_ip=pillar['cert_ip'] %}
{% endif %}


{% set certgen="make-ca-cert.sh" %}

# generates the certificate for the tessca and also signs a certificate that is to be used by the apiserver
# todo: change the bash script to generate individual certs as needed
generate-server-certs:
  cmd.script:
    - unless: test -f /srv/certs/tessca.crt && test -f /srv/certs/server.crt && test -f /srv/certs/server.key
    - source: salt://certs/{{certgen}}
    #todo(remove to expect api domain names or stable ips (lb, cluster_ip) always)
{% if cert_ip is defined %}
    - args: {{cert_ip}} {{master_extra_sans}}
{% if not grains.os_distribution is defined or grains.os_distribution != 'atomic' %}
    - require:
      - pkg: curl
{% endif %}
{% endif %}
    - env:
       - CERT_DIR: /srv/certs
{% if grains.os_distribution is defined and grains.os_distribution == 'atomic' %}
    - cwd: /tmp
{% else %}
    - cwd: /
{% endif %}
    - user: root
    - group: root
    - shell: /bin/bash

/srv/salt/certs/tocopy:
    file.symlink:
        - target: /srv/certs

{% endif %} # if salt-master machine


# apiserver needs keys for TLS
{% if 'kubernetes-master' in  grains.roles -%}

/etc/ssl/kubernetes/server.crt:
    file.managed:
        - source: salt://certs/tocopy/server.crt
        - mode: 600
        - makedirs: True

/etc/ssl/kubernetes/server.key:
    file.managed:
        - source: salt://certs/tocopy/server.key
        - mode: 600
        - makedirs: True

/etc/ssl/kubernetes/etcd.key:
    file.managed:
        - source: salt://certs/tocopy/etcd.key
        - mode: 600
        - makedirs: True

/etc/ssl/kubernetes/etcd.crt:
    file.managed:
        - source: salt://certs/tocopy/etcd.crt
        - mode: 600
        - makedirs: True

{% endif %}

# everyone in the cluster needs tess-ca
/etc/ssl/kubernetes/ca.crt:
    file.managed:
        - source: salt://certs/tocopy/tessca.crt
        - mode: 600
        - makedirs: True
