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
ARG AWS_SRC="https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip"

ARG DEBIAN_FRONTEND=noninteractive

FROM ubuntu:22.04 as build-image
ARG DEBIAN_FRONTEND
ARG AWS_SRC
WORKDIR /tmp
RUN bash <<EOF
apt-get update
apt-get install -y unzip curl
rm -rf /var/lib/apt/lists/*
#
# Install AWS-CLI
curl -L -o awscli.zip ${AWS_SRC}
unzip awscli.zip
./aws/install
EOF

FROM ubuntu:22.04
COPY --from=build-image /usr/local/bin /usr/local/bin
COPY --from=build-image /usr/local/aws-cli /usr/local/aws-cli
ARG DEBIAN_FRONTEND
RUN bash <<EOF
apt-get update
apt-get install -y openssl openvpn jq iptables
rm -rf /var/lib/apt/lists/*
EOF

COPY etc/ /etc
COPY app/ /app
RUN chmod +x /app/entrypoint.sh
WORKDIR /app

HEALTHCHECK --interval=30s --timeout=3s --start-period=300s CMD pidof openvpn

ENTRYPOINT [ "/app/entrypoint.sh" ]