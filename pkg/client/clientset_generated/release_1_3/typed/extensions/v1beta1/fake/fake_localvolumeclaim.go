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

package fake

import (
	api "k8s.io/kubernetes/pkg/api"
	unversioned "k8s.io/kubernetes/pkg/api/unversioned"
	v1beta1 "k8s.io/kubernetes/pkg/apis/extensions/v1beta1"
	core "k8s.io/kubernetes/pkg/client/testing/core"
	labels "k8s.io/kubernetes/pkg/labels"
	watch "k8s.io/kubernetes/pkg/watch"
)

// FakeLocalVolumeClaims implements LocalVolumeClaimInterface
type FakeLocalVolumeClaims struct {
	Fake *FakeExtensions
	ns   string
}

var localvolumeclaimsResource = unversioned.GroupVersionResource{Group: "extensions", Version: "v1beta1", Resource: "localvolumeclaims"}

func (c *FakeLocalVolumeClaims) Create(localVolumeClaim *v1beta1.LocalVolumeClaim) (result *v1beta1.LocalVolumeClaim, err error) {
	obj, err := c.Fake.
		Invokes(core.NewCreateAction(localvolumeclaimsResource, c.ns, localVolumeClaim), &v1beta1.LocalVolumeClaim{})

	if obj == nil {
		return nil, err
	}
	return obj.(*v1beta1.LocalVolumeClaim), err
}

func (c *FakeLocalVolumeClaims) Update(localVolumeClaim *v1beta1.LocalVolumeClaim) (result *v1beta1.LocalVolumeClaim, err error) {
	obj, err := c.Fake.
		Invokes(core.NewUpdateAction(localvolumeclaimsResource, c.ns, localVolumeClaim), &v1beta1.LocalVolumeClaim{})

	if obj == nil {
		return nil, err
	}
	return obj.(*v1beta1.LocalVolumeClaim), err
}

func (c *FakeLocalVolumeClaims) UpdateStatus(localVolumeClaim *v1beta1.LocalVolumeClaim) (*v1beta1.LocalVolumeClaim, error) {
	obj, err := c.Fake.
		Invokes(core.NewUpdateSubresourceAction(localvolumeclaimsResource, "status", c.ns, localVolumeClaim), &v1beta1.LocalVolumeClaim{})

	if obj == nil {
		return nil, err
	}
	return obj.(*v1beta1.LocalVolumeClaim), err
}

func (c *FakeLocalVolumeClaims) Delete(name string, options *api.DeleteOptions) error {
	_, err := c.Fake.
		Invokes(core.NewDeleteAction(localvolumeclaimsResource, c.ns, name), &v1beta1.LocalVolumeClaim{})

	return err
}

func (c *FakeLocalVolumeClaims) DeleteCollection(options *api.DeleteOptions, listOptions api.ListOptions) error {
	action := core.NewDeleteCollectionAction(localvolumeclaimsResource, c.ns, listOptions)

	_, err := c.Fake.Invokes(action, &v1beta1.LocalVolumeClaimList{})
	return err
}

func (c *FakeLocalVolumeClaims) Get(name string) (result *v1beta1.LocalVolumeClaim, err error) {
	obj, err := c.Fake.
		Invokes(core.NewGetAction(localvolumeclaimsResource, c.ns, name), &v1beta1.LocalVolumeClaim{})

	if obj == nil {
		return nil, err
	}
	return obj.(*v1beta1.LocalVolumeClaim), err
}

func (c *FakeLocalVolumeClaims) List(opts api.ListOptions) (result *v1beta1.LocalVolumeClaimList, err error) {
	obj, err := c.Fake.
		Invokes(core.NewListAction(localvolumeclaimsResource, c.ns, opts), &v1beta1.LocalVolumeClaimList{})

	if obj == nil {
		return nil, err
	}

	label := opts.LabelSelector
	if label == nil {
		label = labels.Everything()
	}
	list := &v1beta1.LocalVolumeClaimList{}
	for _, item := range obj.(*v1beta1.LocalVolumeClaimList).Items {
		if label.Matches(labels.Set(item.Labels)) {
			list.Items = append(list.Items, item)
		}
	}
	return list, err
}

// Watch returns a watch.Interface that watches the requested localVolumeClaims.
func (c *FakeLocalVolumeClaims) Watch(opts api.ListOptions) (watch.Interface, error) {
	return c.Fake.
		InvokesWatch(core.NewWatchAction(localvolumeclaimsResource, c.ns, opts))

}
