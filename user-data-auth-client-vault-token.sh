#!/bin/bash
# This script is meant to be run in the User Data of each EC2 Instance while it's booting. The script uses the
# run-consul script to configure and start Consul in client mode. Note that this script assumes it's running in an AMI
# built from the Packer template in examples/vault-consul-ami/vault-consul.json.

set -e

admin_user="${openvpn_admin_user}"
admin_pw="$(openssl rand -base64 12)" # auto generate instance pass and store in vault after vault login.
openvpn_user="${openvpn_user}" # TODO temporary use of admin for testing. Should be replaced with another user.
openvpn_user_pw="$(openssl rand -base64 12)"
resourcetier="${resourcetier}"
# TODO these will be replaced with calls to vault.

# Send the log output from this script to user-data.log, syslog, and the console
# From: https://alestic.com/2010/12/ec2-user-data-output/
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

# These variables are passed in via Terraform template interpolation
/opt/consul/bin/run-consul --client --cluster-tag-key "${consul_cluster_tag_key}" --cluster-tag-value "${consul_cluster_tag_value}"

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

  for i in $(seq 1 30); do
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

export AWS_DEFAULT_REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone | sed 's/\(.*\)[a-z]/\1/')
public_ip=$(curl http://169.254.169.254/latest/meta-data/public-ipv4); echo "Public IP: $public_ip"
private_ip=$(curl http://169.254.169.254/latest/meta-data/local-ipv4); echo "Private IP: $private_ip"

# If vault cli is installed we can also perform these operations with vault cli
# The necessary environment variables have to be set
# export VAULT_TOKEN=$token
export VAULT_ADDR=https://vault.service.consul:8200

# # Start the Vault agent
# # /opt/vault/bin/run-vault --agent --agent-auth-type iam --agent-auth-role "${example_role_name}"

# Retry and wait for the Vault Agent to write the token out to a file.  This could be
# because the Vault server is still booting and unsealing, or because run-consul
# running on the background didn't finish yet
retry \
  "vault login  --no-print ${vault_token}" \
  "Waiting for Vault login"

log "Request Vault sign's the SSH host key and becomes a known host for other machines."
# Allow access from clients signed by the CA.
trusted_ca="/etc/ssh/trusted-user-ca-keys.pem"
# Aquire the public CA cert to approve an authority
vault read -field=public_key ssh-client-signer/config/ca | tee $trusted_ca
if test ! -f "$trusted_ca"; then
    log "Missing $trusted_ca"
    exit 1
fi
### Sign SSH host key
if test ! -f "/etc/ssh/ssh_host_rsa_key.pub"; then
    log "Missing public host key /etc/ssh/ssh_host_rsa_key.pub"
    exit 1
fi
# Sign this host's public key
vault write -format=json ssh-host-signer/sign/hostrole \
    cert_type=host \
    public_key=@/etc/ssh/ssh_host_rsa_key.pub
# Aquire the cert
vault write -field=signed_key ssh-host-signer/sign/hostrole \
    cert_type=host \
    public_key=@/etc/ssh/ssh_host_rsa_key.pub | tee /etc/ssh/ssh_host_rsa_key-cert.pub
if test ! -f "/etc/ssh/ssh_host_rsa_key-cert.pub"; then
    log "Failed to aquire /etc/ssh/ssh_host_rsa_key-cert.pub"
    exit 1
fi
chmod 0640 /etc/ssh/ssh_host_rsa_key-cert.pub
# Private key and cert are both required for ssh to another host.  Multiple entries for host key may exist.
grep -q "^HostKey /etc/ssh/ssh_host_rsa_key" /etc/ssh/sshd_config || echo 'HostKey /etc/ssh/ssh_host_rsa_key' | tee --append /etc/ssh/sshd_config
# Configure host cert to be recognised as a known host.
grep -q "^HostCertificate" /etc/ssh/sshd_config || echo 'HostCertificate' | tee --append /etc/ssh/sshd_config
sed -i 's@HostCertificate.*@HostCertificate /etc/ssh/ssh_host_rsa_key-cert.pub@g' /etc/ssh/sshd_config

set -x

client_network=${client_network}
client_netmask_bits=${client_netmask_bits}
private_subnet1=${private_subnet1}
public_subnet1=${public_subnet1}
aws_internal_domain=${aws_internal_domain}
onsite_private_subnet_cidr=${onsite_private_subnet_cidr}

ls -la /usr/local/openvpn_as/scripts/

# see https://evanhoffman.com/2014/07/22/openvpn-cli-cheat-sheet/

# # this may need to be in the image
# /usr/local/openvpn_as/scripts/sacli Init 
/usr/local/openvpn_as/scripts/sacli -k vpn.daemon.0.client.network -v $client_network ConfigPut
/usr/local/openvpn_as/scripts/sacli -k vpn.daemon.0.client.netmask_bits -v $client_netmask_bits ConfigPut
/usr/local/openvpn_as/scripts/sacli --key 'vpn.server.tls_auth' --value 'true' ConfigPut
/usr/local/openvpn_as/scripts/sacli --key vpn.server.routing.gateway_access --value 'true' ConfigPut
/usr/local/openvpn_as/scripts/sacli --key vpn.server.routing.private_network.0 --value "$private_subnet1" ConfigPut
/usr/local/openvpn_as/scripts/sacli --key vpn.server.routing.private_network.1 --value "$public_subnet1" ConfigPut
/usr/local/openvpn_as/scripts/sacli --key vpn.server.routing.private_network.2 --value "$client_network/$client_netmask_bits" ConfigPut
/usr/local/openvpn_as/scripts/sacli --key vpn.server.routing.private_access --value 'route' ConfigPut
/usr/local/openvpn_as/scripts/sacli --key 'vpn.client.routing.reroute_dns' --value 'true' ConfigPut
/usr/local/openvpn_as/scripts/sacli --key 'vpn.server.dhcp_option.domain' --value "$aws_internal_domain" ConfigPut
/usr/local/openvpn_as/scripts/sacli --key 'vpn.server.routing.allow_private_nets_to_clients' --value 'true' ConfigPut

# ensure listen on interaces at default. restore ip since the old one during ami build is now invalid.
/usr/local/openvpn_as/scripts/sacli --key "vpn.daemon.0.server.ip_address" --value "all" ConfigPut
/usr/local/openvpn_as/scripts/sacli --key "vpn.daemon.0.listen.ip_address" --value "all" ConfigPut
/usr/local/openvpn_as/scripts/sacli --key "vpn.server.daemon.udp.port" --value "1194" ConfigPut
/usr/local/openvpn_as/scripts/sacli --key "vpn.server.daemon.tcp.port" --value "443" ConfigPut
/usr/local/openvpn_as/scripts/sacli --key "host.name" --value "$public_ip" ConfigPut

/usr/local/openvpn_as/scripts/sacli start

cd /usr/local/openvpn_as/scripts/
/usr/local/openvpn_as/scripts/sacli --user $openvpn_user --key 'prop_autologin' --value 'true' UserPropPut
/usr/local/openvpn_as/scripts/sacli --user $openvpn_user --key 'c2s_route.0' --value "$onsite_private_subnet_cidr" UserPropPut
/usr/local/openvpn_as/scripts/sacli --user $openvpn_user AutoGenerateOnBehalfOf
mkdir -p /usr/local/openvpn_as/scripts/seperate
/usr/local/openvpn_as/scripts/sacli -o ./seperate --cn "${openvpn_user}_AUTOLOGIN" get1
chown $openvpn_user seperate/*
/usr/local/openvpn_as/scripts/sacli start
ls -la seperate

# show entire config
/usr/local/openvpn_as/scripts/sacli ConfigQuery

### Store Generated keys and password with vault

echo "Storing keys with vault..."

vault kv patch -address="$VAULT_ADDR" -format=json $resourcetier/network/openvpn_admin_pw value=${admin_pw}
vault kv patch -address="$VAULT_ADDR" -format=json $resourcetier/network/openvpn_user_pw value=${openvpn_user_pw}

function retrieve_file {
  local -r file_path="$1"
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

function store_file {
  local -r file_path="$1"
  if [[ -z "$2" ]]; then
    local target="$resourcetier/files/$file_path"
  else
    local target="$2"
  fi

  if sudo test -f "$file_path"; then
    # vault login -no-print -address="$VAULT_ADDR" -method=aws header_value=vault.service.consul role=provisioner-vault-role  
    vault kv put -address="$VAULT_ADDR" -format=json $target file="$(sudo cat $file_path)"
    if [[ "$OSTYPE" == "darwin"* ]]; then # Acquire file permissions.
        octal_permissions=$(sudo stat -f %A $file_path | rev | sed -E 's/^([[:digit:]]{4})([^[:space:]]+)/\1/' | rev ) # clip to 4 zeroes
    else
        octal_permissions=$(sudo stat --format '%a' $file_path | rev | sed -E 's/^([[:digit:]]{4})([^[:space:]]+)/\1/' | rev) # clip to 4 zeroes
    fi
    octal_permissions=$( python -c "print( \"$octal_permissions\".zfill(4) )" ) # pad to 4 zeroes
    vault kv patch -address="$VAULT_ADDR" -format=json $target permissions="$octal_permissions"
    file_uid="$(sudo stat --format '%u' $file_path)"
    vault kv patch -address="$VAULT_ADDR" -format=json $target owner="$(sudo id -un -- $file_uid)"
    vault kv patch -address="$VAULT_ADDR" -format=json $target uid="$file_uid"
    file_gid="$(sudo stat --format '%g' $file_path)"
    vault kv patch -address="$VAULT_ADDR" -format=json $target gid="$file_gid"
  else
    print "Error: file not found: $file_path"
    exit 1
  fi
}

# Store generated certs in vault

for filename in /usr/local/openvpn_as/scripts/seperate/*; do
    store_file "$filename"
done

echo "Done."
