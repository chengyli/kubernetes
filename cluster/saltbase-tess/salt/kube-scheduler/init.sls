# Ensure we are starting scheduler with a kubeconfig, see kubecfg sls for details
/var/lib/kube-scheduler/kubeconfig:
    file.managed:
      - source: salt://kubecfg/scheduler/kubeconfig
      - makedirs: true
      - user: root
      - group: root
      - chmod: 400

# Copy kube-scheduler manifest to manifests folder for kubelet.
/etc/kubernetes/manifests/kube-scheduler.manifest:
  file.managed:
    - source: salt://kube-scheduler/kube-scheduler.manifest
    - template: jinja
    - user: root
    - group: root
    - mode: 644
    - makedirs: true
    - dir_mode: 755

/var/log/kube-scheduler.log:
  file.managed:
    - user: root
    - group: root
    - mode: 644

#stop legacy kube-scheduler service 
stop_kube-scheduler:
  service.dead:
    - name: kube-scheduler
    - enable: None
