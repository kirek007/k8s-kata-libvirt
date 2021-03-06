#!/usr/bin/env bash

POD_NETWORK="10.1.0.0/16"

kubeadm init --apiserver-advertise-address="${MASTER_IP}" --apiserver-cert-extra-sans="${MASTER_IP}" --token "${KUBERNETES_TOKEN}" --token-ttl 3600m --pod-network-cidr="${POD_NETWORK}"

export KUBECONFIG=/etc/kubernetes/admin.conf

#systemctl restart kubelet
kubectl taint nodes --all node-role.kubernetes.io/master-

# Prepare config
export HOME=/home/vagrant
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown "$(id vagrant -u)":"$(id vagrant -g)" $HOME/.kube/config
sudo cp $HOME/.kube/config /vagrant

sleep 5

curl https://docs.projectcalico.org/v3.9/manifests/calico.yaml -O
sed -i -e "s?192.168.0.0/16?${POD_NETWORK}?g" calico.yaml
kubectl apply -f calico.yaml

echo "Waiting for network to become Ready"
until [ $(kubectl get po --field-selector status.phase!=Running -A 2>/dev/null | wc -l) -gt 0 ]; do
  echo -n "."
  sleep 5
done

cat <<EOF | kubectl apply -f -
---
apiVersion: node.k8s.io/v1beta1
kind: RuntimeClass
metadata:
  name: kata-qemu
handler: kata-qemu
---
apiVersion: node.k8s.io/v1beta1
kind: RuntimeClass
metadata:
  name: kata-fc
handler: kata-fc
---
apiVersion: node.k8s.io/v1beta1
kind: RuntimeClass
metadata:
  name: kata-runtime
handler: kata-runtime
---
apiVersion: apps/v1
kind: Deployment
metadata:
  creationTimestamp: null
  labels:
    app: kata-nginx
  name: kata-nginx
spec:
  replicas: 1
  selector:
    matchLabels:
      app: kata-nginx
  template:
    metadata:
      labels:
        app: kata-nginx
    spec:
      runtimeClassName: kata-runtime
      containers:
      - image: nginx
        name: nginx
        resources: {}
EOF
