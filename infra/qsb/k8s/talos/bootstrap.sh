#!/usr/bin/env bash


DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
TALENV_FILE="${DIR}/talenv.sops.yaml"
TALSECRET_FILE="${DIR}/talsecret.sops.yaml"
TALCONFIG_FILE="${DIR}/talconfig.yaml"
CLUSTERCONFIG_DIR="${DIR}/clusterconfig"
APPS_DIR="${DIR}/../apps"
INTEGRATIONS_DIR="${DIR}/integrations"


rm -rf "$CLUSTERCONFIG_DIR"
talhelper genconfig --env-file "$TALENV_FILE" --secret-file "$TALSECRET_FILE" --config-file "$TALCONFIG_FILE" --out-dir "$CLUSTERCONFIG_DIR" > /dev/null 2>&1

export SOPS_AGE_KEY_FILE="${DIR}../../../age.key"
export TALOSCONFIG_FILE="$CLUSTERCONFIG_DIR/../../../../age.key"

NODES=$(yq e -o=j -I=0 '.nodes[]' "$TALCONFIG_FILE")

while IFS=\= read -r action; do
    HOSTNAME=$(yq e '.hostname' <<< "$action" | cut -d . -f 1)
    IP_ADDRESS=$(yq e '.ipAddress' <<< "$action")
    echo "Applying config for $HOSTNAME ($IP_ADDRESS)"
    talosctl apply-config --insecure -n "$IP_ADDRESS" -f "$CLUSTERCONFIG_DIR"/*"${HOSTNAME}"*.yaml
done <<EOF
$NODES
EOF

CNI="${INTEGRATIONS_DIR}/cni"
CNI_CHARTS="${CNI}/charts"
CNI_VALUES="${CNI}/values.yaml"

rm -rf "${CNI_CHARTS}"
envsubst < "${APPS_DIR}"/kube-system/cilium/app/values.yaml > "${CNI_VALUES}"
kustomize build --enable-helm "${CNI}" | kubectl apply -f -
rm "${CNI_VALUES}"
rm -rf "${CNI_CHARTS}"

KCA="${INTEGRATIONS_DIR}/kubelet-csr-approver"
KCA_CHARTS="${KCA}/charts"
KCA_VALUES="${KCA}/values.yaml"
rm -rf "${KCA_CHARTS}"
envsubst < "${APPS_DIR}"/system-controllers/kubelet-csr-approver/app/values.yaml > "${KCA_VALUES}"
if ! kubectl get ns system-controllers >/dev/null 2>&1; then
  kubectl create ns system-controllers
fi
kustomize build --enable-helm "${KCA}" | kubectl apply -f -
rm "${KCA_VALUES}"
rm -rf "${KCA_CHARTS}"

rm -rf "$CLUSTERCONFIG_DIR"
