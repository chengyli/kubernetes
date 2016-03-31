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

package keystone

import (
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"os"

	"github.com/golang/glog"
	"github.com/mitchellh/mapstructure"
	"github.com/rackspace/gophercloud"
	"github.com/rackspace/gophercloud/openstack"
	"github.com/rackspace/gophercloud/openstack/identity/v3/tokens"
	"k8s.io/kubernetes/pkg/auth/user"
)

type osConfig struct {
	AuthUrl    string `json:"auth-url"`
	Username   string `json:"user-name"`
	UserId     string `json:"user-id"`
	Password   string `json:"password"`
	ApiKey     string `json:"api-key"`
	TenantId   string `json:"tenant-id"`
	TenantName string `json:"tenant-name"`
	Region     string `json:"region"`
}

type OpenstackClient struct {
	provider   *gophercloud.ProviderClient
	authClient *gophercloud.ServiceClient
	config     *osConfig
}

type KeystoneTokenAuthenticator struct {
	osClient Interface
}

type Token struct {
	ID       string
	Username string
	Tenant   string
}

func newOpenstackClient(config *osConfig) (*OpenstackClient, error) {

	if config == nil {
		err := errors.New("no OpenStack cloud provider config file given")
		return nil, err
	}

	opts := gophercloud.AuthOptions{
		IdentityEndpoint: config.AuthUrl,
		Username:         config.Username,
		Password:         config.Password,
		TenantID:         config.TenantId,
		AllowReauth:      true,
	}

	provider, err := openstack.AuthenticatedClient(opts)
	if err != nil {
		glog.Info("Failed: Starting openstack authenticate client")
		return nil, err
	}
	authClient := openstack.NewIdentityV2(provider)

	return &OpenstackClient{
		provider,
		authClient,
		config,
	}, nil
}

func readConfig(reader io.Reader) (config osConfig, err error) {
	decoder := json.NewDecoder(reader)
	err = decoder.Decode(&config)
	if err != nil {
		return config, err
	}
	return config, nil
}

// New returns a token authenticator that validates user token using openstack keystone
func NewKeystoneTokenAuthenticator(configFile string) (*KeystoneTokenAuthenticator, error) {
	file, err := os.Open(configFile)
	if err != nil {
		return nil, err
	}
	defer file.Close()

	openstackConfig, err := readConfig(file)
	if err != nil {
		return nil, err
	}

	osClient, err := newOpenstackClient(&openstackConfig)
	if err != nil {
		return nil, err
	}

	ka := &KeystoneTokenAuthenticator{
		osClient: osClient,
	}
	return ka, nil
}

func (keystoneAuthenticator *KeystoneTokenAuthenticator) AuthenticateToken(token string) (user.Info, bool, error) {

	tokenDetails, err := keystoneAuthenticator.osClient.getTokenDetails(token)
	if err != nil {
		glog.Errorf("Keystone Authentication failed with error %s", err.Error())
		return nil, false, err
	}
	return &user.DefaultInfo{
		Name:   tokenDetails.Username,
		Groups: []string{tokenDetails.Tenant},
	}, true, nil
}

//TODO: Fork gopher cloud and make changes to the project than having this logic here https://github.corp.ebay.com/tess/tess/issues/593
func (osClient *OpenstackClient) getTokenDetails(token string) (*Token, error) {
	r := getToken(osClient.authClient, token)
	if r.Err != nil {
		return nil, r.Err
	}

	var response struct {
		Access struct {
			Token struct {
				ExpiresAt string `mapstructure:"expires"`
				Tenant    struct {
					Name string `mapstructure:"name"`
					ID   string `mapstructure:"id"`
				} `mapstructure:"tenant"`
			} `mapstructure:"token"`
			User struct {
				Username string `mapstructure:"username"`
			} `mapstructure:"user"`
		} `mapstructure:"access"`
	}

	err := mapstructure.Decode(r.Body, &response)
	if err != nil {
		return nil, err
	}

	return &Token{
		ID:       token,
		Username: response.Access.User.Username,
		Tenant:   response.Access.Token.Tenant.Name,
	}, err
}

// Get validates and retrieves information about another token.
func getToken(c *gophercloud.ServiceClient, token string) tokens.GetResult {
	var result tokens.GetResult
	var response *http.Response
	response, result.Err = c.Request("GET", tokenURL(c, token), gophercloud.RequestOpts{
		JSONResponse: &result.Body,
		OkCodes:      []int{200, 203},
	})
	if result.Err != nil {
		return result
	}
	result.Header = response.Header
	return result
}

func tokenURL(c *gophercloud.ServiceClient, token string) string {
	return c.ServiceURL("tokens", token)
}
