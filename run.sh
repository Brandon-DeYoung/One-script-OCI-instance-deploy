#!/bin/bash

userOCID=$(oci iam user list --raw-output --query "data[?contains(\"id\",'.user.')].\"id\" | [0]")
tenancyOCID=$(oci iam user list --raw-output --query "data[?contains(\"compartment-id\",'.tenancy.')].\"compartment-id\" | [0]")
regionCode=$(oci iam region-subscription list --raw-output --query "data [?\"is-home-region\" ].\"region-name\" | [0]")
imageOCID=$(oci compute image list --all --compartment-id ocid1.tenancy.oc1..aaaaaaaaz7ly6pbgtt2s5y4uj7zfast2bz6cdrwvoqckq7v37s3q2xqbuioq --raw-output --query "sort_by(data[?\"operating-system\" == 'Oracle Linux' && \"operating-system-version\" == '8' && contains(\"display-name\", 'aarch64')], &\"time-created\") | reverse(@) | [0].id")

#Generate API key and upload API key  
if [ -n "$(ls -A ~/.oci 2>/dev/null)" ]
then
  echo "Directory ~/.oci already exists. Check to see if directory contains API keys and you've uploaded the public key to the OCI cloud console."
else
  echo "Generating API keypair and uploading it to the OCI cloud console."
  mkdir ~/.oci 
  openssl genrsa -out ~/.oci/oci_api_key.pem 2048
  chmod go-rwx ~/.oci/oci_api_key.pem
  openssl rsa -pubout -in ~/.oci/oci_api_key.pem -out ~/.oci/oci_api_key_public.pem
  fingerprint=$(oci iam user api-key upload --user-id $userOCID --key-file ~/.oci/oci_api_key_public.pem|grep -oP '(?<=fingerprint": ")[^"]*')
  apiPrivateKey=$(cat ~/.oci/oci_api_key.pem|tr -d '\n'|tr -d ' ')
  echo
fi

#Generate SSH keypair
if [ -n "$(ls -A ~/.ssh 2>/dev/null)" ]
then
  echo "Directory ~/.ssh already exists."
else
  ssh-keygen -b 2048 -t rsa -N "" -f ~/.ssh/id_rsa
  sshPublicKey=\"$(cat ~/.ssh/id_rsa.pub)\"
fi

mkdir terraform

echo -e "variable \"tenancy_ocid\" {}

variable \"compartment_ocid\" {}

variable \"user_ocid\" {}

variable \"rsa_private_key_path\" {}

variable \"fingerprint\" {}

variable \"region_identifier\" {}

variable \"compute_shape\" {}

variable \"instance_source_details_boot_volume_size_in_gbs\" {}

variable \"memory_in_gbs\" {}

variable \"ocpus\" {}

variable \"image_id\" {}

variable \"ssh_public_key_path\" {}

variable \"budget_amount\" {}

variable \"alert_rule_recipients\" {}

variable \"vcn_cidr\" {}

variable \"subnet\" {}

variable \"cidr_ingress\" {}

variable \"ports\" {}

variable \"ssh_public_key\" {}

" >> terraform/variables.tf

###################################################################################

echo -e "tenancy_ocid    = \"$tenancyOCID\"
compartment_ocid         = \"$tenancyOCID\"
user_ocid                = \"$userOCID\"
rsa_private_key_path     = \"~/.oci/oci_api_key.pem\"
fingerprint              = \"$fingerprint\"
region_identifier        = \"$regionCode\"
compute_shape            = \"VM.Standard.A1.Flex\"
instance_source_details_boot_volume_size_in_gbs = \"50\"
memory_in_gbs            = \"6\"
ocpus                    = \"1\"
image_id                 = \"$imageOCID\"
ssh_public_key_path      = \"~/.ssh/id_rsa.pub\"
budget_amount            = \"1\"
alert_rule_recipients    = \"testemail@gmail.com\"
vcn_cidr                 = \"10.0.0.0/16\"
subnet                   = \"10.0.1.0/24\"
cidr_ingress             = \"0.0.0.0/0\"
ports                    = [\"22\"]
ssh_public_key           = $sshPublicKey
" >> terraform/terraform.tfvars

###################################################################################

echo -e "provider \"oci\" {
  tenancy_ocid           = var.tenancy_ocid
  user_ocid              = var.user_ocid
  private_key_path       = var.rsa_private_key_path
  fingerprint            = var.fingerprint
  region                 = var.region_identifier
}
" >> terraform/provider.tf

###################################################################################

