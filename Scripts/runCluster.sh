#!/bin/bash

# define names and paths:
masterName="master3"
slaveName="slave3"
instanceType="c5.large"
numberOfCPUs=1
sshKey=~/.ssh/tutorial-key.pem
sshKeyName="tutorial-key"
masterCliSkeleton=~/Documents/AWS/Scripts/templateMaster.json
slaveCliSkeleton=~/Documents/AWS/Scripts/templateSlave.json
tempDir=~/Documents/AWS/temp/
userName="ubuntu"
numberOfNodes=2 # how many nodes (including master)
openFoamScript=/home/greg/OpenFOAM/greg-v1712/AWS/OFAWS.sh
placementGroupName="ClusterCFD"
securityGroupName="Cluster Security"
securityGroupDescription="Security Group created by runCluster script"

# how to specify root memory ??

(( numberOfSlaves= $numberOfNodes - 1 ))
tempMasterCliSkeleton="$tempDir""tempMaster.json"
tempSlaveCliSkeleton="$tempDir""tempSlave.json"
remoteOFScript="\${HOME}/OpenFOAM/OFAWS.sh"

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
if [ ! -r $openFoamScript ] ; then
     printf "OpenFOAM script does not exist: %s\n" "$openFoamScript"
     exit 1
fi
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
if [[ $(aws ec2 describe-security-groups --query 'SecurityGroups[*].GroupName' --output text | grep -w "$securityGroupName" -c) -eq 0 ]] ; then
    aws ec2 create-security-group --group-name "$securityGroupName" --description "$securityGroupDescription"
    # allowing connection via ssh tunnel:
    aws ec2 authorize-security-group-ingress --group-name "$securityGroupName" --protocol tcp --port 22 --cidr 0.0.0.0/0
    # allowing connection within cluster
    aws ec2 authorize-security-group-ingress --group-name "$securityGroupName" --protocol tcp --port 0-65535 --source-group "$securityGroupName"
fi

securityGroupId=$(aws ec2 describe-security-groups --query 'SecurityGroups[*].[GroupName, GroupId]' --output text | grep "$securityGroupName" | sed 's/.*\t//')


# creating and editing temporary CLI Skeletons
{
# create temporary templates
mkdir $tempDir
cp $masterCliSkeleton $tempMasterCliSkeleton
cp $slaveCliSkeleton $tempSlaveCliSkeleton

# edit temporary template so appropriate placement group is used
sed -i 's/"GroupName": "",/"GroupName": "'"$placementGroupName"'",/' $tempMasterCliSkeleton $tempSlaveCliSkeleton

# edit security group ID
sed -i 's/"tutorial-sg"/"'"$securityGroupId"'"/' $tempMasterCliSkeleton $tempSlaveCliSkeleton

# edit instance type
sed -i 's/"InstanceType": "c5.large",/"InstanceType": "'"$instanceType"'",/' $tempMasterCliSkeleton $tempSlaveCliSkeleton

# edit instances number
sed -i -e 's/"MaxCount": ,/"MaxCount": '$numberOfSlaves',/' -e 's/"MinCount": ,/"MinCount": '$numberOfSlaves',/' $tempSlaveCliSkeleton
    
# edit cpu core number
sed -i 's/"CoreCount": ,/"CoreCount": '$numberOfCPUs',/' $tempMasterCliSkeleton $tempSlaveCliSkeleton


# edit names
sed -i 's/"Value": "defaultName"/"Value": "'"$masterName"'"/' $tempMasterCliSkeleton
sed -i 's/"Value": "defaultName"/"Value": "'"$slaveName"'"/' $tempSlaveCliSkeleton
}

# add disk space

# create instances 
aws ec2 run-instances --cli-input-json file://"$tempMasterCliSkeleton"
aws ec2 run-instances --cli-input-json file://"$tempSlaveCliSkeleton"

# remove temporary files
rm -r $tempDir

# get masterIP, read names and IPs of all instances, sort to get only master data with grep and remove junk with sed
masterIP="NULL"
while [[ $masterIP == "NULL" ]]
do
    masterIP=$(aws ec2 describe-instances --query 'Reservations[*].Instances[*].[Tags[0].Value, PublicIpAddress]' --output text | grep -w "$masterName" | sed 's/.*\t//')
done

