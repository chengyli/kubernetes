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
	"fmt"
	"net"

	docker "github.com/fsouza/go-dockerclient"
)

type TessNetServer struct {
	Config       Config
	DockerClient *docker.Client
	bridgeIPNet  *net.IPNet
}

func NewTessNeServer(config Config, subnet *net.IPNet) (*TessNetServer, error) {

	client, err := docker.NewClient(config.Docker.Socket)
	if err != nil {
		return nil, err
	}

	return &TessNetServer{config, client, subnet}, nil
}

//getDeviceIPNet gets the first IP of the device in question
func GetDeviceIpNet(dev string) (*net.IPNet, error) {

	iface, err := net.InterfaceByName(dev)
	if err != nil {
		return nil, fmt.Errorf("error getting inferface by name %s due to error %s", dev, err.Error())
	}

	addrs, err := iface.Addrs()
	if err != nil {
		return nil, fmt.Errorf("error getting addresses of the interface %s due to error %s", iface.Name, err.Error())
	}

	for _, addr := range addrs {
		if ipNet, ok := addr.(*net.IPNet); ok {
			if ip := ipNet.IP.To4(); ip == nil {
				return ipNet, nil
			} else {
				return &net.IPNet{ip, ipNet.Mask}, nil
			}
		}
	}

	return nil, fmt.Errorf("Could not find the device address")

}

func printNics(message string) {
	if ifaces, err := net.Interfaces(); err == nil {
		for _, iface := range ifaces {
			fmt.Printf("%s: %v \n", message, iface.Name)
		}
	} else {
		fmt.Printf("i%s: %s \n", message, err)
	}
}
