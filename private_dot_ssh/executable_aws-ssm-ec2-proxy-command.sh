#!/usr/bin/env sh
######## Source ################################################################
#
# https://github.com/qoomon/aws-ssm-ec2-proxy-command (With additions by Topicus Cloud Team to start stopped instances)
#
######## Usage #################################################################
# https://github.com/qoomon/aws-ssm-ec2-proxy-command/blob/master/README.md
#
# Install Proxy Command
#   - Move this script to ~/.ssh/aws-ssm-ec2-proxy-command.sh
#   - Ensure it is executable (chmod +x ~/.ssh/aws-ssm-ec2-proxy-command.sh)
#
# Add following SSH Config Entry to ~/.ssh/config
#
# host aws-bastion-host
#  IdentityFile ~/.ssh/id_rsa
#  ProxyCommand ~/.ssh/aws-ssm-ec2-proxy-command.sh %r %p ~/.ssh/id_rsa.pub
#  StrictHostKeyChecking no
#  User ec2-user
#  ServerAliveInterval=120
#  RequestTTY no

# Ensure SSM Permissions for Target Instance Profile
#   https://docs.aws.amazon.com/systems-manager/latest/userguide/setup-instance-profile.html
#
# Open SSH Connection
#   ssh <INSTANCE_USER>@<INSTANCE_ID>
#   
#   Ensure AWS CLI environment variables are set properly
#   e.g. AWS_PROFILE='default' ssh ec2-user@i-xxxxxxxxxxxxxxxx
################################################################################
set -eu

ssh_user="$1"
ssh_port="$2"
ssh_public_key_path="$3"


ec2_instance_id="$(aws ssm get-parameter --name /topicus/applications/ec2/bastion-host/instance-id --query Parameter.Value --output text)"

instance_status="$(aws ec2 describe-instances \
    --instance-id "$ec2_instance_id" \
    --query "Reservations[0].Instances[0].State.Name" \
    --output text)"

if [ $instance_status != "running" ]
then
  >/dev/stderr echo "Instance ${ec2_instance_id} is not running (status: ${instance_status}). Starting the instance.."
  aws ec2 start-instances --instance-ids "$ec2_instance_id" --output json

  >/dev/stderr echo "Waiting for instance ${ec2_instance_id} to finish starting.."
  aws ec2 wait instance-status-ok --instance-ids "$ec2_instance_id" --output json

  >/dev/stderr echo "Instance ${ec2_instance_id} finished starting!"
fi

instance_availability_zone="$(aws ec2 describe-instances \
    --instance-id "$ec2_instance_id" \
    --query "Reservations[0].Instances[0].Placement.AvailabilityZone" \
    --output text)"

>/dev/stderr echo "Add public key ${ssh_public_key_path} to instance ${ec2_instance_id} for 60 seconds"
aws ec2-instance-connect send-ssh-public-key  \
  --instance-id "$ec2_instance_id" \
  --instance-os-user "$ssh_user" \
  --ssh-public-key "file://$ssh_public_key_path" \
  --availability-zone "$instance_availability_zone" \
  --output json

>/dev/stderr echo "Start ssm session to instance ${ec2_instance_id}"
aws ssm start-session \
  --target "${ec2_instance_id}" \
  --document-name 'AWS-StartSSHSession' \
  --parameters "portNumber=${ssh_port}" \
  --output json
