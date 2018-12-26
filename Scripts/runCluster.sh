# define names and paths:
masterName="master"
slaveName="slave"
sshKey="~/.ssh/tutorial-key.pem"
sshKeyName="tutorial-key"
masterCliSkeleton="~/Documents/AWS/Scripts/templateMaster.json"
slaveCliSkeleton="~/Documents/AWS/Scripts/templateSlave.json"
userName="ubuntu"
numberOfCores=4 # how many cores for each node
numberOfNodes=4 # how many nodes (including master)
openFoamScript="/home/greg/OpenFOAM/greg-v1712/AWS/OFAWS.sh"
placementGroupName="ClusterCFD"
securityGroupName=""

# check if paths are ok (if files exist and are readable)
if [ ! -r $sshKey) ] ; then
     printf "sshKey does not exist: %s\n" "$sshKey"
     exit
fi
if [ ! -r $masterCliSkeleton) ] ; then
     printf "Master CLI Skeleton does not exist: %s\n" "$masterCliSkeleton"
     exit
fi
if [ ! -r $slaveCliSkeleton) ] ; then
     printf "Slave CLI Skeleton does not exist: %s\n" "$slaveCliSkeleton"
     exit
fi
if [ ! -r $openFoamScript) ] ; then
     printf "OpenFOAM script does not exist: %s\n" "$openFoamScript"
     exit
fi

# create placement group
# check if placement group already exists
if [[ $(aws ec2 describe-placement-groups --output text | sed 's/PLACEMENTGROUPS\t//' | sed 's/\t.*//' | grep -w $placementGroupName -c) -eq 0 ]] ; then
# if does not exist, create placement group:
    aws ec2 create-placement-group --group-name $placementGroupName --strategy cluster
fi

!!!!
create temporary template
edit template to change placement group and core number etc

# check if security group exists, if not, create one:
if [[ <sprawdź istniejące grupy bezpieczeństwa> | grep $securityGroupName == <co zwraca grep jak pusto> ]] ; then
    #definition of security group
fi


# sed 


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
