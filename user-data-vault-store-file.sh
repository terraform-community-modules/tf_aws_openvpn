#!/bin/bash

set -e
exec > >(tee -a /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

# User Vars: Set by terraform template
resourcetier="${resourcetier}"
example_role_name="${example_role_name}"

# Script vars (implicit)
export VAULT_ADDR="https://vault.service.consul:8200"
client_cert_file_path="${client_cert_file_path}"
client_cert_vault_path="${client_cert_vault_path}"

# Functions
function log {
 local -r message="$1"
 local -r timestamp=$(date +"%Y-%m-%d %H:%M:%S")
 >&2 echo -e "$timestamp $message"
}
function has_yum {
  [[ -n "$(command -v yum)" ]]
}
function has_apt_get {
  [[ -n "$(command -v apt-get)" ]]
}
# A retry function that attempts to run a command a number of times and returns the output
function retry {
  local -r cmd="$1"
  local -r description="$2"
  attempts=5

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

  log "$description failed after $attempts attempts."
  exit $exit_status
}
function store_file {
  local -r file_path="$1"
  if [[ -z "$2" ]]; then
    local target="$resourcetier/vpn/client_cert_files/$file_path"
  else
    local target="$2"
  fi
  if sudo test -f "$file_path"; then
    vault kv put -address="$VAULT_ADDR" "$target/file" value="$(sudo cat $file_path | base64 -w 0)"
    if [[ "$OSTYPE" == "darwin"* ]]; then # Acquire file permissions.
        octal_permissions=$(sudo stat -f %A $file_path | rev | sed -E 's/^([[:digit:]]{4})([^[:space:]]+)/\1/' | rev ) # clip to 4 zeroes
    else
        octal_permissions=$(sudo stat --format '%a' $file_path | rev | sed -E 's/^([[:digit:]]{4})([^[:space:]]+)/\1/' | rev) # clip to 4 zeroes
    fi
    octal_permissions=$( python3 -c "print( \"$octal_permissions\".zfill(4) )" ) # pad to 4 zeroes
    file_uid="$(sudo stat --format '%u' $file_path)"
    file_gid="$(sudo stat --format '%g' $file_path)"
    blob="{ \
      \"permissions\":\"$octal_permissions\", \
      \"owner\":\"$(sudo id -un -- $file_uid)\", \
      \"uid\":\"$file_uid\", \
      \"gid\":\"$file_gid\", \
      \"format\":\"base64\" \
    }"
    jq_parse=$( echo "$blob" | jq -c -r '.' )
    vault kv put -address="$VAULT_ADDR" -format=json "$target/permissions" value="$jq_parse"
  else
    print "Error: file not found: $file_path"
    exit 1
  fi
}

### Vault Auth IAM Method CLI
retry \
  "vault login --no-print -method=aws header_value=vault.service.consul role=${example_role_name}" \
  "Waiting for Vault login"
# Store generated certs in vault
echo "...Store certificate."
store_file "$client_cert_file_path" "$client_cert_vault_path"
echo "Revoking vault token..."
vault token revoke -self
