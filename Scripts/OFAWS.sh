#!/bin/bash

numberOfNodes=$1
ipList=$2
numberOfCores=$(nproc)
((numberOfProcesses = $numberOfCores * $numberOfNodes))

# preparing tutorial case
cd $FOAM_RUN
cp -r $FOAM_TUTORIALS/multiphase/interFoam/laminar/damBreak/damBreak .
cd damBreak
blockMesh
refineMesh -overwrite
cp -r 0/alpha.water.orig 0/alpha.water
setFields
# copy ips files
cp $ipList ./machines
# edit decomposition parameters
sed -i 's/numberOfSubdomains 4;/numberOfSubdomains '$numberOfProcesses';/' ./system/decomposeParDict
sed -i 's/(2 2 1)/('$numberOfNodes' '$numberOfCores' 1)/' ./system/decomposeParDict
decomposePar

printf "\n\n\n\n\n\n"
ls 
printf "\n\n\n\n\n\n"

foamJob -p -w interFoam

# construct log files in user-friendly form
foamLog ./log

# reconstruct results
reconstructPar

# remove unnecessary files
rm -r processor*

# exit script
exit 1
