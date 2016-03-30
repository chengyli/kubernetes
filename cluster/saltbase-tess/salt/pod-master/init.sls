# Copy pod-master manifest to manifests folder for kubelet.
/etc/kubernetes/pod-master-sources:
  file.directory:
    - name: /etc/kubernetes/pod-master-sources
    - user: root
    - group: root
    - mode: 0755

/etc/kubernetes/pod-master-sources/kube-scheduler.manifest:
  file.managed:
    - source: salt://kube-scheduler/kube-scheduler.manifest
    - template: jinja
    - user: root
    - group: root
    - mode: 644
    - makedirs: true
    - dir_mode: 755

/etc/kubernetes/pod-master-sources/kube-controller-manager.manifest:
  file.managed:
    - source: salt://kube-controller-manager/kube-controller-manager.manifest
    - template: jinja
    - user: root
    - group: root
    - mode: 644
    - makedirs: true
    - dir_mode: 755

/etc/kubernetes/manifests/pod-master.manifest:
  file.managed:
    - source: salt://pod-master/pod-master.manifest
    - template: jinja
    - user: root
    - group: root
    - mode: 644
    - makedirs: true
    - dir_mode: 755

/var/log/pod-master.log:
  file.managed:
    - user: root
    - group: root
    - mode: 644