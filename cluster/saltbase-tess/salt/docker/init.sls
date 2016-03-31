{% if grains['os_family'] == 'RedHat' %}
{% set environment_file = '/etc/sysconfig/docker' %}
{% else %}
{% set environment_file = '/etc/default/docker' %}
{% endif %}

bridge-utils:
  pkg.installed

# Certificate for eBay private docker registry
/etc/docker/certs.d/commregistry-slc.corp.ebay.com/ca.crt:
  file.managed:
    - source: salt://docker/ca.crt
    - user: root
    - group: root
    - mode: 644
    - makedirs: true

# This is Docker's root directory
# where image layers, logs, etc., are stored.
docker-runtime-root:
  file.directory:
    - name: /mnt/docker
    - user: root
    - group: root
    - mode: 0755

{% if grains.os_family == 'RedHat' %}
{% if not grains.os_distribution is defined or grains.os_distribution != 'atomic' %}
docker-io:
  pkg:
    - installed
{% endif %}

{{ environment_file }}:
  file.managed:
    - source: salt://docker/docker-defaults
    - template: jinja
    - user: root
    - group: root
    - mode: 644
    - makedirs: true

{% if grains.os_distribution is defined and grains.os_distribution == 'atomic' %}
docker:
  service.running:
    - enable: True
    - watch:
      - file: {{ environment_file }}
{% else %}
docker:
  service.running:
    - enable: True
    - require:
      - pkg: docker-io
    - watch:
      - file: {{ environment_file }}
{% endif %}

net.ipv4.ip_forward:
  sysctl.present:
    - value: 1

cbr0:
  container_bridge.ensure:
    - cidr: {{ grains['cbr_cidr'] }}
    - ip: {{ grains['cbr_ip'] }}
    - mtu: 1460

{% else %}

{% if grains.cloud is defined
   and grains.cloud == 'gce' %}
# The default GCE images have ip_forwarding explicitly set to 0.
# Here we take care of commenting that out.
/etc/sysctl.d/11-gce-network-security.conf:
  file.replace:
    - pattern: '^net.ipv4.ip_forward=0'
    - repl: '# net.ipv4.ip_forward=0'
{% endif %}

# TODO: This should really be based on network strategy instead of os_family
net.ipv4.ip_forward:
  sysctl.present:
    - value: 1

cbr0:
  container_bridge.ensure:
    - cidr: {{ grains['cbr_cidr'] }}
    - ip: {{ grains['cbr_ip'] }}
    - mtu: 1460

purge-old-docker:
  pkg.removed:
    - pkgs:
      - lxc-docker-1.2.0
      - lxc-docker-1.3.0
      - lxc-docker-1.3.1
      - lxc-docker-1.3.2
      - lxc-docker-1.3.3
      - lxc-docker-1.4.0

{{ environment_file }}:
  file.managed:
    - source: salt://docker/docker-defaults
    - template: jinja
    - user: root
    - group: root
    - mode: 644
    - makedirs: true

# Docker is on the ContainerVM image by default. The following
# variables are provided for other cloud providers, and for testing and dire circumstances, to allow
# overriding the Docker version that's in a ContainerVM image.
#
# To change:
#
# 1. Find new deb name with:
#    curl https://get.docker.com/ubuntu/dists/docker/main/binary-amd64/Packages
# 2. Download based on that:
#    curl -O https://get.docker.com/ubuntu/pool/main/<...>
# 3. Upload to GCS:
#    gsutil cp <deb> gs://kubernetes-release/docker/<deb>
# 4. Make it world readable:
#    gsutil acl ch -R -g all:R gs://kubernetes-release/docker/<deb>
# 5. Get a hash of the deb:
#    shasum <deb>
# 6. Update override_deb, override_deb_sha1, override_docker_ver with new
#    deb name, new hash and new version

{% set storage_base='https://os-r-object.vip.slc.ebayc3.com/v1/KEY_630396909e6f4bf89d89477708c43e23/kubernetes-staging/packages/docker/' %}

{% set override_deb='lxc-docker-1.6.0_1.6.0_amd64.deb' %}
{% set override_deb_sha1='fdfd749362256877668e13e152d17fe22c64c420' %}
{% set override_docker_ver='1.6.0' %}

{% if grains.cloud is defined and grains.cloud == 'gce' %}
{% set override_deb='' %}
{% set override_deb_sha1='' %}
{% set override_docker_ver='' %}
{% endif %}

{% if override_docker_ver != '' %}
/var/cache/docker-install/{{ override_deb }}:
  file.managed:
    - source: {{ storage_base }}{{ override_deb }}
    - source_hash: sha1={{ override_deb_sha1 }}
    - user: root
    - group: root
    - mode: 644
    - makedirs: true

# Drop the license file into /usr/share so that everything is crystal clear.
/usr/share/doc/docker/apache.txt:
  file.managed:
    - source: {{ storage_base }}apache2.txt
    - source_hash: sha1=2b8b815229aa8a61e483fb4ba0588b8b6c491890
    - user: root
    - group: root
    - mode: 644
    - makedirs: true

lxc-docker-{{ override_docker_ver }}:
  pkg.installed:
    - sources:
      - lxc-docker-{{ override_docker_ver }}: /var/cache/docker-install/{{ override_deb }}
{% endif %}

docker:
  service.running:
    - enable: True
    - watch:
      - file: {{ environment_file }}
      - container_bridge: cbr0
    - require:
      - file: docker-runtime-root
{% if override_docker_ver != '' %}
      - pkg: lxc-docker-{{ override_docker_ver }}
{% endif %}

{% endif %}