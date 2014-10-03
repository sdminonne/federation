#!/bin/bash

# Copyright 2014 Google Inc. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# A library of helper functions and constant for the local config.

# Use the config file specified in $KUBE_CONFIG_FILE, or default to
# config-default.sh.
KUBE_ROOT=$(dirname "${BASH_SOURCE}")/../..
source "${KUBE_ROOT}/cluster/gce/${KUBE_CONFIG_FILE-"config-default.sh"}"

# Verify prereqs
function verify-prereqs {
  for x in gcloud gcutil gsutil; do
    if [ "$(which $x)" == "" ]; then
      echo "Can't find $x in PATH, please fix and retry."
      exit 1
    fi
  done
}

# Verify and find the various tar files that we are going to use on the server.
#
# Vars set:
#   SERVER_BINARY_TAR
#   SALT_TAR
function find-release-tars {
  SERVER_BINARY_TAR="${KUBE_ROOT}/server/kubernetes-server-linux-amd64.tar.gz"
  if [[ ! -f "$SERVER_BINARY_TAR" ]]; then
    SERVER_BINARY_TAR="${KUBE_ROOT}/_output/release-tars/kubernetes-server-linux-amd64.tar.gz"
  fi
  if [[ ! -f "$SERVER_BINARY_TAR" ]]; then
    echo "!!! Cannot find kubernetes-server-linux-amd64.tar.gz"
    exit 1
  fi

  SALT_TAR="${KUBE_ROOT}/server/kubernetes-salt.tar.gz"
  if [[ ! -f "$SALT_TAR" ]]; then
    SALT_TAR="${KUBE_ROOT}/_output/release-tars/kubernetes-salt.tar.gz"
  fi
  if [[ ! -f "$SALT_TAR" ]]; then
    echo "!!! Cannot find kubernetes-salt.tar.gz"
    exit 1
  fi
}

# Use the gcloud defaults to find the project.  If it is already set in the
# environment then go with that.
#
# Vars set:
#   PROJECT
function detect-project () {
  if [ -z "$PROJECT" ]; then
    PROJECT=$(gcloud config list project | tail -n 1 | cut -f 3 -d ' ')
  fi

  if [ -z "$PROJECT" ]; then
    echo "Could not detect Google Cloud Platform project.  Set the default project using 'gcloud config set project <PROJECT>'" 1>&2
    exit 1
  fi
  echo "Project: $PROJECT (autodetected from gcloud config)"
}


# Take the local tar files and upload them to Google Storage.  They will then be
# downloaded by the master as part of the start up script for the master.
#
# Assumed vars:
#   PROJECT
#   SERVER_BINARY_TAR
#   SALT_TAR
# Vars set:
#   SERVER_BINARY_TAR_URL
#   SALT_TAR_URL
function upload-server-tars() {
  SERVER_BINARY_TAR_URL=
  SALT_TAR_URL=

  local project_hash
  if which md5 > /dev/null 2>&1; then
    project_hash=$(md5 -q -s "$PROJECT")
  else
    project_hash=$(echo -n "$PROJECT" | md5sum)
  fi

  local -r staging_bucket="gs://kubernetes-staging-${project_hash}"

  # Ensure the bucket is created
  if ! gsutil ls "$staging_bucket" > /dev/null 2>&1 ; then
    echo "Creating $staging_bucket"
    gsutil mb "${staging_bucket}"
  fi

  local -r staging_path="${staging_bucket}/devel"

  echo "+++ Staging server tars to Google Storage: ${staging_path}"
  SERVER_BINARY_TAR_URL="${staging_path}/${SERVER_BINARY_TAR##*/}"
  gsutil -q cp "${SERVER_BINARY_TAR}" "${SERVER_BINARY_TAR_URL}"
  SALT_TAR_URL="${staging_path}/${SALT_TAR##*/}"
  gsutil -q cp "${SALT_TAR}" "${SALT_TAR_URL}"
}

