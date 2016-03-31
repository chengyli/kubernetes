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
	"encoding/json"
	"fmt"
	"github.com/golang/glog"
	"io"
	"io/ioutil"
	"os"
)

func InitConfig(configFile string, ignoreComputeConfigFailures bool) (Config, error) {
	file := configFile
	if "" == file {
		glog.V(3).Info("no logfile from command line, trying TESS_CONFIG environment variable")
		file = os.Getenv("TESS_CONFIG")
		if "" == file {
			glog.V(1).Info("no value for TESS_CONFIG environment variable, trying default")
			file = "/etc/sysconfig/tess"
		}
	}
	data, _ := ioutil.ReadFile(file)
	glog.Info(string(data))

	var err error
	var config Config
	if config, err = getConfig(file); err != nil {
		glog.V(4).Infof("Filled configs from config file: %v", config)
		return config, err
	} else {
		if err = fillDefaults(&config); err != nil {
			glog.V(4).Infof("Filled configs from default configs file: %v", config)
			return config, err
		}
	}
	return config, err
}

func fillDefaults(config *Config) error {

	if config.Network.Pipework == "" {
		//assume pipework is in system path
		config.Network.Pipework = "pipework"
	}

	if config.Network.Bridge == "" {
		config.Network.Bridge = "obr0"
	}

	if config.Network.Device == "" {
		config.Network.Bridge = "eth1"
	}

	if config.Docker.Socket == "" {
		config.Docker.Socket = "unix:///var/run/docker.sock"
	}
	return nil
}

func getConfig(file string) (config Config, err error) {
	confFile, err := os.Open(file)
	defer confFile.Close()

	if err != nil {
		glog.V(3).Infof("error reading tess configuration file '%s'", file)
		return
	}
	return decode(confFile)
}

func decode(reader io.Reader) (config Config, err error) {
	decoder := json.NewDecoder(reader)

	err = decoder.Decode(&config)
	if err != nil {
		glog.V(3).Infof("error decoding json from reader %q", reader)
		return
	}

	return
}

func writeConfigToFile(config Config, fileLocation string) (successFlag bool, err error) {

	configData, err := json.Marshal(config)
	if err != nil {
		fmt.Errorf("Error marshalling config object to json while writing config to the file")
		return false, err
	}

	err = ioutil.WriteFile(fileLocation, []byte(configData), 0644)
	if err != nil {
		fmt.Errorf("Error while writing config object to file with error %s", err.Error())
		return false, err
	}
	return true, nil
}

type DockerConfig struct {
	Socket     string `json:"socket"`
	BackupFile string `json:"backupFile"`
}

type NetworkConfig struct {
	Bridge                string `json:"bridge"`
	Gateway               string `json:"gateway"` //the gateway to be configured in the  infra pod
	Device                string `json:"device"`  //the device to create in the pod
	CIDR                  string `json:"cidr"`
	Pipework              string `json:"pipework,omitempty"`   //path of pipework binary
	OvsDocker             string `json:"ovs_docker,omitempty"` //path of pipework binary
	ContainerSubnetPrefix string `json:"container_subnet_prefix"`
	DockerBridgeIP        string `json:"docker_bridge_ip"` // the docker bridge ip to use
	RouterId              string `json:"router_id"`
	NetworkId             string `json:"network_id"`
	ExternalNetworkId     string `json:"external_network_id"`
	SubnetId              string `json:"subnet_id"`
}

type ComputeConfig struct {
	UUID       string `json:"uuid"`
	PortID     string `json:"port_id"`
	Name       string `json:"name"`
	FloatingIP string `json:"floating_ip"`
	FQDN       string `json:"fqdn"`
	MetaFile   string `json:"metafile"`
}

type OpenstackCredentials struct {
	IdentityEndpoint string `json:"identityEndpoint"`
	Username         string `json:"username"`
	Password         string `json:"password,omitempty"`
	TenantID         string `json:"tenantId"`
	Region           string `json:"region"`
}

type KubernetesConfig struct {
	AuthConfig string `json:"authconfig"`
	ApiServer  string `json:"apiserver"`
	Hostname   string `json:"hostname"`
}

type Config struct {
	Network   NetworkConfig        `json:"network"`
	Compute   ComputeConfig        `json:"compute"`
	Openstack OpenstackCredentials `json:"openstack"`
	Docker    DockerConfig         `json:"docker"`
	Kube      KubernetesConfig     `json:"kube"`
}

func (config *Config) PersistToFile() (err error) {
	_, err = writeConfigToFile(*config, config.Docker.BackupFile)
	return err
}
