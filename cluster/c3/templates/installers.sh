#!/bin/bash

# Copyright 2015 The Kubernetes Authors All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Retry a download until we get it.
#
# $1 is the URL to download

install-nginx() {

  mkdir -p /var/cache/yum-rpm/nginx
  cd /var/cache/yum-rpm/nginx

  RPMS=(
    openssl-libs-1.0.1k-11.fc21.x86_64.rpm
    make-4.0-3.fc21.x86_64.rpm
    openssl-1.0.1k-11.fc21.x86_64.rpm
    perl-libs-5.18.4-308.fc21.x86_64.rpm
    perl-5.18.4-308.fc21.x86_64.rpm
    perl-Term-ANSIColor-4.03-2.fc21.noarch.rpm
    perl-HTTP-Tiny-0.043-2.fc21.noarch.rpm
    perl-Pod-Perldoc-3.23-2.fc21.noarch.rpm
    perl-podlators-2.5.3-2.fc21.noarch.rpm
    perl-version-0.99.12-1.fc21.x86_64.rpm
    perl-Pod-Escapes-1.04-308.fc21.noarch.rpm
    perl-Text-ParseWords-3.30-1.fc21.noarch.rpm
    perl-Encode-2.75-1.fc21.x86_64.rpm
    perl-parent-0.228-2.fc21.noarch.rpm
    perl-Pod-Usage-1.67-1.fc21.noarch.rpm
    perl-macros-5.18.4-308.fc21.x86_64.rpm
    perl-constant-1.27-293.fc21.noarch.rpm
    perl-Exporter-5.70-2.fc21.noarch.rpm
    perl-Time-HiRes-1.9726-3.fc21.x86_64.rpm
    perl-File-Path-2.09-293.fc21.noarch.rpm
    perl-Time-Local-1.2300-292.fc21.noarch.rpm
    perl-Filter-1.54-1.fc21.x86_64.rpm
    perl-Carp-1.36-1.fc21.noarch.rpm
    perl-Storable-2.51-2.fc21.x86_64.rpm
    perl-threads-1.92-3.fc21.x86_64.rpm
    perl-Socket-2.020-1.fc21.x86_64.rpm
    perl-File-Temp-0.23.04-2.fc21.noarch.rpm
    perl-Module-CoreList-3.13-308.fc21.noarch.rpm
    perl-threads-shared-1.46-4.fc21.x86_64.rpm
    perl-Scalar-List-Utils-1.42-1.fc21.x86_64.rpm
    perl-Pod-Simple-3.29-1.fc21.noarch.rpm
    perl-Getopt-Long-2.47-1.fc21.noarch.rpm
    perl-PathTools-3.47-3.fc21.x86_64.rpm
    perl-5.18.4-308.fc21.x86_64.rpm
    libjpeg-turbo-1.3.1-5.fc21.x86_64.rpm
    libpng-1.6.10-3.fc21.x86_64.rpm
    freetype-2.5.3-16.fc21.x86_64.rpm
    fontpackages-filesystem-1.44-10.fc21.noarch.rpm
    lyx-fonts-2.1.3-1.fc21.noarch.rpm
    fontconfig-2.11.1-5.fc21.x86_64.rpm
    GeoIP-GeoLite-data-2015.05-1.fc21.noarch.rpm
    GeoIP-GeoLite-data-extra-2015.05-1.fc21.noarch.rpm
    libXau-1.0.8-4.fc21.x86_64.rpm
    libxcb-1.11-5.fc21.x86_64.rpm
    libxslt-1.1.28-8.fc21.x86_64.rpm
    geoipupdate-2.2.1-2.fc21.x86_64.rpm
    GeoIP-1.6.5-1.fc21.x86_64.rpm
    libunwind-1.1-10.fc21.x86_64.rpm
    gperftools-libs-2.2.1-2.fc21.x86_64.rpm
    jbigkit-libs-2.1-2.fc21.x86_64.rpm
    libtiff-4.0.3-20.fc21.x86_64.rpm
    nginx-filesystem-1.6.3-4.fc21.noarch.rpm
    libX11-common-1.6.2-2.fc21.noarch.rpm
    libX11-1.6.2-2.fc21.x86_64.rpm
    libXpm-3.5.11-3.fc21.x86_64.rpm
    libvpx-1.3.0-6.fc21.x86_64.rpm
    gd-2.1.0-8.fc21.x86_64.rpm
    nginx-1.6.3-4.fc21.x86_64.rpm
  )

  URL_BASE="https://os-r-object.vip.slc.ebayc3.com/v1/KEY_630396909e6f4bf89d89477708c43e23/tess/yum-utils"
  rpms=""
  for rpm in "${RPMS[@]}"; do
    echo ">>>>> Downloading Installing ${rpm}"
    download-or-bust "${URL_BASE}/${rpm}"
    rpms="${rpms} ${rpm}"
  done
  echo $rpms
  yum -y install $rpms

}

