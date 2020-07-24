
# in this script we receive
	# a group of disk donors
	# a group of disk receivers
	# the threshold
	# security margin


# Testing purposes

# get total in megabytes
total=$(($(df -m /dev/tpsecu/third | awk 'FNR == 2{print $4}')+$(df -m /dev/tpsecu/third | awk 'FNR == 2{print $3}')))
# displaying arguments DEBUG purposes

arguments=$@

# Variable initialization and defaults

	# Argument defaults
	threshold=90
	security_margin=5
	donors=""
	receivers=""
	vg_name=""

	# argument prefixes
	argthreshold='--threshold='
	argsecurity_margin='--security_margin='
	argdonors='--donors='
	argreceivers='--receivers='
	argvg_name='--vgname='

	# Variables
	crisis=0

# Argument Handling
for argument in "$@"
do
	# the threshold argument
	if [[ $argument == "$argthreshold"* ]]
	then
		threshold=$(echo "$argument" | awk -F "=" '{print $2}' | cut -d'%' -f 1)
	fi

	# the security margin
	if [[ $argument == "$argsecurity_margin"* ]]
	then
		security_margin=$(echo "$argument" | awk -F "=" '{print $2}' | cut -d'%' -f 1)
	fi

	# the donors list
	if [[ $argument == "$argdonors"* ]]
	then
		donors=$(echo "$argument" | awk -F "=" '{print $2}' | sed 's/,/ /g')
	fi

	# the donors list
	if [[ $argument == "$argreceivers"* ]]
	then
		receivers=$(echo "$argument" | awk -F "=" '{print $2}' | sed 's/,/ /g')
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

# Start

