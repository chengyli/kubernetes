/*
Copyright 2015 The Kubernetes Authors All rights reserved.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package tessnet

import (
	"io/ioutil"
	"os"
	"strings"
	"testing"
)

var configData = `
{
    "network": {
        "bridge": "obr0",
        "gateway": "172.20.0.1",
        "device": "eth0",
        "cidr": "172.20.0.0/24",
        "pipework": "/opt/pipework/bin/pipework",
        "container_subnet_prefix": "172.20.",
        "router_id": "0ef77969-0e48-4909-af8c-28240433c030",
        "network_id": "fdbfb508-1058-4345-8033-f1604b7c5063",
        "external_network_id": "c0667e7d-a6ff-4fda-8994-d96b23050a5a",
        "subnet_id": "db9a61f8-3853-4deb-a922-2770171e0677"
    },

    "docker": {
        "socket": "unix:///var/run/docker.sock",
        "backupFile": "/var/folders/_q/45twvpl12rbg7nzn9dqklmqw3906pv/T/kubernetes.XXXXXX.0j6gOWC3/kubernetes-minion-1-tess.conf"
    }

}
`

func TestReadConfig(t *testing.T) {
	config, err := InitConfig("", true)
	if err == nil {
		t.Errorf("no exception on inexistent file")
	}

	fileName := "/tmp/tess.conf"

	if err = ioutil.WriteFile(fileName, []byte(configData), 0644); err == nil {

		if config, err = InitConfig(fileName, true); err != nil {
			t.Errorf("failed to read config from file, %s", err.Error())
		} else {
			testValidate(config, t)
		}

		//now set env variable and check if that works
		os.Setenv("TESS_CONFIG", fileName)
		if config, err = InitConfig("", true); err != nil {
			t.Errorf("failed to read config from env, %s", err.Error())
		} else {
			testValidate(config, t)
		}

	} else {
		t.Logf("errror creating test file %v", err)
	}
}

func TestDecode(t *testing.T) {

	config, err := decode(strings.NewReader(configData))
	if err != nil {
		t.Errorf("error reading config: %q \n", config)
		return
	}
	testValidate(config, t)
}

func testValidate(config Config, t *testing.T) {

	if config.Network.Bridge != "obr0" {
		t.Errorf("got bridge '%v' \n", config.Network.Bridge)
	}
	if config.Network.Gateway != "172.20.0.1" {
		t.Errorf("got gateway '%v' \n", config.Network.Gateway)
	}
	if config.Network.Device != "eth0" {
		t.Errorf("got device '%v' \n", config.Network.Device)
	}
	if config.Network.CIDR != "172.20.0.0/24" {
		t.Errorf("got cidr '%v' \n", config.Network.CIDR)
	}
	if config.Network.Pipework != "/opt/pipework/bin/pipework" {
		t.Errorf("got pipework %v \n", config.Network.Pipework)
	}

	if config.Docker.Socket != "unix:///var/run/docker.sock" {
		t.Errorf("got docker socket '%v' \n", config.Docker.Socket)
	}

}
