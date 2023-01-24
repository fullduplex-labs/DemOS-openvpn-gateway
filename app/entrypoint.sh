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
set \
  -o errexit \
  -o pipefail

# Environment Variables
AwsRegion="$AwsRegion"
KeyAlias="$KeyAlias"
VpnGatewayKey="$VpnGatewayKey"
VpnGatewayProfile="$VpnGatewayProfile"
VpnGatewayEndpoint="$VpnGatewayEndpoint"
VpnLocalIp="$VpnLocalIp"

# Utility Variables
Aws="aws --region $AwsRegion"
ServerConfig="/etc/openvpn/server"
ClientConfig="/app/client-config/"
ProfileTemplate="/app/template.ovpn"

# Helpers
################################################################################
function tagFile() {
  declare t=$(cat "$1")
  echo "${t//$2/$3}" > "$1"
}

function fetchVpnGatewayKey() {
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

function makeVpnGatewayKey() {
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

function makeClientProfile() {
  declare \
    clientProfile="$ClientConfig/profile.ovpn"

  tagFile $ProfileTemplate "{{ProfileName}}" "Debug"
  tagFile $ProfileTemplate "{{VpnGatewayEndpoint}}" "$VpnGatewayEndpoint"

  cat "$ProfileTemplate" \
    <(echo -e '<ca>') \
    $ServerConfig/keys/ca.crt \
    <(echo -e '</ca>\n<cert>') \
    $ClientConfig/client.crt \
    <(echo -e '</cert>\n<key>') \
    $ClientConfig/client.key \
    <(echo -e '</key>\n<tls-crypt>') \
    $ServerConfig/keys/vpn.key \
    <(echo -e '</tls-crypt>') \
    > "$clientProfile"

  $Aws s3 cp "$clientProfile" "s3://$VpnGatewayProfile" --acl public-read

  return
}

function configureNetworking() {
  declare \
    device

  device="$(ip -j a | jq -r 'map(select(.ifname|test("^(eth|en)")))[0].ifname')"

  iptables -C DOCKER-USER -j ACCEPT -i "tun0" -o "$device" &> /dev/null \
  || iptables -I DOCKER-USER -j ACCEPT -i "tun0" -o "$device"

  iptables -C DOCKER-USER -j ACCEPT -i "$device" -o "tun0" &> /dev/null \
  || iptables -I DOCKER-USER -j ACCEPT -i "$device" -o "tun0"

  return
}

# Runtime
################################################################################
fetchVpnGatewayKey || makeVpnGatewayKey
makeDiffieHelmanParameters
makeServerConfiguration
makeClientProfile

$(which openvpn) --cd /etc/openvpn/server --config server.conf

exit