install-rsyslog() {

  mkdir -p /var/cache/yum-rpm/rsyslog
  cd /var/cache/yum-rpm/rsyslog

  RPMS=(
    json-c-0.12-5.fc21.x86_64.rpm
    libestr-0.1.9-4.fc21.x86_64.rpm
    logrotate-3.8.7-4.fc21.x86_64.rpm
    liblogging-stdlog-1.0.4-4.fc21.x86_64.rpm
    rsyslog-7.4.10-5.fc21.x86_64.rpm
  )

  URL_BASE="https://os-r-object.vip.slc.ebayc3.com/v1/KEY_630396909e6f4bf89d89477708c43e23/tess/yum-utils"
  rpms=""
  for rpm in "${RPMS[@]}"; do
    echo ">>>>> Downloading Installing ${rpm}"
    download-or-bust "${URL_BASE}/${rpm}"
    rpms="${rpms} ${rpm}"
  done
  echo $rpms
  yum -y install $rpms
}

install-openvswitch() {

  mkdir -p /var/cache/yum-rpm/openvswitch
  cd /var/cache/yum-rpm/openvswitch

  RPMS=(
    openssl-libs-1.0.1k-11.fc21.x86_64.rpm
    make-4.0-3.fc21.x86_64.rpm
    openssl-1.0.1k-11.fc21.x86_64.rpm
    openvswitch-2.3.2-1.fc21.x86_64.rpm
  )

  UURL_BASE="https://os-r-object.vip.slc.ebayc3.com/v1/KEY_630396909e6f4bf89d89477708c43e23/tess/yum-utils"
  rpms=""
  for rpm in "${RPMS[@]}"; do
    echo ">>>>> Downloading Installing ${rpm}"
    download-or-bust "${URL_BASE}/${rpm}"
    rpms="${rpms} ${rpm}"
  done
  echo $rpms
  yum -y install $rpms
}

install-bridgeutils() {

  mkdir -p /var/cache/yum-rpm/bridgeutils
  cd /var/cache/yum-rpm/bridgeutils

  RPMS=(
    bridge-utils-1.5-10.fc21.x86_64.rpm
  )

  URL_BASE="https://os-r-object.vip.slc.ebayc3.com/v1/KEY_630396909e6f4bf89d89477708c43e23/tess/yum-utils"
  rpms=""
  for rpm in "${RPMS[@]}"; do
    echo ">>>>> Downloading Installing ${rpm}"
    download-or-bust "${URL_BASE}/${rpm}"
    rpms="${rpms} ${rpm}"
  done
  echo $rpms
  yum -y install $rpms
}

install-docker() {

  mkdir -p /var/cache/yum-rpm/docker
  cd /var/cache/yum-rpm/docker

  RPMS=(
    docker-io-1.6.2-3.gitc3ca5bb.fc21.x86_64.rpm
  )

  URL_BASE="https://os-r-object.vip.slc.ebayc3.com/v1/KEY_630396909e6f4bf89d89477708c43e23/tess/yum-utils"
  rpms=""
  for rpm in "${RPMS[@]}"; do
    echo ">>>>> Downloading Installing ${rpm}"
    download-or-bust "${URL_BASE}/${rpm}"
    rpms="${rpms} ${rpm}"
  done
  echo $rpms
  yum -y install $rpms
}

