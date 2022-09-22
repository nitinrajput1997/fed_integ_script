#!/bin/bash



RED='\033[0;31m'
GREEN='\033[0;32m'
BLACK='\033[0m'



echo -e ${GREEN}#########################################
echo -e ${GREEN}#    **MAGMA REPO**                 
echo -e ${GREEN}#########################################${BLACK}


echo -e ${GREEN} Clone Magma ${BLACK}
DIR="$HOME/workspace-1/magma"
if [ -d "$DIR" ]; then
  echo "Directory Exists ${DIR}"
else
  mkdir workspace-1 && cd workspace-1
  git clone https://github.com/magma/magma.git
fi


echo -e ${GREEN}Working on Magma Particular Commit${BLACK}
cd magma
git checkout $1
export MAGMA_ROOT=$HOME/workspace-1/magma

echo -e ${GREEN}#########################################
echo -e ${GREEN}#    *Pre-requisites**
echo -e ${GREEN}#########################################${BLACK}

echo -e ${GREEN} Install pre requisites ${BLACK}
sudo curl -O https://releases.hashicorp.com/vagrant/2.2.19/vagrant_2.2.19_x86_64.deb
sudo apt update
sudo apt install ./vagrant_2.2.19_x86_64.deb
vagrant plugin install vagrant-vbguest vagrant-disksize vagrant-vbguest vagrant-mutate vagrant-scp
pip3 install --upgrade pip
pip3 install ansible fabric3 jsonpickle requests PyYAML firebase_admin
vagrant plugin install vagrant-vbguest vagrant-disksize vbguest
echo 'export PATH="$HOME/.local/bin:$PATH"' >> $HOME/.bashrc
source $HOME/.bashrc

echo -e ${GREEN} Open up network interfaces for VM ${BLACK}
sudo mkdir -p /etc/vbox/
sudo touch /etc/vbox/networks.conf
sudo sh -c "echo '* 192.168.0.0/16' > /etc/vbox/networks.conf"
sudo sh -c "echo '* 3001::/64' >> /etc/vbox/networks.conf"


echo -e ${GREEN} Orc8r build ${BLACK}
cd
cd $MAGMA_ROOT/orc8r/cloud/docker
./build.py --deployment all

echo -e ${GREEN} Save Docker Images ${BLACK}
cd
rm -rf Image
mkdir Image
cd Image
docker save orc8r_nginx:latest | gzip > fed_orc8r_nginx.tar.gz
docker save orc8r_controller:latest  | gzip > fed_orc8r_controller.tar.gz
docker save orc8r_fluentd:latest  | gzip > fed_orc8r_fluentd.tar.gz
docker save orc8r_test:latest  | gzip > fed_orc8r_test.tar.gz

echo -e ${GREEN} Build feg ${BLACK}
cd
cd $MAGMA_ROOT && mkdir -p .cache/test_certs/ && mkdir -p .cache/feg/
cd $MAGMA_ROOT/.cache/feg/ && touch snowflake
cd
cd $MAGMA_ROOT/lte/gateway
sed -i "s/-i ''/-i/" fabfile.py
cd
cd $MAGMA_ROOT/feg/gateway/docker
docker-compose build --force-rm --parallel
cd
cd Image
docker save feg_gateway_go:latest  | gzip > fed_feg_gateway_go.tar.gz
docker save feg_gateway_python:latest  | gzip > fed_feg_gateway_python.tar.gz

echo -e ${GREEN} Vagrant Host prerequisites for federated integ test ${BLACK}
cd
cd $MAGMA_ROOT/lte/gateway && fab open_orc8r_port_in_vagrant

echo -e ${GREEN} Build test vms ${BLACK}
cd
cd $MAGMA_ROOT/lte/gateway && fab build_test_vms
cd $MAGMA_ROOT/lte/gateway && vagrant halt magma_test && vagrant halt magma_trfserver

echo -e ${GREEN} build_agw ${BLACK}
cd
cd $MAGMA_ROOT/lte/gateway/python/integ_tests/federated_tests
export MAGMA_DEV_CPUS=3
export MAGMA_DEV_MEMORY_MB=9216
fab build_agw

echo -e ${GREEN} Load Docker images ${BLACK}
set -x
cd
cd Image
cp *.gz $MAGMA_ROOT/lte/gateway
cd
cd $MAGMA_ROOT/lte/gateway
for IMAGE in `ls -a1 *.gz`
do
  echo Image being loaded $IMAGE
  gzip -cd $IMAGE > image.tar
  vagrant ssh magma -c 'cat $MAGMA_ROOT/lte/gateway/image.tar | docker load'
  rm image.tar
done
mkdir -p /tmp/fed_integ_test-images

echo -e ${GREEN}#########################################
echo -e ${GREEN}#    **FED INTEG TEST**                 
echo -e ${GREEN}#########################################${BLACK}
cd
cd $MAGMA_ROOT/lte/gateway
export MAGMA_DEV_CPUS=3
export MAGMA_DEV_MEMORY_MB=9216
fab federated_integ_test:build_all=False,orc8r_on_vagrant=True