# we verify if we are in crisis mode by checking if we have enough space without making other volumes go beyond the threshold

	# first we calculate the needed space (including security margin, assuming out of crisis mode)
	needed=0
	needed_crisis=0

	for volume in $receivers
	do
		use=$(df -m $volume| awk 'FNR == 2{print $5}'| cut -d'%' -f 1);
		let total=$(df -m $volume| awk 'FNR == 2{print $4}')+$(df -m $volume| awk 'FNR == 2{print $3}')
		# let required=use-threshold+security_margin
		let needed+=(use - threshold+security_margin)*total/100
		let needed_crisis+=(use - threshold)*total/100
	done
	echo "needed space (crisis mode: off): $needed mb";

	# second we calculate the available space and see if we require additional space 
	
	# we get the free space from the specified volume group
	vgfree=$(vgdisplay $vg_name | grep Free | sed 's/,/ /g' | awk '{print $7}')
	
	# if the free space in the specified volume group is enough, we allcate it and exit
	if [ $vgfree -gt $needed ]
	then
		echo "Volume group has necessary memory needs, allocating to"
		for $volume in $receivers
		do
			use=$(df -m $volume| awk 'FNR == 2{print $5}'| cut -d'%' -f 1);
			let total=$(df -m $volume| awk 'FNR == 2{print $4}')+$(df -m $volume| awk 'FNR == 2{print $3}')

			let volume_needed=(use - threshold+security_margin)*total/100

			echo $volume
			lvextend -L +${volume_needed}M $volume
			exit 0
		done
	fi

	# we calculate available space in donors volumes
	available=0
	available_crisis=0
	available_crisis_two=0
	for volume in $donors
	do
		use=$(df -m $volume| awk 'FNR == 2{print $5}'| cut -d'%' -f 1);
		let total=$(df -m $volume| awk 'FNR == 2{print $4}')+$(df -m $volume| awk 'FNR == 2{print $3}')

		# global available space while taking account of the security margin Below threshold (No Crisis)
		let available+=(threshold - use - security_margin)*total/100
		# global available space considering the threshold only (no security margin) (Crisis 1)
		let available_crisis+=(threshold - use)*total/100
		# global available space considering nothing but available space (no threshold or security margin) (Crisis 2)
		let available_crisis_two+=(100-use)*total/100
	done

	# if there's free space in the volume group we count it as available
		if [ $vgfree -gt 0 ]
		then
			# we add that available space to the free space in volume group
			let total_available=available+vgfree
			let total_available_crisis=available_crisis+vgfree
			let total_available_crisis_two=available_crisis_two+vgfree
		else
			total_available=$available
			total_available_crisis=$available_crisis
			total_available_crisis_two=$available_crisis_two
		fi

	if [ $total_available -gt $needed ]
	then

		# no crisis mode
		echo "no crisis mode"

		echo "available space (crisis mode: off):"
		echo -e "\tVolume group: ${vgfree} mb"
		echo -e "\tDonors: ${available} mb"
		echo -e "\tTOTAL: ${total_available} mb"

		# for each volume in donors we will remove the necessary space
		for volume in $donors
		do
			use=$(df -m $volume| awk 'FNR == 2{print $5}'| cut -d'%' -f 1);
			let total=$(df -m $volume| awk 'FNR == 2{print $4}')+$(df -m $volume| awk 'FNR == 2{print $3}')

			let free=(threshold - use - security_margin)*total/100
			# echo "free=$free;available=$available;needed=$needed"
			removed=$(awk "BEGIN {removed=($free/$available)*($needed-$vgfree); print removed}")
			echo "$volume will offer ${removed} mb"
			lvreduce -L ${removed}M $volume

		done

		# for each volume in receivers we will add the needed space
		for volume in $receivers
		do
			use=$(df -m $volume| awk 'FNR == 2{print $5}'| cut -d'%' -f 1);
			let total=$(df -m $volume| awk 'FNR == 2{print $4}')+$(df -m $volume| awk 'FNR == 2{print $3}')

			let volume_needed=(use - threshold+security_margin)*total/100
			echo "the volume $volume will receive $needed mb"

			lvextend -L +${volume_needed}M $volume

		done
		exit 0
	else
		# crisis mode

		if [ $total_available_crisis -gt $needed_crisis ]
		then
			# we're in crisis mode 1 (we can still maintain the threshold, but we've crossed the security margin)

			# if there's free space in the volume group we count it as available
			if [ $vgfree -gt 0 ]
			then
				# we add that available space to the free space in volume group
				let total_available=available_crisis+vgfree
			else
				total_available=$available_crisis
			fi
			echo "crisis mode 1"
			
			echo "available space (crisis mode: off):"
			echo -e "\tVolume group: ${vgfree} mb"
			echo -e "\tDonors: ${available_crisis} mb"
			echo -e "\tTOTAL: ${total_available} mb"
			
			# for each volume in donors we will remove the necessary space
			for volume in $donors
			do
				use=$(df -m $volume| awk 'FNR == 2{print $5}'| cut -d'%' -f 1);
				let total=$(df -m $volume| awk 'FNR == 2{print $4}')+$(df -m $volume| awk 'FNR == 2{print $3}')

				let free=(threshold - use)*total/100
				# echo "free=$free;available=$available;needed=$needed"
				removed=$(awk "BEGIN {removed=($free/$available)*($needed-$vgfree); print removed}")
				echo "$volume will offer ${removed} mb"
				lvreduce -L ${removed}M $volume
			done

			# for each volume in receivers we will add the needed space
			for volume in $receivers
			do
				use=$(df -m $volume| awk 'FNR == 2{print $5}'| cut -d'%' -f 1);
				let total=$(df -m $volume| awk 'FNR == 2{print $4}')+$(df -m $volume| awk 'FNR == 2{print $3}')

				let volume_needed=(use - threshold)*total/100
				echo "the volume $volume will receive $volume_needed mb"
	
				lvextend -L +${volume_needed}M $volume
			done

			exit 0
		else
			# we're in crisis mode 2 (we cannot maintain the threshold anymore)
			echo "crisis mode 2"
			# when we can't maintain the threshold, we need a unit of transfer, the minimum unit of transfer available
			# to do that we'll even out all the logical volumes each time, we'll balance the empty space
			all_volumes=lvdisplay $vg_name | grep "LV Path" | awk '{print $3}'
			list_all_volumes=($all_volumes)
			list_count=${#list_all_volumes[@]}

			# calculating true total space
			total_space_available=$vgfree
			for volume in $all_volumes
			do
				let total_space_available+=$(df -m $volume | awk 'FNR==2{print $4}')
			done

				required_each=$(awk "BEGIN {result=$total_space_available/$list_count; print result}")

			for volume in $all_volumes
			do
				free_space=$(df -m $volume | awk 'FNR == 2{print $4}')
				
				echo -e "free: $free_space\trequired: $required"
				# if the free space is bigger than the required (equally distributed)
				if [ $free_space -gt $required_each ]
				then
					let difference=free_space-required_each
					lvreduce -L ${difference}M $volume
				fi
			done

			for volume in $all_volumes
			do
				free_space=$(df -m $volume | awk 'FNR == 2{print $4}')
				
				echo -e "free: $free_space\trequired: $required"
				# if the free space is bigger than the required (equally distributed)
				if [ $required_each -gt $free_space ]
				then
					let difference=required_each-free_space
					extend -L ${difference}M $volume
				fi
			done
		fi
	fi
	

# echo $donors
# echo $receivers

# echo -e "Arguments:\n"
# echo $arguments

# for argument in "$@"
# do
# 	echo -e "$argument"
# done