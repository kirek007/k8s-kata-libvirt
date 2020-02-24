#!/usr/bin/env bash

# Disable DNSSEC
sed -i "s/DNSSEC=yes/DNSSEC=no/g" /etc/systemd/resolved.conf
sed -i "s/DNS=4.2.2.1 4.2.2.2 208.67.220.220/DNS=1.1.1.1/g" /etc/systemd/resolved.conf
sed -i "s/\[4.2.2.1, 4.2.2.2, 208.67.220.220\]/\[1.1.1.1\]/g" /etc/netplan/01-netcfg.yaml

systemctl restart systemd-networkd.service systemd-resolved.service
netplan apply

modprobe overlay
modprobe br_netfilter

cat >> /etc/sysctl.conf <<EOF
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOF

sysctl -p


KUBERNETES_VERSION=1.17

# Install kata and firecracker

wget -q https://github.com/kata-containers/runtime/releases/download/1.10.0/kata-static-1.10.0-x86_64.tar.xz
tar -xf kata-static-1.10.0-x86_64.tar.xz
sudo cp -r opt /
rm -rf opt kata

apt-get update && apt-get install -y apt-transport-https curl
curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
add-apt-repository "deb https://apt.kubernetes.io/ kubernetes-xenial main"
apt-get update
apt-get install -y  kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl

# Install OCR

# Ubuntu (18.04, 19.04 and 19.10)
. /etc/os-release
sudo sh -c "echo 'deb http://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/x${NAME}_${VERSION_ID}/ /' > /etc/apt/sources.list.d/devel:kubic:libcontainers:stable.list"
wget -nv https://download.opensuse.org/repositories/devel:kubic:libcontainers:stable/x${NAME}_${VERSION_ID}/Release.key -O- | sudo apt-key add -

sudo apt-get update -qq
sudo apt-get install -y -qq runc cri-o-$KUBERNETES_VERSION

cat >> /etc/crio/crio.conf << EOF
[crio.runtime.runtimes.kata-runtime]
runtime_path = "/opt/kata/bin/kata-runtime"
runtime_type = "oci"
[crio.runtime.runtimes.kata-qemu]
runtime_path = "/opt/kata/bin/kata-qemu"
runtime_type = "oci"
[crio.runtime.runtimes.kata-fc]
runtime_path = "/opt/kata/bin/kata-fc"
runtime_type = "oci"
EOF

cat > /etc/cni/net.d/100-crio-bridge.conf << EOF
{
    "cniVersion": "0.3.1",
    "name": "crio-bridge",
    "type": "bridge",
    "bridge": "cni0",
    "isGateway": true,
    "ipMasq": true,
    "hairpinMode": true,
    "ipam": {
        "type": "host-local",
        "routes": [
            { "dst": "0.0.0.0/0" }
        ],
        "ranges": [
            [{ "subnet": "10.88.0.0/16" }]
        ]
    }
}
EOF

#sed -i "s/manage_ns_lifecycle = false/manage_ns_lifecycle = true/g" /etc/crio/crio.conf

sudo systemctl daemon-reload
sudo systemctl enable crio
sudo systemctl start crio

# Tweak system
swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