install-salt() {

  mkdir -p /var/cache/yum-rpm
  cd /var/cache/yum-rpm

  RPMS=(
    which-2.20-8.fc21.x86_64.rpm
    hwdata-0.279-1.fc21.noarch.rpm
    libtommath-0.42.0-5.fc21.x86_64.rpm
    libtomcrypt-1.17-24.fc21.x86_64.rpm
    m2crypto-0.21.1-18.fc21.x86_64.rpm
    openpgm-5.2.122-4.fc21.x86_64.rpm
    pciutils-libs-3.3.0-1.fc21.x86_64.rpm
    pciutils-3.3.0-1.fc21.x86_64.rpm
    pytz-2012d-7.fc21.noarch.rpm
    python-babel-1.3-7.fc21.noarch.rpm
    python-crypto-2.6.1-6.fc21.x86_64.rpm
    python-markupsafe-0.23-6.fc21.x86_64.rpm
    python-jinja2-2.7.3-2.fc21.noarch.rpm
    python-kitchen-1.2.1-2.fc21.noarch.rpm
    python-msgpack-0.4.6-1.fc21.x86_64.rpm
    zeromq3-3.2.5-1.fc21.x86_64.rpm
    python-zmq-14.3.1-1.fc21.x86_64.rpm
    yum-utils-1.1.31-27.fc21.noarch.rpm
    systemd-libs-216-12.fc21.x86_64.rpm
    systemd-216-12.fc21.x86_64.rpm
    systemd-python-216-12.fc21.x86_64.rpm
    python-cherrypy-3.2.2-6.fc21.noarch.rpm
    salt-2014.7.5-1.fc21.noarch.rpm
    salt-minion-2014.7.5-1.fc21.noarch.rpm
  )

  URL_BASE="https://os-r-object.vip.slc.ebayc3.com/v1/KEY_630396909e6f4bf89d89477708c43e23/tess/yum-utils"

  if [[ ${1-} == '--master' ]]; then
    RPMS+=(salt-master-2014.7.5-1.fc21.noarch.rpm)
    RPMS+=(salt-api-2014.7.5-1.fc21.noarch.rpm)
  fi

  if [[ ${1-} == '--master' ]]; then
    if ! which salt-master &>/dev/null; then
      # Configure the salt-api
      cat <<EOF >/etc/salt/master.d/salt-api.conf
external_auth:
  pam:
    ${MASTER_USER}:
      - .*
rest_cherrypy:
  port: 8000
  host: 127.0.0.1
  disable_ssl: True
  webhook_disable_auth: True
EOF
    fi
  fi

  if ! which salt-minion >/dev/null 2>&1; then

    for rpm in "${RPMS[@]}"; do
      echo ">>>>> Downloading Installing ${rpm}"
      download-or-bust "${URL_BASE}/${rpm}"
      yum -y install "${rpm}"
    done

    if [[ ${1-} == '--master' ]]; then
      echo "Adding master configuration to execute custom pillars"
      printf '%s\n\n%s\n  %s\n' 'extension_modules: /srv/modules' 'ext_pillar:' '- custom_pillar:' >> /etc/salt/master
      # issue 877 enable salt master key gpg sign
      printf 'master_sign_pubkey: True\n' >> /etc/salt/master
      systemctl start salt-api
      systemctl start salt-master
      #issue 802 store salt keys. wait for salt key generate
      sleep 30
    fi
    # issue 877 enable salt master key gpg sign
    printf 'verify_master_pubkey_sign: True\n' >> /etc/salt/minion
    #start then pki/minion directory created
    systemctl start salt-minion

  fi
  #issue 802 store salt keys. cp to tmp, and bootstrap can get them to upload
  sleep 3
  if [ -f /etc/salt/pki/master/master_sign.pub -a -f /etc/salt/pki/master/master.pub ]; then
      cp /etc/salt/pki/master/master_sign.pub /etc/salt/pki/minion/ >/dev/null
      cp /etc/salt/pki/master/master.pub /etc/salt/pki/minion/ >/dev/null
  else
      eval  "${SALT_PUB_KEY_CMD}"
      eval  "${SALT_SIGN_KEY_CMD}"
  fi
  #restart to enable salt key checking
  systemctl restart salt-minion
}