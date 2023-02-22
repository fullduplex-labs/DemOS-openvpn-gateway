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

# Environment Variables: Required
PrivateDomain="$PrivateDomain"
PublicDomain="$PublicDomain"
SubnetPortalCidr="$SubnetPortalCidr"
SubnetOpsCidr="$SubnetOpsCidr"
VpnGatewayCidr="$VpnGatewayCidr"

# Environment Variables: Optional
VpnDevice="${VpnDevice:-eth0}"
VpnDnsEndpoint="${VpnDnsEndpoint:-169.254.169.253}"

# Utility Variables
ServerConfig="/etc/openvpn/server"
ClientConfig="/etc/openvpn/client"

# Helpers
################################################################################
function tagFile() {
  declare t=$(cat "$1")
  echo "${t//$2/$3}" > "$1"
}

function makeServerConfiguration() {
  declare \
    config="$ServerConfig/server.conf"

  [[ ${VpnGatewayCidr##*/} != "25" ]] && {
    printf "The VpnGatewayCidr expects a subnet mask of 25"
    return 1
  }

  tagFile $config "{{VpnDeviceIp}}" \
    "$(ip -o -4 addr list $VpnDevice | awk '{print $4}' | cut -d/ -f1)"

  tagFile $config "{{VpnGatewayPrefix}}" "${VpnGatewayCidr%.*}"
  tagFile $config "{{PrivateDomain}}" "$PrivateDomain"
  tagFile $config "{{PublicDomain}}" "$PublicDomain"

  tagFile $config "{{SubnetPortalPrefix}}" "${SubnetPortalCidr%/*}"
  tagFile $config "{{SubnetPortalMask}}" \
    "$(ipcalc -nb $SubnetPortalCidr | grep Netmask | awk '{print $2}')"

  tagFile $config "{{SubnetOpsPrefix}}" "${SubnetOpsCidr%/*}"
  tagFile $config "{{SubnetOpsMask}}" \
    "$(ipcalc -nb $SubnetOpsCidr | grep Netmask | awk '{print $2}')"

  return
}

function configureNetworking() {
  declare \
    prefix="${VpnGatewayCidr%.*}" \
    dnat tuple masquerade ip

  dnat=(
    "${prefix}.200:${VpnDnsEndpoint}"
  )

  # masquerade=()

  iptables-legacy \
    -C DOCKER-USER -j ACCEPT -i "tun0" -o "$VpnDevice" &> /dev/null \
  || iptables-legacy \
    -I DOCKER-USER -j ACCEPT -i "tun0" -o "$VpnDevice"

  iptables-legacy \
    -C DOCKER-USER -j ACCEPT -i "$VpnDevice" -o "tun0" &> /dev/null \
  || iptables-legacy \
    -I DOCKER-USER -j ACCEPT -i "$VpnDevice" -o "tun0"

  # Setup Destination NAT (DNAT)
  for tuple in "${dnat[@]}"; do
    iptables-legacy -t nat -C PREROUTING -j DNAT \
      -s "$VpnGatewayCidr" \
      -d "${tuple%:*}/32" \
      --to-destination "${tuple#*:}" \
      &> /dev/null \
    || iptables-legacy -t nat -I PREROUTING -j DNAT \
      -s "$VpnGatewayCidr" \
      -d "${tuple%:*}/32" \
      --to-destination "${tuple#*:}"
  done

  # # Setup NAT for Public IPs (MASQUERADE)
  # for ip in "${masquerade[@]}"; do
  #   iptables-legacy -t nat -C POSTROUTING -j MASQUERADE \
  #     -s "$VpnGatewayCidr" \
  #     -d "$ip/32" \
  #     -o "$VpnDevice" \
  #     &> /dev/null \
  #   || iptables-legacy -t nat -A POSTROUTING -j MASQUERADE \
  #     -s "$VpnGatewayCidr" \
  #     -d "$ip/32" \
  #     -o "$VpnDevice"
  # done

  return
}

# Runtime
################################################################################
makeServerConfiguration
configureNetworking

$(which openvpn) --cd /etc/openvpn/server --config server.conf

exit