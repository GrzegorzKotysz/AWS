#!/bin/bash

# define names and paths:
caseName="test"

instanceType="c5.large" #c5.large
numberOfCPUs=1
numberOfNodes=2 # how many nodes (including master)

diskDeviceName="/dev/sda1" # edit disk space
diskSize=20 # in GB

openFoamScript=~/Documents/AWS/Scripts/OFAWS.sh
masterCliSkeleton=~/Documents/AWS/Scripts/templateMaster.json
slaveCliSkeleton=~/Documents/AWS/Scripts/templateSlave.json
tempDir=~/Documents/AWS/temp/

S3Bucket=""
userName="ubuntu" # as in host

placementGroupName="ClusterTest"
securityGroupName="ClusterTest"
securityGroupDescription="Security Group created by runCluster script"

EC2trustFile=~/Documents/AWS/Scripts/iamEC2trust.json
permissionsPolicyFile=~/Documents/AWS/Scripts/iamPermissionsPolicy.json

sshKey=~/.ssh/tutorial-key.pem
sshKeyName="tutorial-key"
region=eu-central-1
tag=Case # tag name for iam policies

# calculated variables
masterName="$caseName""Master"
slaveName="$caseName""Slave"
iamPolicyName="$caseName""Policy"
iamRoleName="$caseName""Role"
instanceProfileName="$caseName""Profile"
S3BucketFolder="$S3Bucket""$caseName"

(( numberOfSlaves= $numberOfNodes - 1 ))
tempMasterCliSkeleton="$tempDir""tempMaster.json"
tempSlaveCliSkeleton="$tempDir""tempSlave.json"
tempPermissionsPolicyFile="$tempDir""tempIamPermissionsPolicy.json"
remoteOFScript="\$FOAM_RUN/OFaws.sh"

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

# check if instance type is correct
if [[ $(aws pricing get-attribute-values --service-code AmazonEC2 --attribute-name instanceType --region us-east-1 --output text | sed 's/ATTRIBUTEVALUES\t//g' | grep -w $instanceType -c ) -eq 0 ]] ; then
    printf "ERROR! Invalid instance type:""$instanceType""\n"
    exit 1
fi

# create placement group
# check if placement group already exists
if [[ $(aws ec2 describe-placement-groups --output text | sed 's/PLACEMENTGROUPS\t//' | sed 's/\t.*//' | grep -w -i $placementGroupName -c) -eq 0 ]] ; then
# if does not exist, create placement group:
    aws ec2 create-placement-group --group-name $placementGroupName --strategy cluster
fi

# create security group
# get your ip to create temporary inbound rule
myip=$(curl http://checkip.amazonaws.com)
if [[ $(aws ec2 describe-security-groups --query 'SecurityGroups[*].GroupName' --output text | grep -w "$securityGroupName" -c) -eq 0 ]] ; then
    aws ec2 create-security-group --group-name "$securityGroupName" --description "$securityGroupDescription"
    # allowing connection within cluster
    aws ec2 authorize-security-group-ingress --group-name "$securityGroupName" --protocol tcp --port 0-65535 --source-group "$securityGroupName"
fi
# allowing connection via ssh tunnel:
aws ec2 authorize-security-group-ingress --group-name "$securityGroupName" --protocol tcp --port 22 --cidr ${myip}/32

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

# add disk space
sed -i 's\"DeviceName": ""\"DeviceName": "'"$diskDeviceName"'"\' $tempMasterCliSkeleton
sed -i 's/"VolumeSize": 0/"VolumeSize": '$diskSize'/' $tempMasterCliSkeleton

# edit key [case name]
sed -i -e 's/tag-name/'$tag'/' -e 's/tag-value/'$caseName'/' $tempMasterCliSkeleton $tempSlaveCliSkeleton
}

# get user ID for arn adresses
userID=$(aws sts get-caller-identity --query 'Account' --output text)

# if exists, remove role from instance profile and delete old instance profile
if [ $(aws iam list-instance-profiles --query InstanceProfiles[*].InstanceProfileName | grep -w $instanceProfileName -c) -eq 1 ] ; then
    # if attached, remove role from instance profile
    if ! [ "$(aws iam get-instance-profile --instance-profile-name $instanceProfileName --query "InstanceProfile".Roles[*].RoleName)" == 'null' ] ; then
        aws iam remove-role-from-instance-profile --instance-profile-name $instanceProfileName --role-name $(aws iam get-instance-profile --instance-profile-name $instanceProfileName --query "InstanceProfile".Roles[*].RoleName --output text)
    fi
    aws iam delete-instance-profile --instance-profile-name $instanceProfileName
fi

# if exists, delete old IAM role
if [ $(aws iam list-roles --query Roles[*].RoleName | grep -w $iamRoleName -c) -eq 1 ] ; then
    # if policies attached, delete them:
    for policyAttached in $(aws iam list-role-policies --role-name $iamRoleName --query PolicyNames[*] --output text)
    do
        aws iam delete-role-policy --role-name $iamRoleName --policy-name $policyAttached
    done
    aws iam delete-role --role-name $iamRoleName
fi

# create IAM role for terminating instance and sending data to S3 bucket
aws iam create-role --role-name $iamRoleName --assume-role-policy-document file://$EC2trustFile

