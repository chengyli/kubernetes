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

// FakeLocalVolumes implements LocalVolumeInterface
type FakeLocalVolumes struct {
	Fake *FakeExtensions
}

var localvolumesResource = unversioned.GroupVersionResource{Group: "extensions", Version: "v1beta1", Resource: "localvolumes"}

func (c *FakeLocalVolumes) Create(localVolume *v1beta1.LocalVolume) (result *v1beta1.LocalVolume, err error) {
	obj, err := c.Fake.
		Invokes(core.NewRootCreateAction(localvolumesResource, localVolume), &v1beta1.LocalVolume{})
	if obj == nil {
		return nil, err
	}
	return obj.(*v1beta1.LocalVolume), err
}

func (c *FakeLocalVolumes) Update(localVolume *v1beta1.LocalVolume) (result *v1beta1.LocalVolume, err error) {
	obj, err := c.Fake.
		Invokes(core.NewRootUpdateAction(localvolumesResource, localVolume), &v1beta1.LocalVolume{})
	if obj == nil {
		return nil, err
	}
	return obj.(*v1beta1.LocalVolume), err
}

func (c *FakeLocalVolumes) UpdateStatus(localVolume *v1beta1.LocalVolume) (*v1beta1.LocalVolume, error) {
	obj, err := c.Fake.
		Invokes(core.NewRootUpdateSubresourceAction(localvolumesResource, "status", localVolume), &v1beta1.LocalVolume{})
	if obj == nil {
		return nil, err
	}
	return obj.(*v1beta1.LocalVolume), err
}

func (c *FakeLocalVolumes) Delete(name string, options *api.DeleteOptions) error {
	_, err := c.Fake.
		Invokes(core.NewRootDeleteAction(localvolumesResource, name), &v1beta1.LocalVolume{})
	return err
}

func (c *FakeLocalVolumes) DeleteCollection(options *api.DeleteOptions, listOptions api.ListOptions) error {
	action := core.NewRootDeleteCollectionAction(localvolumesResource, listOptions)

	_, err := c.Fake.Invokes(action, &v1beta1.LocalVolumeList{})
	return err
}

func (c *FakeLocalVolumes) Get(name string) (result *v1beta1.LocalVolume, err error) {
	obj, err := c.Fake.
		Invokes(core.NewRootGetAction(localvolumesResource, name), &v1beta1.LocalVolume{})
	if obj == nil {
		return nil, err
	}
	return obj.(*v1beta1.LocalVolume), err
}

func (c *FakeLocalVolumes) List(opts api.ListOptions) (result *v1beta1.LocalVolumeList, err error) {
	obj, err := c.Fake.
		Invokes(core.NewRootListAction(localvolumesResource, opts), &v1beta1.LocalVolumeList{})
	if obj == nil {
		return nil, err
	}

	label := opts.LabelSelector
	if label == nil {
		label = labels.Everything()
	}
	list := &v1beta1.LocalVolumeList{}
	for _, item := range obj.(*v1beta1.LocalVolumeList).Items {
		if label.Matches(labels.Set(item.Labels)) {
			list.Items = append(list.Items, item)
		}
	}
	return list, err
}

// Watch returns a watch.Interface that watches the requested localVolumes.
func (c *FakeLocalVolumes) Watch(opts api.ListOptions) (watch.Interface, error) {
	return c.Fake.
		InvokesWatch(core.NewRootWatchAction(localvolumesResource, opts))
}
