
/var/lib/kubelet/generate-kubecfg.sh:
  file.managed:
    - source: salt://kubecfg/generate.sh
    - makedirs: true
    - user: root
    - mode: 700


# we create a per role folder under /srv/kubecfg for each kube role such as kublet or proxy. This is inefficient and insecure
# (todo) We need to have the secure keys in pillar , if we are using salt for doing these



{% if 'salt-master' in grains.roles -%}
# each role should uniquely match the entries in the file /srv/kubernetes/known_tokens.csv
{% for role in ['kubelet', 'kube_proxy', 'controller_manager', 'scheduler'] %}

generate-{{role}}-kubecfg:
  cmd.run:
    - name: /var/lib/kubelet/generate-kubecfg.sh
    - unless: test -f /srv/salt/kubecfg/{{role}}/kubeconfig
    - cwd: /
    - user: root
    - group: root
    - shell: /bin/bash
    - env:
        - KUBE_SERVER: {{ pillar['api_servers_with_port'] }}
        - CA_CERT: /etc/ssl/kubernetes/ca.crt
        - CONTEXT: default
        - KUBECONFIG: /srv/salt/kubecfg/{{role}}/kubeconfig
        - KUBE_ROLE: {{role}}
    - require:
        - sls: certs

{% endfor %}
{% endif %}
