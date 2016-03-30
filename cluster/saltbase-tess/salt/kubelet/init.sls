{% if grains['os_family'] == 'RedHat' %}
{% set environment_file = '/etc/sysconfig/kubelet' %}
{% else %}
{% set environment_file = '/etc/default/kubelet' %}
{% endif %}

{{ environment_file}}:
  file.managed:
    - source: salt://kubelet/default
    - template: jinja
    - user: root
    - group: root
    - mode: 644

/usr/local/bin/kubelet:
  file.managed:
    - source: salt://kube-bins/kubelet
    - user: root
    - group: root
    - mode: 755

# This is Kubelet's root directory
# where pod data is stored, including emptyDir
kubelet-runtime-root:
  file.directory:
    - name: /mnt/kubelet
    - user: root
    - group: root
    - mode: 0755

{% if grains['os_family'] == 'RedHat' %}

{{ pillar.get('systemd_system_path') }}/kubelet.service:
  file.managed:
    - source: salt://kubelet/kubelet.service
    - user: root
    - group: root

{% else %}

/etc/init.d/kubelet:
  file.managed:
    - source: salt://kubelet/initd
    - user: root
    - group: root
    - mode: 755

{% endif %}


/var/lib/kubelet/kubeconfig:
    file.managed:
      - source: salt://kubecfg/kubelet/kubeconfig
      - makedirs: true
      - user: root
      - group: root
      - chmod: 400

kubelet:
  service.running:
    - enable: True
    - watch:
      - file: /usr/local/bin/kubelet
{% if grains['os_family'] != 'RedHat' %}
      - file: /etc/init.d/kubelet
{% endif %}
      - file: {{ environment_file }}
      - file: /var/lib/kubelet/kubeconfig
      - file: /etc/hosts
    - require:
        - file: kubelet-runtime-root

# mount openstack config driver

# set auto mount etcd disk
/mnt/config:
  mount.mounted:
    - device: LABEL=config-2
    - fstype: vfat
    - mkmnt: True
    - opts:
      - defaults
