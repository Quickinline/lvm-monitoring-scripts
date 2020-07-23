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
	security_margin=5
	vg_name=""
	
	# Argument prefixes
	argverbose='--verbose'
	argthreshold='--threshold='
	argsecurity_margin='--security_margin='
	argvg_name='--vgname='

# Argument Handling

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

	# threshold argument
	if [[ $argument == "$argthreshold"* ]];
	then threshold=$(echo "$argument" | awk -F "=" '{print $2}' | cut -d'%' -f 1); echo "threshold is set at $threshold"
	fi

	# security margin argument
	if [[ $argument == "$argsecurity_margin"* ]];
	then threshold=$(echo "$argument" | awk -F "=" '{print $2}' | cut -d'%' -f 1); echo "security margin is set at $security_margin"
	fi

	if [[ $argument == "$argvg_name"* ]];
	then
		# catch variable
		vg_name=$(echo "$argument" | awk -F "=" '{print $2}');
		# check if the volume group exists
		volume_groups=$(vgdisplay | grep "VG Name" | awk '{print $3}')
		exists=0
		for group in $volume_groups
		do
			if [ $group = $vg_name ]
			then
				exists=1
			fi
		done
		if [ $exists = 0 ]
		then echo "Volume Group not found, Aborting"; exit 0
		else echo "specified Volume Group: $vg_name"
		fi
	fi
done

# if volume group not specified, abort
if [ -z $vg_name ]
then echo -e "\nVolume Group not specified, Aborting"; exit 0
fi


# Start

# we acquire the list of logical volume paths
logical_volumes_paths=$(lvdisplay $vg_name |grep "LV Path" | awk '{print $3}')


echo -e "\nDetected Volumes for monitoring:"
echo -e "$logical_volumes_paths\n"

# while going though volumes, we need to set them apart as Receivers (of memory) and Donors
receivers=""
donors=""

# foeach volume, if it's usage is beyond the threshold it blongs to the receivers
# if it's below threshold it belongs to the donors
for volume in $logical_volumes_paths
do
	percentage=$(df $volume| awk 'FNR == 2{print $5}'| cut -d'%' -f 1)
	if [ "$percentage" -gt "$threshold" ]
		# Beyond threshold, we add it to the Receivers
		then
			receivers+="$volume,"

		# Under threshold
		else
			donors+="$volume,"
	fi
done
# remove comma suffixes (last comma appended)
donors=${donors%","}
receivers=${receivers%","}


echo -e "receivers: $receivers"
echo -e "donors: $donors\n"

bash $target_script --threshold=$threshold --security_margin=$security_margin --vgname=$vg_name --donors=$donors --receivers=$receivers

exit 0


		# 	if [ $verbose -eq 1 ]; then
		# 		echo -e "-the volume $volume usage is: $percentage% ,Beyond threshold\n\tExecuting target script: $target_script $volume"
		# 	fi
		# 	bash $target_script $volume $threshold


		# if [ $verbose -eq 1 ]; then
		# 	echo -e "the volume $volume usage is: $percentage below threshold not executing target script"
		# fi
