#!/bin/bash
set -a
if [ -z $1 ]; then
	echo -e "Usage: \n bash setup.sh [OPTIONS]\n \n Available Options: \n      install           Install NVIDIA Cloud Native Core\n      validate          Validate NVIDIA Cloud Native Core x86 only\n      uninstall         Uninstall NVIDIA Cloud Native Core"
	echo
	exit 1
fi

sudo ls > /dev/null

version=$(cat cnc_version.yaml | awk -F':' '{print $2}' | head -n1 | tr -d ' ' | tr -d '\n\r')
cp cnc_values_$version.yaml cnc_values.yaml
sed -i "1s/^/cnc_version: $version\n/" cnc_values.yaml

# Ansible Install
ansible_install() {
	os=$(cat /etc/os-release | grep -iw ID | awk -F'=' '{print $2}') 
	version=$(cat /etc/os-release | grep -i VERSION_CODENAME | awk -F'=' '{print $2}')
	if [[ $os == "ubuntu" && $version != "focal" ]]; then 
		echo "Installing Ansible"
		{
        	sudo apt-add-repository ppa:ansible/ansible -y 
        	sudo apt update 
        	sudo apt install ansible sshpass -y 
		} >/dev/null
	elif [[ $os == "ubuntu" && $version == "focal" ]]; then
		echo "Installing Ansible"
		{ 
		sudo -E apt update
        sudo -E apt install ansible sshpass -y
		} >/dev/null 
	elif [ $os == "rhel*" ]; then
		version=$(cat /etc/os-release | grep VERSION_ID | awk -F'=' '{print $2}')
		if [ $version == "*7.*" ]; then
			sudo subscription-manager repos --enable rhel-7-server-ansible-2.9-rpms
			sudo yum install ansible -y
		elif [ $version == "*8.*" ]; then
			sudo subscription-manager repos --enable ansible-2.9-for-rhel-8-x86_64-rpms
			sudo yum install ansible -y
		fi
	fi
}
# Prechecks
prerequisites() {
url=$(cat cnc_values.yaml | grep k8s_apt_key | awk -F '//' '{print $2}' | awk -F'/' '{print $1}')
code=$(curl --connect-timeout 3 -s -o /dev/null -w "%{http_code}" http://$url)
echo "Checking this system has valid prerequisites"
echo
if [ $code == 200 ]; then
	echo "This system has an internet access"
	echo
elif [ $code != 200 ]; then
    echo "This system does not have a internet access"
	echo
    exit 1
fi
}

if ! hash sudo ansible 2>/dev/null
then
    prerequisites
	ansible_install 
else
	echo "Ansible Already Installed"
	echo
fi


if [ $1 == "install" ]; then
	echo
        echo "Installing NVIDIA Cloud Native Core Version $version"
		id=$(sudo dmidecode --string system-uuid | awk -F'-' '{print $1}' | cut -c -3)
		manufacturer=$(sudo dmidecode -s system-manufacturer | egrep -i "microsoft corporation|Google")
		if [[ $id == 'ec2' || $manufacturer == 'Microsoft Corporation' || $manufacturer == 'Google' ]]; then
			sed -ie 's/- hosts: master/- hosts: all/g' *.yaml
			nvidia_driver=$(ls /usr/src/ | grep nvidia | awk -F'-' '{print $1}')
			if [[ $nvidia_driver == 'nvidia' ]]; then
				ansible -c local -i localhost, all -m lineinfile -a "path={{lookup('pipe', 'pwd')}}/cnc_values.yaml regexp='cnc_docker: no' line='cnc_docker: yes'"
			fi
			ansible-playbook -c local -i localhost, cnc-installation.yaml
			exit 1
		fi

	ansible-playbook -i hosts cnc-installation.yaml
elif [ $1 == "uninstall" ]; then
	echo
	echo "Unstalling NVIDIA Cloud Native Core"
        ansible-playbook -i hosts cnc-uninstall.yaml
elif [ $1 == "validate" ]; then
	echo
	echo "Validating NVIDIA Cloud Native Core"
        ansible-playbook -i hosts cnc-validation.yaml
else
	echo -e "Usage: \n bash setup.sh [OPTIONS]\n \n Available Options: \n      install     Install NVIDIA Cloud Native Core\n      validate    Validate NVIDIA Cloud Native Core\n      uninstall   Uninstall NVIDIA Cloud Native Core"
        echo
        exit 1
	fi
