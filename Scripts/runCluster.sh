# define names and paths:
masterName="master"
slaveName="slave"
instanceType="c5.large"
sshKey=~/.ssh/tutorial-key.pem
sshKeyName="tutorial-key"
masterCliSkeleton=~/Documents/AWS/Scripts/templateMaster.json
slaveCliSkeleton=~/Documents/AWS/Scripts/templateSlave.json
tempDir=~/Documents/AWS/temp/
userName="ubuntu"
numberOfCPUs="default"
numberOfNodes=4 # how many nodes (including master)
openFoamScript=/home/greg/OpenFOAM/greg-v1712/AWS/OFAWS.sh
placementGroupName="ClusterCFD"
securityGroupName="Cluster Security"
securityGroupDescription="Security Group created by runCluster script"

# how to specify master memory ??

numberOfSlaves=( $numberOfNodes - 1 )
tempMasterCliSkeleton="$tempDir""tempMaster.json"
tempSlaveCliSkeleton="$tempDir""tempSlave.json"

# check if paths are ok (if files exist and are readable)
{
if [ ! -r $sshKey ] ; then
     printf "sshKey does not exist: %s\n" "$sshKey"
     exit 1
fi
if [ ! -r $masterCliSkeleton ] ; then
     printf "Master CLI Skeleton does not exist: %s\n" "$masterCliSkeleton"
     exit 1
fi
if [ ! -r $slaveCliSkeleton ] ; then
     printf "Slave CLI Skeleton does not exist: %s\n" "$slaveCliSkeleton"
     exit 1
fi
# if [ ! -r $openFoamScript ] ; then
#      printf "OpenFOAM script does not exist: %s\n" "$openFoamScript"
#      exit 1
# fi
}

# create placement group
# check if placement group already exists
if [[ $(aws ec2 describe-placement-groups --output text | sed 's/PLACEMENTGROUPS\t//' | sed 's/\t.*//' | grep -w -i $placementGroupName -c) -eq 0 ]] ; then
# if does not exist, create placement group:
    aws ec2 create-placement-group --group-name $placementGroupName --strategy cluster
fi

# check if instance type is correct
if [[ $(aws pricing get-attribute-values --service-code AmazonEC2 --attribute-name instanceType --region us-east-1 --output text | sed 's/ATTRIBUTEVALUES\t//g' | grep -w $instanceType -c ) -eq 0 ]] ; then
    printf "ERROR! Invalid instance type:""$instanceType""\n"
fi

# check if security group exists, if not, create one:
if [[ $(aws ec2 describe-security-groups --query 'SecurityGroups[*].GroupName' --output text | grep -w $securityGroupName -c) -eq 0 ]] ; then
    aws ec2 create-security-group --group-name "$securityGroupName" --description "$securityGroupDescription"
    # allowing connection via ssh tunnel:
    aws ec2 authorize-security-group-ingress --group-name "$securityGroupName" --protocol tcp --port 22 --cidr 0.0.0.0/0
    # allowing connection within cluster
    aws ec2 authorize-security-group-ingress --group-name "$securityGroupName" --protocol tcp --port 0-65535 --source-group "$securityGroupName"
fi

# creating ad editing temporary CLI Skeletons
{
# create temporary templates
mkdir $tempDir
cp $masterCliSkeleton $tempMasterCliSkeleton
cp $slaveCliSkeleton $tempSlaveCliSkeleton

# edit temporary template so appropriate placement group is used
sed -i 's/"GroupName": "",/"GroupName": '"$placementGroupName"',/' $tempMasterCliSkeleton $tempSlaveCliSkeleton

# edit instance type
sed -i 's/"InstanceType": "c5.large",/"InstanceType": "'"$instanceType"'",/' $tempMasterCliSkeleton $tempSlaveCliSkeleton

# edit instances number
sed -i -e 's/"MaxCount": ,/"MaxCount": '$numberOfSlaves',/' -e 's/"MinCount": ,/"MinCount": '$numberOfSlaves',/' $tempSlaveCliSkeleton
    
# edit cpu core number
if [[ ! $numberOfCPUs == "default" ]] ; then
    sed -i 's/"CoreCount": ,/"CoreCount": '$numberOfCPUs',/' $tempMasterCliSkeleton $tempSlaveCliSkeleton
fi

# edit names
sed -i 's/"Value": "defaultName"/"Value": "'"$masterName"'"/' $tempMasterCliSkeleton
sed -i 's/"Value": "defaultName"/"Value": "'"$slaveName"'"/' $tempSlaveCliSkeleton
}

# create instances


# remove temporary files
rm -r $tempDir

# get masterIP, read names and IPs of all instances, sort to get only master data with grep and remove junk with sed
masterIP=$(aws ec2 describe-instances --query 'Reservations[*].Instances[*].[Tags[0].Value, PublicIpAddress]' --output text | grep "$masterName" | sed 's/.*\t//')


# connecting to master instance

# enable agent forwarding
ssh-add $sshKey

# establish ssh connection
ssh -A "$userName""@""$masterIP"

# creating NFS server, so all the data is stored on Master Node:
sudo sh -c "echo '/home/ubuntu/OpenFOAM *(rw,sync,no_subtree_check)' >> /etc/exports"
sudo exportfs -ra
sudo service nfs-kernel-server start

# fetching slave master IP
masterPrivateIP= <wyciągnij z AWSa prywatne IP mastera>
# fetching slaves private IPs
slavesPrivateIPs= <wyciągnij z AWSa prywatne IP niewolników> # format ip1 ip2 ip3

# removing old directories
for ip in $slavesIPs ; do 
    ssh $ip 'rm -rf ${HOME}/OpenFOAM/*' 
done

# mounting the directory on slave instances
for ip in $slavesIPs ; do
    ssh $ip 'sudo mount "$masterPrivateIP":${HOME}/OpenFOAM ${HOME}/OpenFOAM'
done

# testing the mount point
for ip in $slabesIPs ; do
    ssh $ip 'ls ${HOME}/OpenFOAM' ;
done

# save list of private IPs to run case in parallel:
listOfIPs='/home/ubuntu/OpenFoam/ipList.txt'

# save IPs to a file
"$masterPrivateIP"" $slavesPrivateIPs" | sed 's/" "/"\n"/' > listOfIPs







# run openFoam connected script:
!!! copy the script first to the master node along with list
bash OFAWS.sh
# let it run in background
bg
