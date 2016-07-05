/*
Copyright 2016 The Kubernetes Authors All rights reserved.

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

package unversioned

import (
	api "k8s.io/kubernetes/pkg/api"
	extensions "k8s.io/kubernetes/pkg/apis/extensions"
	watch "k8s.io/kubernetes/pkg/watch"
)

// LocalVolumeClaimsGetter has a method to return a LocalVolumeClaimInterface.
// A group's client should implement this interface.
type LocalVolumeClaimsGetter interface {
	LocalVolumeClaims(namespace string) LocalVolumeClaimInterface
}

// LocalVolumeClaimInterface has methods to work with LocalVolumeClaim resources.
type LocalVolumeClaimInterface interface {
	Create(*extensions.LocalVolumeClaim) (*extensions.LocalVolumeClaim, error)
	Update(*extensions.LocalVolumeClaim) (*extensions.LocalVolumeClaim, error)
	UpdateStatus(*extensions.LocalVolumeClaim) (*extensions.LocalVolumeClaim, error)
	Delete(name string, options *api.DeleteOptions) error
	DeleteCollection(options *api.DeleteOptions, listOptions api.ListOptions) error
	Get(name string) (*extensions.LocalVolumeClaim, error)
	List(opts api.ListOptions) (*extensions.LocalVolumeClaimList, error)
	Watch(opts api.ListOptions) (watch.Interface, error)
	LocalVolumeClaimExpansion
}

// localVolumeClaims implements LocalVolumeClaimInterface
type localVolumeClaims struct {
	client *ExtensionsClient
	ns     string
}

// newLocalVolumeClaims returns a LocalVolumeClaims
func newLocalVolumeClaims(c *ExtensionsClient, namespace string) *localVolumeClaims {
	return &localVolumeClaims{
		client: c,
		ns:     namespace,
	}
}

// Create takes the representation of a localVolumeClaim and creates it.  Returns the server's representation of the localVolumeClaim, and an error, if there is any.
func (c *localVolumeClaims) Create(localVolumeClaim *extensions.LocalVolumeClaim) (result *extensions.LocalVolumeClaim, err error) {
	result = &extensions.LocalVolumeClaim{}
	err = c.client.Post().
		Namespace(c.ns).
		Resource("localvolumeclaims").
		Body(localVolumeClaim).
		Do().
		Into(result)
	return
}

// Update takes the representation of a localVolumeClaim and updates it. Returns the server's representation of the localVolumeClaim, and an error, if there is any.
func (c *localVolumeClaims) Update(localVolumeClaim *extensions.LocalVolumeClaim) (result *extensions.LocalVolumeClaim, err error) {
	result = &extensions.LocalVolumeClaim{}
	err = c.client.Put().
		Namespace(c.ns).
		Resource("localvolumeclaims").
		Name(localVolumeClaim.Name).
		Body(localVolumeClaim).
		Do().
		Into(result)
	return
}

func (c *localVolumeClaims) UpdateStatus(localVolumeClaim *extensions.LocalVolumeClaim) (result *extensions.LocalVolumeClaim, err error) {
	result = &extensions.LocalVolumeClaim{}
	err = c.client.Put().
		Namespace(c.ns).
		Resource("localvolumeclaims").
		Name(localVolumeClaim.Name).
		SubResource("status").
		Body(localVolumeClaim).
		Do().
		Into(result)
	return
}

// Delete takes name of the localVolumeClaim and deletes it. Returns an error if one occurs.
func (c *localVolumeClaims) Delete(name string, options *api.DeleteOptions) error {
	return c.client.Delete().
		Namespace(c.ns).
		Resource("localvolumeclaims").
		Name(name).
		Body(options).
		Do().
		Error()
}

// DeleteCollection deletes a collection of objects.
func (c *localVolumeClaims) DeleteCollection(options *api.DeleteOptions, listOptions api.ListOptions) error {
	return c.client.Delete().
		Namespace(c.ns).
		Resource("localvolumeclaims").
		VersionedParams(&listOptions, api.ParameterCodec).
		Body(options).
		Do().
		Error()
}

// Get takes name of the localVolumeClaim, and returns the corresponding localVolumeClaim object, and an error if there is any.
func (c *localVolumeClaims) Get(name string) (result *extensions.LocalVolumeClaim, err error) {
	result = &extensions.LocalVolumeClaim{}
	err = c.client.Get().
		Namespace(c.ns).
		Resource("localvolumeclaims").
		Name(name).
		Do().
		Into(result)
	return
}

// List takes label and field selectors, and returns the list of LocalVolumeClaims that match those selectors.
func (c *localVolumeClaims) List(opts api.ListOptions) (result *extensions.LocalVolumeClaimList, err error) {
	result = &extensions.LocalVolumeClaimList{}
	err = c.client.Get().
		Namespace(c.ns).
		Resource("localvolumeclaims").
		VersionedParams(&opts, api.ParameterCodec).
		Do().
		Into(result)
	return
}

// Watch returns a watch.Interface that watches the requested localVolumeClaims.
func (c *localVolumeClaims) Watch(opts api.ListOptions) (watch.Interface, error) {
	return c.client.Get().
		Prefix("watch").
		Namespace(c.ns).
		Resource("localvolumeclaims").
		VersionedParams(&opts, api.ParameterCodec).
		Watch()
}
