/etc/kubernetes/kube-master-addons.sh:
  file.managed:
    - source: salt://kube-master-addons/kube-master-addons.sh
    - user: root
    - group: root
    - mode: 755

{% if grains['os_family'] == 'RedHat' %}

{{ pillar.get('systemd_system_path') }}/kube-master-addons.service:
  file.managed:
    - source: salt://kube-master-addons/kube-master-addons.service
    - user: root
    - group: root

{% else %}

/etc/init.d/kube-master-addons:
  file.managed:
    - source: salt://kube-master-addons/initd
    - user: root
    - group: root
    - mode: 755

{% endif %}

/etc/kubernetes/kube-bins:
  file.directory:
    - user: root
    - group: root
    - dir_mode: 755
    - makeDirs: True

/etc/kubernetes/kube-bins/kube-apiserver.tar:
  file.managed:
    - source: salt://kube-bins/kube-apiserver.tar
    - user: root
    - group: root
    - mode: 755
    - makeDirs: True

/etc/kubernetes/kube-bins/kube-scheduler.tar:
  file.managed:
    - source: salt://kube-bins/kube-scheduler.tar
    - user: root
    - group: root
    - mode: 755
    - makeDirs: True

/etc/kubernetes/kube-bins/kube-controller-manager.tar:
  file.managed:
    - source: salt://kube-bins/kube-controller-manager.tar
    - user: root
    - group: root
    - mode: 755
    - makeDirs: True

# Used to restart kube-master-addons service each time salt is run
master-docker-image-tags:
  file.touch:
    - name: /srv/docker-images.sls

kube-master-addons:
  service.running:
    - enable: True
    - restart: True
    - watch:
      - file: master-docker-image-tags
      - file: /etc/kubernetes/kube-master-addons.sh
