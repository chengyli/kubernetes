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

package localvolumeclaim

import (
	"fmt"

	"k8s.io/kubernetes/pkg/api"
	//"k8s.io/kubernetes/pkg/api/validation"
	"k8s.io/kubernetes/pkg/fields"
	"k8s.io/kubernetes/pkg/labels"
	"k8s.io/kubernetes/pkg/registry/generic"
	"k8s.io/kubernetes/pkg/runtime"
	"k8s.io/kubernetes/pkg/util/validation/field"
	"k8s.io/kubernetes/pkg/apis/extensions"
)

// localvolumeclaimStrategy implements behavior for localVolumeClaim objects
type localvolumeclaimStrategy struct {
	runtime.ObjectTyper
	api.NameGenerator
}

// Strategy is the default logic that applies when creating and updating localVolumeClaim
// objects via the REST API.
var Strategy = localvolumeclaimStrategy{api.Scheme, api.SimpleNameGenerator}

func (localvolumeclaimStrategy) NamespaceScoped() bool {
	return true
}

// PrepareForCreate clears the Status field which is not allowed to be set by end users on creation.
func (localvolumeclaimStrategy) PrepareForCreate(obj runtime.Object) {
	pv := obj.(*extensions.LocalVolumeClaim)
	pv.Status = extensions.LocalVolumeClaimStatus{}
}

func (localvolumeclaimStrategy) Validate(ctx api.Context, obj runtime.Object) field.ErrorList {
	//pvc := obj.(*extensions.LocalVolumeClaim)
	//return validation.ValidateLocalVolumeClaim(pvc)
	return field.ErrorList{}
}

// Canonicalize normalizes the object after validation.
func (localvolumeclaimStrategy) Canonicalize(obj runtime.Object) {
}

func (localvolumeclaimStrategy) AllowCreateOnUpdate() bool {
	return false
}

// PrepareForUpdate sets the Status field which is not allowed to be set by end users on update
func (localvolumeclaimStrategy) PrepareForUpdate(obj, old runtime.Object) {
	newPvc := obj.(*extensions.LocalVolumeClaim)
	oldPvc := old.(*extensions.LocalVolumeClaim)
	newPvc.Status = oldPvc.Status
}

func (localvolumeclaimStrategy) ValidateUpdate(ctx api.Context, obj, old runtime.Object) field.ErrorList {
	//errorList := validation.ValidateLocalVolumeClaim(obj.(*extensions.LocalVolumeClaim))
	//return append(errorList, validation.ValidateLocalVolumeClaimUpdate(obj.(*extensions.LocalVolumeClaim), old.(*extensions.LocalVolumeClaim))...)
	return field.ErrorList{}
}

func (localvolumeclaimStrategy) AllowUnconditionalUpdate() bool {
	return true
}

type localvolumeclaimStatusStrategy struct {
	localvolumeclaimStrategy
}

var StatusStrategy = localvolumeclaimStatusStrategy{Strategy}

// PrepareForUpdate sets the Spec field which is not allowed to be changed when updating a PV's Status
func (localvolumeclaimStatusStrategy) PrepareForUpdate(obj, old runtime.Object) {
	newPv := obj.(*extensions.LocalVolumeClaim)
	oldPv := old.(*extensions.LocalVolumeClaim)
	newPv.Spec = oldPv.Spec
}

func (localvolumeclaimStatusStrategy) ValidateUpdate(ctx api.Context, obj, old runtime.Object) field.ErrorList {
	//return validation.ValidateLocalVolumeClaimStatusUpdate(obj.(*extensions.LocalVolumeClaim), old.(*extensions.LocalVolumeClaim))
	return field.ErrorList{}
}

// MatchLocalVolumeClaim returns a generic matcher for a given label and field selector.
func MatchLocalVolumeClaim(label labels.Selector, field fields.Selector) generic.Matcher {
	return generic.MatcherFunc(func(obj runtime.Object) (bool, error) {
		localvolumeclaimObj, ok := obj.(*extensions.LocalVolumeClaim)
		if !ok {
			return false, fmt.Errorf("not a localvolumeclaim")
		}
		fields := LocalVolumeClaimToSelectableFields(localvolumeclaimObj)
		return label.Matches(labels.Set(localvolumeclaimObj.Labels)) && field.Matches(fields), nil
	})
}

// LocalVolumeClaimToSelectableFields returns a label set that represents the object
func LocalVolumeClaimToSelectableFields(localvolumeclaim *extensions.LocalVolumeClaim) labels.Set {
	objectMetaFieldsSet := generic.ObjectMetaFieldsSet(localvolumeclaim.ObjectMeta, true)
	specificFieldsSet := fields.Set{
		// This is a bug, but we need to support it for backward compatibility.
		"name": localvolumeclaim.Name,
	}
	return labels.Set(generic.MergeFieldsSets(objectMetaFieldsSet, specificFieldsSet))
}
