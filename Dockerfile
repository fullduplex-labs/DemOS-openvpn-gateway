# syntax=docker/dockerfile:1.5-labs
#
# Copyright 2023 Full Duplex Media, LLC

# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at

#     http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive
RUN bash <<EOF
apt-get update
apt-get install -y openvpn iptables ipcalc
rm -rf /var/lib/apt/lists/*
EOF

COPY etc/ /etc
COPY app/ /app
RUN chmod +x /app/entrypoint.sh
WORKDIR /app

HEALTHCHECK --interval=30s --timeout=3s --start-period=300s CMD pidof openvpn

ENTRYPOINT [ "/app/entrypoint.sh" ]