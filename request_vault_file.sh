#!/bin/bash
# This script is meant to be run in the User Data of each EC2 Instance while it's booting. The script uses the
# run-consul script to configure and start Consul in client mode. Note that this script assumes it's running in an AMI
# built from the Packer template in examples/vault-consul-ami/vault-consul.json.

set -e

if [[ -z "$1" ]]; then
  echo "arg dev/green/blue must be provided."
  exit 1
fi

resourcetier="$1"
attempts=1

# Log the given message. All logs are written to stderr with a timestamp.
function log {
 local -r message="$1"
 local -r timestamp=$(date +"%Y-%m-%d %H:%M:%S")
 >&2 echo -e "$timestamp $message"
}

# A retry function that attempts to run a command a number of times and returns the output
function retry {
  local -r cmd="$1"
  local -r description="$2"

  for i in $(seq 1 $attempts); do
    log "$description"

    # The boolean operations with the exit status are there to temporarily circumvent the "set -e" at the
    # beginning of this script which exits the script immediatelly for error status while not losing the exit status code
    output=$(eval "$cmd") && exit_status=0 || exit_status=$?
    errors=$(echo "$output") | grep '^{' | jq -r .errors

    log "$output"

    if [[ $exit_status -eq 0 && -z "$errors" ]]; then
      echo "$output"
      return
    fi
    log "$description failed. Will sleep for 10 seconds and try again."
    sleep 10
  done;

  log "$description failed after 30 attempts."
  exit $exit_status
}
# export VAULT_TOKEN=${vault_token}
export VAULT_ADDR=https://vault.service.consul:8200

# Retry and wait for the Vault Agent to write the token out to a file.  This could be
# because the Vault server is still booting and unsealing, or because run-consul
# running on the background didn't finish yet
retry \
  "vault login  --no-print $VAULT_TOKEN" \
  "Waiting for Vault login"

# vault login -method=aws header_value=vault.example.com role=dev-role-iam \
#         aws_access_key_id=<access_key> \
#         aws_secret_access_key=<secret_key>

# # We can then use the client token from the login output once login was successful
# token=$(cat /opt/vault/data/vault-token)

# /opt/vault/bin/vault read secret/example_gruntwork
echo "Aquiring vault data..."
# data=$(vault kv get -format=json /${resourcetier}/files/usr/local/openvpn_as/scripts/seperate/ca.crt)

function retrieve_file {
  local -r file_path="$1"
  # file_path=/usr/local/openvpn_as/scripts/seperate/ca.crt
  # vault kv get -format=json /${resourcetier}/files/$file_path > /usr/local/openvpn_as/scripts/seperate/ca_test.crt

  local -r response=$(retry \
  "vault kv get -format=json /$resourcetier/files/$file_path" \
  "Trying to read secret from vault")
  mkdir -p $(dirname $file_path) # ensure the directory exists
  echo $response | jq -r .data.data.file > $file_path
  local -r permissions=$(echo $response | jq -r .data.data.permissions)
  local -r uid=$(echo $response | jq -r .data.data.uid)
  local -r gid=$(echo $response | jq -r .data.data.gid)
  echo "Setting:"
  echo "uid:$uid gid:$gid permissions:$permissions file_path:$file_path"
  chown $uid:$gid $file_path
  chmod $permissions $file_path
}

# Retrieve previously generated secrets from Vault.  Would be better if we can use vault as an intermediary to generate certs.

retrieve_file "/usr/local/openvpn_as/scripts/seperate/ca.crt"
retrieve_file "/usr/local/openvpn_as/scripts/seperate/client.crt"
retrieve_file "/usr/local/openvpn_as/scripts/seperate/client.key"
retrieve_file "/usr/local/openvpn_as/scripts/seperate/ta.key"
retrieve_file "/usr/local/openvpn_as/scripts/seperate/client.ovpn"

echo "Done."