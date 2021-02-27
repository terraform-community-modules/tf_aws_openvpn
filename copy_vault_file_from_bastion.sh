#!/bin/bash
# This script aquires needed vpn client files from vault to an intermediary bastion

set -e

if [[ -z "$1" ]]; then
  echo "Error: 1st arg bastion host must be provided. eg:"
  echo "VAULT_TOKEN=s.kjh1k4jfdsfhkNe ./copy_vault_file_from_bastion.sh centos@ec2-3-25-143-13.ap-southeast-2.compute.amazonaws.com centos@i-0df3060971160cdd6.node.consul"
  exit 1
fi

if [[ -z "$2" ]]; then
  echo "Error: 2nd arg vault client must be provided. eg: centos@i-00265f3f7614cbbee.node.consul"
  echo "VAULT_TOKEN=s.kjh1k4jfdsfhkNe ./copy_vault_file_from_bastion.sh centos@ec2-3-25-143-13.ap-southeast-2.compute.amazonaws.com centos@i-0df3060971160cdd6.node.consul"
  exit 1
fi

if [[ -z "$2" ]]; then
  echo "Error: env var VAULT_TOKEN must be provided. eg: VAULT_TOKEN=s.kjh1k4jfdsfhkNe"
  echo "VAULT_TOKEN=s.kjh1k4jfdsfhkNe ./copy_vault_file_from_bastion.sh centos@ec2-3-25-143-13.ap-southeast-2.compute.amazonaws.com centos@i-0df3060971160cdd6.node.consul"
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

log "Requesting files from vault to client in private subnet"
ssh -o ProxyCommand="ssh $host1 -W %h:%p" $host2 "VAULT_TOKEN=$VAULT_TOKEN bash -s" < ./request_vault_file.sh main

function retrieve_file {
  local -r source_path="$1"
  local -r target_path="$(basename $source_path)"

  scp -i ~/.ssh/id_rsa-cert.pub -i ~/.ssh/id_rsa -o ProxyCommand="ssh -i ~/.ssh/id_rsa-cert.pub -i ~/.ssh/id_rsa -W %h:%p $host1" $host2:$source_path ./json_blob.json
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

cp ./client.ovpn ./openvpn.conf

log "...Cleaning up"
ssh -o ProxyCommand="ssh $host1 -W %h:%p" $host2 "sudo rm -frv /home/centos/tmp/*"

echo "Done."