# fetching master private IP
masterPrivateIP=$(aws ec2 describe-instances --query 'Reservations[*].Instances[*].[Tags[0].Value, PrivateIpAddress]' --output text | grep -w "$masterName" | sed 's/.*\t//')

# fetching slaves private IPs
slavesPrivateIPs=$(aws ec2 describe-instances --query 'Reservations[*].Instances[*].[Tags[0].Value, PrivateIpAddress]' --output text | grep -w "$slaveName" | sed 's/.*\t//' | tr '\n' ' ') # format ip1 ip2 ip3

# connecting to master instance

# enable agent forwarding
ssh-add $sshKey

# wait for master initialization
while [[ ! ( $(aws ec2 describe-instances --query 'Reservations[*].Instances[*].[Tags[0].Value, State.Name]' --output text | grep -w "$masterName" | sed 's/.*\t//' | grep "running" -c) -eq 1 && $(aws ec2 describe-instances --query 'Reservations[*].Instances[*].[Tags[0].Value, State.Name]' --output text | grep -w "$slaveName" | sed 's/.*\t//' | grep "running" -c) -eq $numberOfSlaves ) ]] 
do
    printf "Waiting for initialization\n"
    sleep 3s
done
printf "Initialization finished \n"
sleep 10s

# copy OpenFOAM script to master node
scp "$openFoamScript" "$userName""@""$masterIP":"$remoteOFScript"

# # copy necessary variables
# ssh -A "$userName""@""$masterIP" /bin/bash << EOF
#     export masterPrivateIP=$masterPrivateIP
#     export slavesPrivateIPs=$slavesPrivateIPs
#     echo \$masterPrivateIP
# EOF

# creating NFS server, so all the data is stored on Master Node:
ssh -A "$userName""@""$masterIP" /bin/bash << 'EOF'
    sudo sh -c "echo '/home/ubuntu/OpenFOAM *(rw,sync,no_subtree_check)' >> /etc/exports"
    sudo exportfs -ra
    sudo service nfs-kernel-server start
EOF

# creating known host file
ssh -A "$userName""@""$masterIP" /bin/bash << EOF
    ssh-keyscan -H -t rsa $slavesPrivateIPs  >> ~/.ssh/known_hosts
EOF

# OpenFOAM
ssh -A "$userName""@""$masterIP" /bin/bash << EOF
    # removing old directories
    for ip in $slavesPrivateIPs ; do 
        ssh \$ip 'rm -rf \${HOME}/OpenFOAM/*' 
    done
EOF

# mounting the directory on slave instances
ssh -A "$userName""@""$masterIP" /bin/bash << EOF
for ip in $slavesPrivateIPs ; do
    ssh \$ip "sudo mount $masterPrivateIP:\${HOME}/OpenFOAM \${HOME}/OpenFOAM"
done
EOF

# testing the mount point
ssh -A "$userName""@""$masterIP" /bin/bash << EOF
for ip in $slavesPrivateIPs ; do
    ssh \$ip 'ls \${HOME}/OpenFOAM' ;
done
EOF

# save file path on master for private IPs to run case in parallel:
listOfIPs='/home/ubuntu/OpenFOAM/ipList.txt'

# save IPs to a file
ssh -A "$userName""@""$masterIP" /bin/bash << EOF
    printf "$masterPrivateIP"" $slavesPrivateIPs" | tr ' ' '\n' > $listOfIPs # format ip1 \n ip2 \n ...
EOF

# run script
ssh -A "$userName""@""$masterIP" /bin/bash << EOF
    # run openFoam connected script:
    source "$remoteOFScript" $numberOfNodes $listOfIPs &
    # get OpenFoam script PID
    OFPID=\$(echo \$!)
    # wait for a program to finish
    while [ 1 ]
    do
    sleep 3s
    ps cax | grep \$OFPID || break
    done
    printf "OpenFOAM script finished\n"
EOF


# copy new data to S3 bucket
# terminate instances in securyity group when calculations and copying are finished
# http://blog.xi-group.com/2015/01/small-tip-how-to-use-aws-cli-filter-parameter/

aws ec2 terminate-instances --instance-ids $(aws ec2 describe-instances --filter Name="instance.group-name",Values="$securityGroupName" --query 'Reservations[*].Instances[*].[InstanceId]' --output text)
