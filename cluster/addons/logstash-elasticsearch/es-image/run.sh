#!/bin/bash

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

export RETENTION=${RETENTION:-3}

sed -i s/\$days/$RETENTION/ /crontab
mv /crontab /etc/cron.daily/curator
chmod +x /etc/cron.daily/curator

su elastic << EOF
export NODE_MASTER=${NODE_MASTER:-true}
export NODE_DATA=${NODE_DATA:-true}
export HTTP_ENABLED=${HTTP_ENABLED:-true}

/elasticsearch_logging_discovery $NAMESPACE >> /elasticsearch/config/elasticsearch.yml
export HTTP_PORT=${HTTP_PORT:-9200}
export TRANSPORT_PORT=${TRANSPORT_PORT:-9300}
export SLACK_URL=${SLACK_URL:-https://hooks.slack.com/services/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}
export ES_HEAP_SIZE=${ES_HEAP_SIZE:-4g}
/elasticsearch/bin/elasticsearch
EOF