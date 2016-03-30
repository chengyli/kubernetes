#!/usr/bin/env python

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

import logging

log = logging.getLogger(__name__)


"""
Get pillar data from custom data soruce
"""
def ext_pillar(minion_id, pillar, *args,  **kw):
    log.info("custom_pillar getting called")
    data = {}

    # Dont have to contact tess master for overlays
    if pillar["network_mode"] == "overlay":
        log.info("Not necessary to call tess-master to allocate CIDR blocks for overlays, continuing..")
        return data

    if 'kubernetes-minion' in minion_id:
        data['route_cidr'] = get_cidr(minion_id)
    return data


"""
Contact Tess Master to get a CIDR allocated
"""
def get_cidr(minion_id):
    #TODO Fill this up when the tess-master api is available
    return "TBD"