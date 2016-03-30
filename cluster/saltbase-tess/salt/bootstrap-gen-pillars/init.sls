#todo(ashwin): currently this is over riding some pillar values to reflect the discovered values. We need to have a
# single authoritative place for all such configuration of the cluster (tess-master) and have custom pillars
# derive that from it.


{% if 'salt-master' in grains.roles -%}

# api_device is the device earmarked for api endpoints to listen on to
{% set api_device = grains.get('api_device', 'eth0') -%}
{% set ip_address =  salt['network.interfaces']()[api_device].inet[0].address -%}

apply_local_api_server_details:
    grains.present:
        - name:  cluster_external_ip
        - value:  {{ ip_address }}
        - failhard: True

# Not specify api server LB IP during kube-up
{% if pillar['cluster_external_ip'] is not defined -%}

#todo(get the port from config)
apply_api_server_details:
    file.append:
        - name: /srv/pillar/cluster-params.sls
        - text: |
           cluster_external_ip: {{ ip_address }}
        - require.in:
          - module.run: refresh_pillar

{% endif -%}
{% endif -%}