echo -e "resource \"oci_core_virtual_network\" \"vcn\" {
  cidr_block             = var.vcn_cidr
  compartment_id         = var.tenancy_ocid
  display_name           = \"tf_vcn\"
}

resource \"oci_core_subnet\" \"public_subnet\" {
  cidr_block             = var.subnet
  compartment_id         = var.tenancy_ocid
  vcn_id                 = oci_core_virtual_network.vcn.id
  display_name           = \"public_subnet\"
  security_list_ids      = [oci_core_security_list.security_list.id]
  route_table_id         = oci_core_route_table.route_table.id
  dhcp_options_id        = oci_core_virtual_network.vcn.default_dhcp_options_id
}

resource \"oci_core_internet_gateway\" \"internet_gateway\" {
  compartment_id         = var.tenancy_ocid
  display_name           = \"tf_igw\"
  vcn_id                 = oci_core_virtual_network.vcn.id
}

resource \"oci_core_route_table\" \"route_table\" {
  compartment_id        = var.tenancy_ocid
  vcn_id                = oci_core_virtual_network.vcn.id
  display_name          = \"tf_route_table\"

  route_rules {
    destination         = \"0.0.0.0/0\"
    destination_type    = \"CIDR_BLOCK\"
    network_entity_id   = oci_core_internet_gateway.internet_gateway.id
  }
}

resource \"oci_core_security_list\" \"security_list\" {
  compartment_id        = var.tenancy_ocid
  vcn_id                = oci_core_virtual_network.vcn.id
  display_name          = \"tf_security_list\"

  egress_security_rules {
    protocol            = \"6\"
    destination         = \"0.0.0.0/0\"
  }

  ingress_security_rules {
    protocol            = \"6\"
    source              = \"0.0.0.0/0\"
    stateless           = true

    tcp_options {
      max               = \"22\"
      min               = \"22\"
    }
  }

  ingress_security_rules {
    protocol            = \"6\"
    source              = \"0.0.0.0/0\"
    stateless           = true

    tcp_options {
      max               = \"80\"
      min               = \"80\"
    }
  }
  
} " >> terraform/vcn.tf

###################################################################################

echo -e "data "oci_identity_availability_domains" "ads" {
  compartment_id = var.tenancy_ocid
} " >> terraform/availability-domains.tf

###################################################################################

echo -e "resource \"oci_core_instance\" \"instance\" {
  availability_domain   = data.oci_identity_availability_domains.ads.availability_domains[0].name
  compartment_id        = var.tenancy_ocid
  display_name          = \"tf_instance\"
  shape                 = var.compute_shape

  shape_config {
    ocpus               = var.ocpus
    memory_in_gbs       = var.memory_in_gbs
  }

  create_vnic_details {
    subnet_id           = oci_core_subnet.public_subnet.id
    display_name        = \"vnic\"
    assign_public_ip    = true
    assign_private_dns_record = false
  }

  source_details {
    source_type         = \"image\"
    source_id           = var.image_id
    boot_volume_size_in_gbs = var.instance_source_details_boot_volume_size_in_gbs
  }

  metadata = {
    ssh_authorized_keys = $sshPublicKey
  }
} " >> terraform/compute.tf

###################################################################################

cd terraform/
terraform init

# Get the total number of availability domains
num_availability_domains=$(oci iam availability-domain list --all --raw-output | jq -r '.data | length')

# Index for the availability domain
x=0
y=1

# Keep track of whether terraform apply succeeded
success=0

# Loop until success or we have tried all availability domains
while [ $x -lt $num_availability_domains ]; do
    # Update the terraform script with the new availability domain index
    echo "Attempting to provision in AD-$y"
    sed -i "s#availability_domains\[\([0-9]*\)\]#availability_domains\[$x\]#" compute.tf

    # Run terraform apply and capture both stdout and stderr
    output=$(terraform apply -auto-approve -var-file="terraform.tfvars" 2>&1)

    # Check if the output contains "Out of host capacity" error
    if echo "$output" | grep -q "500-InternalError, Out of host capacity"; then
        # Increment x (modulo the number of availability domains to wrap around)
        echo "Failed to provision in AD-$y..." 
        x=$(( ($x + 1) % $num_availability_domains ))
        y=$(($x + 1))
    else
        # If there was no error, set success to 1 and break the loop
        success=1
        break
    fi
done

# Check if terraform apply was successful
if [ $success -eq 1 ]; then
    echo "Resources created successfully in AD-$y"
else
    echo "Failed to create resources in all availability domains."
fi
