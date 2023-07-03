# One script OCI instance deploy

### Deploy an instance within Oracle Cloud Infrastructure along with all of the resources needed to run it and more with a single bash script. Resources and instance deployed conform to the [Always Free resource restrictions](https://docs.oracle.com/en-us/iaas/Content/FreeTier/freetier_topic-Always_Free_Resources.htm).

## To deploy
1. Launch the OCI Cloud Shell and clone ```run.sh``` to it. 
2. Make ```run.sh``` executable with ```chmod +x run.sh```
3. ```./run.sh``` to execute the script

The script should run the Terraform needed to create the VCN, subnet, proper gateways and route tables, and security lists needed, along with making an attempt to provision the instance within availaiblity domain 1 (AD1), AD2, and then AD3 (Region dependent, will only loop through amount of ADs per region).

## Ansible
* To impliment

## To connect
From the cloudshell, run ```ssh -i ~/.ssh/id_rsa opc@```< IP address >
* The IP address is found within the console. Click into Compute > Instances > ```tf_instance``` > Instance access > copy Public IP address

## Troubleshooting
### If your instance is not created in any of the availability domains:
* ```cd terraform```
* edit ```compute.tf```'s ```availability_domain``` variable
* * availability_domain   = data.oci_identity_availability_domains.ads.availability_domains[x].name
* * ```x``` = (AD index - 1), AD1 would equal an ```x``` of 0, AD2=1, AD3=2
* ```terraform apply -auto-approve -var-file="terraform.tfvars"```

## Note
This method is destructive and may overwrite your previously stored data such as SSH keypairs, API keypairs, API key fingerprints, and more. Understand the contents within ```run.sh``` and at this point run this script at your own risk.