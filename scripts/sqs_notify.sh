#!/bin/bash

set -e

printf "\n...Waiting for consul vpn service before attempting SQS notify.\n\n"
until consul catalog services | grep -m 1 "vpn"; do sleep 10 ; done

echo ""
echo "...Using SQS queue to notify remote clients of VPN credential endpoint.  SSH certs must be configured to use the endpoint."
echo ""

readonly resourcetier="$1"
readonly sqs_queue_url="$2"
readonly host1="$3"
readonly host2="$4"
readonly ttl_mins="15m"

readonly VAULT_ADDR=https://vault.service.consul:8200

openvpn_admin_pw="$(vault kv get -field=value -address="$VAULT_ADDR" -format=json $resourcetier/network/openvpn_admin_pw)"
token="$(vault token create -address="$VAULT_ADDR" -policy=vpn_read_config -policy=deadline_client -explicit-max-ttl=$ttl_mins -ttl=$ttl_mins -use-limit=4 -field=token)"

file_content="$(cat <<EOF
{
    "openvpn_admin_pw" : $openvpn_admin_pw, 
    "host1" : "$host1",
    "host2" : "$host2",
    "token" : "$token"
}
EOF
)"

aws sqs purge-queue --queue-url $sqs_queue_url
echo "...Waiting 60 seconds to purge queue"
sleep 60
aws sqs send-message --queue-url $sqs_queue_url --message-body "$file_content" --message-group-id "$resourcetier"