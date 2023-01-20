#!/usr/bin/env bash
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
set -e

# Environment Variables
AwsRegion="$AwsRegion"
KeyAlias="$KeyAlias"
VpnGatewayKey="$VpnGatewayKey"
VpnLocalIp="$VpnLocalIp"

# Utility Variables
Aws="aws --region $AwsRegion"
ServerConfig="/etc/openvpn/server"
ClientConfig="/app/client-config/"

# Helpers
################################################################################
function tagFile() {
}

function fetchCertificate() {
  declare \
    keystore="$ServerConfig/keys" \
    parameter 

  parameter=$($Aws ssm get-parameter --name "$VpnGatewayKey" --with-decryption \
    | jq -r '.Parameter')

  [[ $(echo "$parameter" | jq -r '.Version') != "1" ]] \
    || return

  echo "$parameter" | jq -r '.Value' > "$keystore/vpn.key"
  chmod 600 "$keystore/vpn.key"

  return
}

function makeCertificate() {
  declare \
    keystore="$ServerConfig/keys"

  openvpn --genkey --secret "$keystore/vpn.key"

  $Aws ssm put-parameter \
    --type "SecureString" \
    --key-id "$KeyAlias" \
    --name "$VpnGatewayKey" \
    --value "$(cat $keystore/vpn.key)" \
    --overwrite \
  &> /dev/null

  return
}

function makeDiffieHelmanParameters() {
  declare \
    keystore="$ServerConfig/keys"

  openssl dhparam -out "$keystore/dh2048.pem" 2048
  return
}

function makeServerConfiguration() {
  declare \
    config="$ServerConfig/server.conf"

  tagFile $config "{{VpnLocalIp}}" "$VpnLocalIp"

  return
}

# Run
################################################################################
fetchCertificate || makeCertificate
makeDiffieHelmanParameters
makeServerConfiguration

exit