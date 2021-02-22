#!/bin/bash
# This script aquires needed vpn client files from vault to an intermediary bastion

set -e

if [[ -z "$1" ]]; then
  echo "Error: 1st arg bastion host must be provided. eg: centos@ec2-54-253-11-29.ap-southeast-2.compute.amazonaws.com"
  exit 1
fi

if [[ -z "$2" ]]; then
  echo "Error: 2nd arg vault client must be provided. eg: centos@i-00265f3f7614cbbee.node.consul"
  exit 1
fi

host1="$1"
host2="$2"

# Log the given message. All logs are written to stderr with a timestamp.
function log {
 local -r message="$1"
 local -r timestamp=$(date +"%Y-%m-%d %H:%M:%S")
 >&2 echo -e "$timestamp $message"
}

function retrieve_file {
  local -r source_path="$1"
  local -r target_path="$(basename $source_path)"

  scp -i ~/.ssh/id_rsa-cert.pub -i ~/.ssh/id_rsa -o ProxyCommand="ssh -i ~/.ssh/id_rsa-cert.pub -i ~/.ssh/id_rsa -W %h:%p $host1" $host2:$source_path ./json_blob.json
#   local -r response=$(jq json_blob.json)
#   echo $response | jq -r .file | tee $target_path # retrieve full json blob to later pass permissions if required.
  jq -r .file json_blob.json | tee $target_path
  rm ./json_blob.json
  chmod 0600 $target_path
}

# Retrieve previously generated secrets from Vault.  Would be better if we can use vault as an intermediary to generate certs.

retrieve_file "/home/centos/tmp/usr/local/openvpn_as/scripts/seperate/ca.crt"
retrieve_file "/home/centos/tmp/usr/local/openvpn_as/scripts/seperate/client.crt"
retrieve_file "/home/centos/tmp/usr/local/openvpn_as/scripts/seperate/client.key"
retrieve_file "/home/centos/tmp/usr/local/openvpn_as/scripts/seperate/ta.key"
retrieve_file "/home/centos/tmp/usr/local/openvpn_as/scripts/seperate/client.ovpn"

echo "Done."