# Detect the information about the minions
#
# Assumed vars:
#   MINION_NAMES
#   ZONE
# Vars set:
#   KUBE_MINION_IP_ADDRESS (array)
function detect-minions () {
  KUBE_MINION_IP_ADDRESSES=()
  for (( i=0; i<${#MINION_NAMES[@]}; i++)); do
    # gcutil will print the "external-ip" column header even if no instances are found
    local minion_ip=$(gcutil listinstances --format=csv --sort=external-ip \
      --columns=external-ip --zone ${ZONE} --filter="name eq ${MINION_NAMES[$i]}" \
      | tail -n '+2' | tail -n 1)
    if [ -z "$minion_ip" ] ; then
      echo "Did not find ${MINION_NAMES[$i]}" 1>&2
    else
      echo "Found ${MINION_NAMES[$i]} at ${minion_ip}"
      KUBE_MINION_IP_ADDRESSES+=("${minion_ip}")
    fi
  done
  if [ -z "$KUBE_MINION_IP_ADDRESSES" ]; then
    echo "Could not detect Kubernetes minion nodes.  Make sure you've launched a cluster with 'kube-up.sh'" 1>&2
    exit 1
  fi
}

# Detect the IP for the master
#
# Assumed vars:
#   MASTER_NAME
#   ZONE
# Vars set:
#   KUBE_MASTER
#   KUBE_MASTER_IP
function detect-master () {
  KUBE_MASTER=${MASTER_NAME}
  if [ -z "$KUBE_MASTER_IP" ]; then
    # gcutil will print the "external-ip" column header even if no instances are found
    KUBE_MASTER_IP=$(gcutil listinstances --format=csv --sort=external-ip \
      --columns=external-ip --zone ${ZONE} --filter="name eq ${MASTER_NAME}" \
      | tail -n '+2' | tail -n 1)
  fi
  if [ -z "$KUBE_MASTER_IP" ]; then
    echo "Could not detect Kubernetes master node.  Make sure you've launched a cluster with 'kube-up.sh'" 1>&2
    exit 1
  fi
  echo "Using master: $KUBE_MASTER (external IP: $KUBE_MASTER_IP)"
}

# Ensure that we have a password created for validating to the master.  Will
# read from $HOME/.kubernetres_auth if available.
#
# Vars set:
#   KUBE_USER
#   KUBE_PASSWORD
function get-password {
  local file="$HOME/.kubernetes_auth"
  if [[ -r "$file" ]]; then
    KUBE_USER=$(cat "$file" | python -c 'import json,sys;print json.load(sys.stdin)["User"]')
    KUBE_PASSWORD=$(cat "$file" | python -c 'import json,sys;print json.load(sys.stdin)["Password"]')
    return
  fi
  KUBE_USER=admin
  KUBE_PASSWORD=$(python -c 'import string,random; print "".join(random.SystemRandom().choice(string.ascii_letters + string.digits) for _ in range(16))')

  # Store password for reuse.
  cat << EOF > "$file"
{
  "User": "$KUBE_USER",
  "Password": "$KUBE_PASSWORD"
}
EOF
  chmod 0600 "$file"
}

# Instantiate a kubernetes cluster
#
# Assumed vars
#   KUBE_ROOT
#   <Various vars set in config file>
function kube-up {
  # Detect the project into $PROJECT if it isn't set
  detect-project

  # Make sure we have the tar files staged on Google Storage
  find-release-tars
  upload-server-tars

  # Build up start up script for master
  local kube_temp=$(mktemp -d -t kubernetes.XXXXXX)
  trap 'rm -rf "${kube_temp}"' EXIT

  get-password
  python "${KUBE_ROOT}/third_party/htpasswd/htpasswd.py" \
    -b -c "${kube_temp}/htpasswd" "$KUBE_USER" "$KUBE_PASSWORD"
  local htpasswd=$(cat "${kube_temp}/htpasswd")

  if ! gcutil getnetwork "${NETWORK}"; then
    echo "Creating new network for: ${NETWORK}"
    # The network needs to be created synchronously or we have a race. The
    # firewalls can be added concurrent with instance creation.
    gcutil addnetwork "${NETWORK}" --range "10.240.0.0/16"
    gcutil addfirewall "${NETWORK}-default-internal" \
      --project "${PROJECT}" \
      --norespect_terminal_width \
      --sleep_between_polls "${POLL_SLEEP_INTERVAL}" \
      --network "${NETWORK}" \
      --allowed_ip_sources "10.0.0.0/8" \
      --allowed "tcp:1-65535,udp:1-65535,icmp" &
    gcutil addfirewall "${NETWORK}-default-ssh" \
      --project "${PROJECT}" \
      --norespect_terminal_width \
      --sleep_between_polls "${POLL_SLEEP_INTERVAL}" \
      --network "${NETWORK}" \
      --allowed_ip_sources "0.0.0.0/0" \
      --allowed "tcp:22" &
  fi

  echo "Starting VMs and configuring firewalls"
  gcutil addfirewall ${MASTER_NAME}-https \
    --project ${PROJECT} \
    --norespect_terminal_width \
    --sleep_between_polls "${POLL_SLEEP_INTERVAL}" \
    --network ${NETWORK} \
    --target_tags ${MASTER_TAG} \
    --allowed tcp:443 &

  (
    echo "#! /bin/bash"
    echo "mkdir -p /var/cache/kubernetes-install"
    echo "cd /var/cache/kubernetes-install"
    echo "readonly MASTER_NAME='${MASTER_NAME}'"
    echo "readonly NODE_INSTANCE_PREFIX='${INSTANCE_PREFIX}-minion'"
    echo "readonly SERVER_BINARY_TAR_URL='${SERVER_BINARY_TAR_URL}'"
    echo "readonly SALT_TAR_URL='${SALT_TAR_URL}'"
    echo "readonly MASTER_HTPASSWD='${htpasswd}'"
    grep -v "^#" "${KUBE_ROOT}/cluster/gce/templates/download-release.sh"
    grep -v "^#" "${KUBE_ROOT}/cluster/gce/templates/salt-master.sh"
  ) > "${kube_temp}/master-start.sh"

  gcutil addinstance ${MASTER_NAME}\
    --project ${PROJECT} \
    --norespect_terminal_width \
    --sleep_between_polls "${POLL_SLEEP_INTERVAL}" \
    --zone ${ZONE} \
    --machine_type ${MASTER_SIZE} \
    --image ${IMAGE} \
    --tags ${MASTER_TAG} \
    --network ${NETWORK} \
    --service_account_scopes="storage-ro,compute-rw" \
    --automatic_restart \
    --metadata_from_file "startup-script:${kube_temp}/master-start.sh" &

  for (( i=0; i<${#MINION_NAMES[@]}; i++)); do
    (
      echo "#! /bin/bash"
      echo "MASTER_NAME='${MASTER_NAME}'"
      echo "MINION_IP_RANGE=${MINION_IP_RANGES[$i]}"
      grep -v "^#" "${KUBE_ROOT}/cluster/gce/templates/salt-minion.sh"
    ) > "${kube_temp}/minion-start-${i}.sh"

    gcutil addfirewall ${MINION_NAMES[$i]}-all \
      --project ${PROJECT} \
      --norespect_terminal_width \
      --sleep_between_polls "${POLL_SLEEP_INTERVAL}" \
      --network ${NETWORK} \
      --allowed_ip_sources ${MINION_IP_RANGES[$i]} \
      --allowed "tcp,udp,icmp,esp,ah,sctp" &

    gcutil addinstance ${MINION_NAMES[$i]} \
      --project ${PROJECT} \
      --norespect_terminal_width \
      --sleep_between_polls "${POLL_SLEEP_INTERVAL}" \
      --zone ${ZONE} \
      --machine_type ${MINION_SIZE} \
      --image ${IMAGE} \
      --tags ${MINION_TAG} \
      --network ${NETWORK} \
      --service_account_scopes=${MINION_SCOPES} \
      --automatic_restart \
      --can_ip_forward \
      --metadata_from_file "startup-script:${kube_temp}/minion-start-${i}.sh" &

    gcutil addroute ${MINION_NAMES[$i]} ${MINION_IP_RANGES[$i]} \
      --project ${PROJECT} \
      --norespect_terminal_width \
      --sleep_between_polls "${POLL_SLEEP_INTERVAL}" \
      --network ${NETWORK} \
      --next_hop_instance ${ZONE}/instances/${MINION_NAMES[$i]} &
  done

  local fail=0
  local job
  for job in `jobs -p`
  do
      wait $job || let "fail+=1"
  done
  if (( $fail != 0 )); then
    echo "${fail} commands failed.  Exiting."
    exit 2
  fi

  detect-master > /dev/null

  echo "Waiting for cluster initialization."
  echo
  echo "  This will continually check to see if the API for kubernetes is reachable."
  echo "  This might loop forever if there was some uncaught error during start"
  echo "  up."
  echo

  until $(curl --insecure --user ${KUBE_USER}:${KUBE_PASSWORD} --max-time 5 \
          --fail --output /dev/null --silent https://${KUBE_MASTER_IP}/api/v1beta1/pods); do
      printf "."
      sleep 2
  done

  echo "Kubernetes cluster created."
  echo "Sanity checking cluster..."

  sleep 5

  # Basic sanity checking
  local i
  local rc # Capture return code without exiting because of errexit bash option
  for (( i=0; i<${#MINION_NAMES[@]}; i++)); do
      # Make sure docker is installed
      gcutil ssh ${MINION_NAMES[$i]} which docker >/dev/null && rc=$? || rc=$?
      if [[ "$rc" != "0" ]]; then
          echo "Docker failed to install on ${MINION_NAMES[$i]}. Your cluster is unlikely to work correctly."
          echo "Please run ./cluster/kube-down.sh and re-create the cluster. (sorry!)"
          exit 1
      fi
  done

  echo
  echo "Kubernetes cluster is running.  The master is running at:"
  echo
  echo "  https://${KUBE_MASTER_IP}"
  echo
  echo "The user name and password to use is located in ~/.kubernetes_auth."
  echo

  local kube_cert=".kubecfg.crt"
  local kube_key=".kubecfg.key"
  local ca_cert=".kubernetes.ca.crt"

  (umask 077
   gcutil ssh "${MASTER_NAME}" sudo cat /usr/share/nginx/kubecfg.crt >"${HOME}/${kube_cert}" 2>/dev/null
   gcutil ssh "${MASTER_NAME}" sudo cat /usr/share/nginx/kubecfg.key >"${HOME}/${kube_key}" 2>/dev/null
   gcutil ssh "${MASTER_NAME}" sudo cat /usr/share/nginx/ca.crt >"${HOME}/${ca_cert}" 2>/dev/null

   cat << EOF > ~/.kubernetes_auth
{
  "User": "$KUBE_USER",
  "Password": "$KUBE_PASSWORD",
  "CAFile": "$HOME/$ca_cert",
  "CertFile": "$HOME/$kube_cert",
  "KeyFile": "$HOME/$kube_key"
}
EOF

   chmod 0600 ~/.kubernetes_auth "${HOME}/${kube_cert}" \
     "${HOME}/${kube_key}" "${HOME}/${ca_cert}"
  )
}

# Delete a kubernetes cluster
function kube-down {
  # Detect the project into $PROJECT
  detect-project

  echo "Bringing down cluster"
  gcutil deletefirewall  \
    --project ${PROJECT} \
    --norespect_terminal_width \
    --sleep_between_polls "${POLL_SLEEP_INTERVAL}" \
    --force \
    ${MASTER_NAME}-https &

  gcutil deleteinstance \
    --project ${PROJECT} \
    --norespect_terminal_width \
    --sleep_between_polls "${POLL_SLEEP_INTERVAL}" \
    --force \
    --delete_boot_pd \
    --zone ${ZONE} \
    ${MASTER_NAME} &

  gcutil deletefirewall  \
    --project ${PROJECT} \
    --norespect_terminal_width \
    --sleep_between_polls "${POLL_SLEEP_INTERVAL}" \
    --force \
    ${MINION_NAMES[*]/%/-all} &

  gcutil deleteinstance \
    --project ${PROJECT} \
    --norespect_terminal_width \
    --sleep_between_polls "${POLL_SLEEP_INTERVAL}" \
    --force \
    --delete_boot_pd \
    --zone ${ZONE} \
    ${MINION_NAMES[*]} &

  gcutil deleteroute  \
    --project ${PROJECT} \
    --norespect_terminal_width \
    --sleep_between_polls "${POLL_SLEEP_INTERVAL}" \
    --force \
    ${MINION_NAMES[*]} &

  wait

}

# Update a kubernetes cluster with latest source
function kube-push {
  detect-project
  detect-master

  # Make sure we have the tar files staged on Google Storage
  find-release-tars
  upload-server-tars

  (
    echo "#! /bin/bash"
    echo "mkdir -p /var/cache/kubernetes-install"
    echo "cd /var/cache/kubernetes-install"
    echo "readonly SERVER_BINARY_TAR_URL=${SERVER_BINARY_TAR_URL}"
    echo "readonly SALT_TAR_URL=${SALT_TAR_URL}"
    grep -v "^#" "${KUBE_ROOT}/cluster/gce/templates/download-release.sh"
    echo "echo Executing configuration"
    echo "sudo salt '*' mine.update"
    echo "sudo salt --force-color '*' state.highstate"
  ) | gcutil ssh --project $PROJECT --zone $ZONE $KUBE_MASTER sudo bash

  get-password

  echo
  echo "Kubernetes cluster is running.  The master is running at:"
  echo
  echo "  https://${KUBE_MASTER_IP}"
  echo
  echo "The user name and password to use is located in ~/.kubernetes_auth."
  echo

}

# -----------------------------------------------------------------------------
# Cluster specific test helpers used from hack/e2e-test.sh

# Execute prior to running tests to build a release if required for env.
#
# Assumed Vars:
#   KUBE_ROOT
function test-build-release {
  # Build source
  "${KUBE_ROOT}/hack/build-go.sh"
  # Make a release
  "${KUBE_ROOT}/release/release.sh"
}

# Execute prior to running tests to initialize required structure. This is
# called from hack/e2e-test.sh.
#
# Assumed vars:
#   PROJECT
#   ALREADY_UP
#   Variables from config.sh
function test-setup {

  # Detect the project into $PROJECT if it isn't set
  # gce specific
  detect-project

  if [[ ${ALREADY_UP} -ne 1 ]]; then
    # Open up port 80 & 8080 so common containers on minions can be reached
    gcutil addfirewall \
      --project ${PROJECT} \
      --norespect_terminal_width \
      --sleep_between_polls "${POLL_SLEEP_INTERVAL}" \
      --target_tags ${MINION_TAG} \
      --allowed tcp:80,tcp:8080 \
      --network ${NETWORK} \
      ${MINION_TAG}-${INSTANCE_PREFIX}-http-alt
  fi

}

# Execute after running tests to perform any required clean-up.  This is called
# from hack/e2e-test.sh
#
# Assumed Vars:
#   PROJECT
function test-teardown {
  echo "Shutting down test cluster in background."
  gcutil deletefirewall  \
    --project ${PROJECT} \
    --norespect_terminal_width \
    --sleep_between_polls "${POLL_SLEEP_INTERVAL}" \
    --force \
    ${MINION_TAG}-${INSTANCE_PREFIX}-http-alt || true > /dev/null
  "${KUBE_ROOT}/cluster/kube-down.sh" > /dev/null
}
