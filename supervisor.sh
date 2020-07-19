#!/bin/bash
# this is a script meant for monitoring Logical Volumes,
# when a volume reaches a threshold, it calls another script on that volume and makes an alert

# Cheat Sheet:
	# init physical volume: pvcreate $(disk path)
	# Create Volume Group(s): vgcreate $(volume group name) $(disks list)
	# Create Logical volume: lvcreate -n $(volume name) -L $(volume size) $(volume group name)

	# Format partition: mkfs -t ext4 $(disk path)

	# fill a file with random data (1mb count=twice): dd if=/dev/urandom of=a.log bs=1M count=2
	# select third column from standard input with default delimiter (space): awk '{print $3}'

# Variables initializations and Defaults
	# Argument initialisation
	verbose=0
	target_script=""
	threshold=90

# Arguments Handling
	
	# Argument Values
	argverbose='--verbose'
	argthreshold='--threshold='

for argument in "$@"
do
	# if verbose argument exists make verbose 1
	if [ $argument = "$argverbose" ];
	then	verbose=1
	fi
	
	# if the argument is a file (target script)
	if [ -f "$argument" ]
	then	target_script=$argument
	fi

	if [[ $argument == "$argthreshold"* ]];
	then threshold=$(echo "$argument" | awk -F "=" '{print $2}' | cut -d'%' -f 1); echo "threshold is set at $threshold"
	fi
done

# Start

# we acquire the list of logical volume paths
logical_volumes_paths=$(lvdisplay |grep "LV Path" | awk '{print $3}')


echo -e "\nDetected Volumes for monitoring:"
echo -e "$logical_volumes_paths\n"


for volume in $logical_volumes_paths
do
	percentage=$(df $volume| awk 'FNR == 2{print $5}'| cut -d'%' -f 1)
	if [ "$percentage" -gt "$threshold" ]
		# Beyond threshold
		then
			if [ $verbose -eq 1 ]; then
				echo -e "-the volume $volume usage is: $percentage% ,Beyond threshold\n\tExecuting target script: $target_script $volume"
			fi
			bash $target_script $volume $threshold
		# Under threshold
		else
			if [ $verbose -eq 1 ]; then
				echo -e "the volume $volume usage is: $percentage below threshold not executing target script"
			fi
	fi
done

exit 0