# edit permissions policy file to include appropriate S3 folder and edit condition for terminate instances policy
cp $permissionsPolicyFile $tempPermissionsPolicyFile

sed -i -e 's|defaultBucket|'"$S3BucketFolder"'/*|' \
    -e 's|arn:aws:ec2:region:userID:instance|arn:aws:ec2:'$region':'$userID':instance|' \
    -e 's|"ec2:ResourceTag/tag-name":"tag-value"|"ec2:ResourceTag/'$tag'":"'$caseName'"|' "$tempPermissionsPolicyFile"

# attach new role policy
aws iam put-role-policy --role-name $iamRoleName --policy-name $iamPolicyName --policy-document file://$tempPermissionsPolicyFile
    
# create the instance profile required by EC2 to contain the role
if [ $(aws iam list-instance-profiles --query InstanceProfiles[*].InstanceProfileName | grep -w testProfile -c) -eq 0 ] ; then
    aws iam create-instance-profile --instance-profile-name $instanceProfileName
fi

# add the role to the instance profile
aws iam add-role-to-instance-profile --instance-profile-name $instanceProfileName --role-name $iamRoleName

# associate-iam-instance-profile with instance
sed -i 's|instanceProfileName|'$instanceProfileName'|' $tempMasterCliSkeleton

# waitings help with: An error occurred (InvalidParameterValue) when calling the RunInstances operation: Value (testProfile) for parameter iamInstanceProfile.name is invalid. Invalid IAM Instance Profile name
sleep 15s

# create instances 
aws ec2 run-instances --cli-input-json file://"$tempMasterCliSkeleton"
aws ec2 run-instances --cli-input-json file://"$tempSlaveCliSkeleton"

# remove temporary files
rm -r $tempDir

# enable agent forwarding
ssh-add $sshKey

# wait for master initialization
while [[ ! ( $(aws ec2 describe-instances --filter Name=tag:Name,Values=$masterName --query 'Reservations[*].Instances[*].[State.Name]' --output text | grep -w "running" -c) -eq 1 && $(aws ec2 describe-instances --filter Name=tag:Name,Values=$slaveName --query 'Reservations[*].Instances[*].[State.Name]' --output text | grep -w "running" -c) -eq $numberOfSlaves ) ]] 
do
    printf "Waiting for initialization\n"
    sleep 3s
done
printf "Initialization finished \n"

# connecting to master instance

# get masterIP, read names and IPs of all instances, sort to get only master data with grep and remove junk with sed
masterIP="NULL"
while [[ $masterIP == "NULL" ]]
do
    masterIP=$(aws ec2 describe-instances --filter Name="tag:Name",Values=$masterName Name="instance-state-name",Values="running" --query 'Reservations[*].Instances[*].[PublicIpAddress]' --output text)
done

# fetching master private IP
masterPrivateIP=$(aws ec2 describe-instances --filter Name="tag:Name",Values=$masterName Name="instance-state-name",Values="running" --query 'Reservations[*].Instances[*].[PrivateIpAddress]' --output text)

# fetching slaves private IPs
slavesPrivateIPs=$(aws ec2 describe-instances --filter Name="tag:Name",Values=$slaveName Name="instance-state-name",Values="running" --query 'Reservations[*].Instances[*].[PrivateIpAddress]' --output text | tr '\n' ' ') # format ip1 ip2 ip3

# copy OpenFOAM script [and other data if needed] to master node
while 
    scp -q "$openFoamScript" "$userName""@""$masterIP":"$remoteOFScript"
    ssh -q "$userName""@""$masterIP" ! test -e "$remoteOFScript"
do 
    printf "OF script yet to be copied, please wait\n"
    sleep 3s
done
if ssh -q "$userName""@""$masterIP" test -e "$remoteOFScript" ; then
    printf "OF script copied successfully\n"
else   
    printf "ERROR encountered while copying OF script, exiting...\n"
    exit 1
fi
    
# creating NFS server, so all the data is stored on Master Node:
ssh -A "$userName""@""$masterIP" /bin/bash << EOF
    sudo sh -c "echo '/home/'$userName'/OpenFOAM *(rw,sync,no_subtree_check)' >> /etc/exports"
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

# get instances IDs from this case to allow termination via Master
instancesIDs=$(aws ec2 describe-instances --filter Name=tag:$tag,Values=$caseName Name="instance-state-name",Values="running" --query 'Reservations[*].Instances[*].[InstanceId]' --output text | tr '\n' ' ')

# run script
nohup ssh -A "$userName""@""$masterIP" /bin/bash << EOF &
     # run openFoam connected script:
     source "$remoteOFScript" $numberOfNodes $listOfIPs &
     # get OpenFoam script PID
     OFPID=\$(echo \$!)
     # wait for a program to finish
     wait $OFPID
     printf "OpenFOAM script finished\n"
     aws s3 cp --recursive "\$FOAM_RUN" s3://"$S3BucketFolder"
     echo $instancesIDs
     aws ec2 terminate-instances --region eu-central-1 --instance-ids $instancesIDs
EOF

aws ec2 revoke-security-group-ingress --group-name "$securityGroupName" --protocol tcp --port 22 --cidr ${myip}/32
