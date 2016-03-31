/*
Copyright 2014 The Kubernetes Authors All rights reserved.

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
	"fmt"
	"strings"
	"testing"
)

type testOpenstackClient struct {
}

func (osClient *testOpenstackClient) getDefaultTenant() (tenant string) {
	return ""
}

func TestReadConfig(t *testing.T) {

	cfg, err := readConfig(strings.NewReader(`
{
  "auth-url": "https://auth-url/v2.0",
  "user-name": "username",
  "password": "password",
  "region": "na-east",
  "tenant-id": "31213d3bc3144cfaacb60f040206baae",
  "tenant-name": "tenant"
}
`))
	if err != nil {
		t.Fatalf("Should succeed when a valid config is provided: %s", err)
	}
	if cfg.AuthUrl != "https://auth-url/v2.0" {
		t.Errorf("expected username \"https://auth-url/v2.0\" got %s", cfg.AuthUrl)
	}
	if cfg.Username != "username" {
		t.Errorf("expected username \"username\" got %s", cfg.Username)
	}
	if cfg.Password != "password" {
		t.Errorf("expected password \"password\" got %s", cfg.Password)
	}
	if cfg.Region != "na-east" {
		t.Errorf("expected region \"na-east\" got %s", cfg.Region)
	}
	if cfg.TenantId != "31213d3bc3144cfaacb60f040206baae" {
		t.Errorf("expected tenant id \"31213d3bc3144cfaacb60f040206baae\" got %s", cfg.TenantId)
	}
	if cfg.TenantName != "tenant" {
		t.Errorf("expected tenant name \"tenant\" got %s", cfg.TenantName)
	}
}

func TestAuthenticate(t *testing.T) {

	testCases := []struct {
		Token     string
		ExpectErr bool
		Name      string
	}{
		{
			Token:     "token1",
			ExpectErr: false,
			Name:      "Valid token",
		},
		{
			Token:     "token11",
			ExpectErr: true,
			Name:      "Invalid token",
		},
		{
			Token:     "token2",
			ExpectErr: false,
			Name:      "Valid Token",
		},
	}

	for k, testCase := range testCases {

		auth := KeystoneTokenAuthenticator{
			osClient: &testOpenstackClient{},
		}
		_, _, err := auth.AuthenticateToken(testCase.Token)
		if testCase.ExpectErr && err == nil {
			t.Errorf("%s: %s: Expected error, got none", testCase.Name, k)
			continue
		}
		if !testCase.ExpectErr && err != nil {
			t.Errorf("%s: %s: Did not expect error, got err:%v", testCase.Name, k, err)
			continue
		}
	}
}

func (osClient *testOpenstackClient) getTokenDetails(token string) (*Token, error) {

	validTokenMap := map[string]string{
		"token1": "user1",
		"token2": "user1",
		"token3": "user3",
		"token4": "user4",
		"token5": "user5",
		"token6": "user6",
	}

	if username, ok := validTokenMap[token]; ok {
		return &Token{
			ID:       token,
			Username: username,
			Tenant:   username,
		}, nil
	}
	return nil, fmt.Errorf("Invalid Token, keystone authentication failed")

}
