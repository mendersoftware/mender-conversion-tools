#!/bin/bash

show_help() {
cat << EOF

Mender conversion tool

A tool for taking an existing embedded image (Debian, Ubuntu, Raspbian, etc)
and convert it to a Mender image by restructuring partition table and adding
necessary files.

Usage: $0 COMMAND [options]

General commands:

        from-raw-disk-image                     - composes fully functional Mender
                                                  image compliant with Mender
                                                  partition layout, having all
                                                  necessary files installed
        mender-disk-image-to-artifact           - creates Mender artifact file
                                                  from Mender image

Expert commands:

        raw-disk-image-shrink-rootfs            - shrinks existing embedded raw
                                                  disk image
        raw-disk-image-create-partitions        - converts raw disk image's
                                                  partition table to be compliant
                                                  with Mender partition layout
        install-mender-to-mender-disk-image     - installs Mender client related
                                                  files
        install-bootloader-to-mender-disk-image - installs bootloader (U-Boot/GRUB)
                                                  related files

Options: [-r|--raw-disk-image | -m|--mender-disk-image | -s|--data-part-size-mb |
          -d|--device-type | -p|--rootfs-partition-id | -i|--demo-host-ip |
          -c| --server-cert | -u| --server-url | -t|--tenant-token |
          -g|--mender-client -b|--bootloader-toolchain | -a|--artifact-name |
          -k|--keep]

        raw-disk-image       - raw disk embedded Linux (Debian, Raspbian,
                               Ubuntu, etc.) image path
        mender-disk-image    - Mender disk image name where the script writes to
                               should have "sdimg" suffix
        data-part-size-mb    - data partition size in MB; default value 128MB
        device-type          - target device identification used to build
                               Mender image
        rootfs-partition-id  - selects root filesystem (rootfs_a|rootfs_b) as the
                               source filesystem for an artifact
        demo-host-ip         - server demo ip used for testing purposes
        server-cert          - server certificate file
        server-url           - production server url
        tenant-token         - Mender tenant token
        mender-client        - Mender client binary
        bootloader-toolchain - GNU Arm Embedded Toolchain
        artifact-name        - Mender artifact name
        keep                 - keep intermediate files in output directory

        Note: root filesystem size used in Mender image creation can be found as
              an output from 'raw-disk-image-shrink-rootfs' command or, in case
              of using unmodified embedded raw disk image, can be checked with
              any partition manipulation program (e.g. parted, fdisk, etc.).

Examples:

    To create fully functional Mender image from raw disk image in a single step:

        ./mender-convert.sh from-raw-disk-image
                --raw-disk-image <raw_disk_image_path>
                --mender-disk-image <mender_image_name>
                --device-type <beaglebone | raspberrypi3>
                --mender-client <mender_binary_path>
                --artifact-name release-1_1.5.0
                --bootloader-toolchain arm-linux-gnueabihf
                --demo-host-ip 192.168.10.2
                --keep

        Output: ready to use Mender image with Mender client and bootloader installed

    To create Mender artifact file from Mender image:

        ./mender-convert.sh mender-disk-image-to-artifact
                --mender-disk-image <mender_image_path>
                --device-type <beaglebone | raspberrypi3>
                --artifact-name release-1_1.5.0
                --rootfs-partition-id rootfs_a

        Note: artifact name format is: release-<release_no>_<mender_version>

Examples for expert actions:

    To shrink the existing embedded raw disk image:

        ./mender-convert.sh raw-disk-image-shrink-rootfs
                --raw-disk-image <raw_disk_image_path>

        Output: Root filesystem size (sectors): 4521984

    To convert raw disk image's partition table to Mender layout:

        ./mender-convert.sh raw-disk-image-create-partitions
                --raw-disk-image <raw_disk_image_path>
                --mender-disk-image <mender_image_name>
                --device-type <beaglebone | raspberrypi3>
                --data-part-size-mb 128

	Output: repartitioned (respectively to Mender layout) raw disk image

    To install Mender client related files:

        ./mender-convert.sh install-mender-to-mender-disk-image
                --mender-disk-image <mender_image_path>
                --device-type <beaglebone | raspberrypi3>
                --artifact-name release-1_1.5.0
                --demo-host-ip 192.168.10.2
                --mender-client <mender_binary_path>

        Output: Mender image with Mender client related files installed

    To install bootloader (U-Boot/GRUB) related files:

        ./mender-convert.sh install-bootloader-to-mender-disk-image
                --mender-disk-image <mender_image_path>
                --device-type <beaglebone | raspberrypi3>
                --bootloader-toolchain arm-linux-gnueabihf

        Output: Mender image with appropriate bootloader (U-Boot/GRUB) installed

EOF
}

if [ $# -eq 0 ]; then
  show_help
  exit 1
fi

tool_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Default sector size
sector_size=
# Boot partition start in sectors (512 bytes per sector).
pboot_start=
# Default 'boot' partition size in sectors: 16MB
# (i.e 16777216 bytes, equals to 'partition_alignment' * 2)
pboot_size=
# Default 'data' partition size in MiB.
data_part_size_mb=128
# Data partition size in sectors.
pdata_size=
# Exemplary values for Beaglebone: 9.3: 4521984 9.4: 4423680
prootfs_size=

mender_disk_image=
raw_disk_image=
device_type=
partitions_number=
artifact_name=
rootfs_partition_id=
image_type=
mender_client=
# Mender production certificate.
server_cert=
# Mender production server url.
server_url=
# Mender demo server IP address.
demo_host_ip=
# Mender hosted token.
tenant_token=

declare -a rootfs_partition_ids=("rootfs_a" "rootfs_b")
declare -a mender_disk_mappings
declare -a raw_disk_mappings

do_raw_disk_image_shrink_rootfs() {
  if [ -z "${raw_disk_image}" ]; then
    echo "Raw disk image not set. Aborting."
    exit 1
  fi

  local count=
  local bootstart=
  local bootsize=
  local rootfsstart=
  local rootfssize=
  local bootflag=

  # Gather information about raw disk image.
  get_image_info $raw_disk_image count sector_size bootstart bootsize \
          rootfsstart rootfssize bootflag

  # Find first available loopback device.
  loopdevice=($(losetup -f))

  # Mount appropriate partition.
  if [[ $count -eq 1 ]]; then
    sudo losetup $loopdevice $raw_disk_image -o $(($bootstart * $sector_size))
  elif [[ $count -eq 2 ]]; then
    sudo losetup $loopdevice $raw_disk_image -o $(($rootfsstart * $sector_size))
  else
    echo "Error: invalid/unsupported embedded raw disk image. Aborting."
    exit 1
  fi

  [ $? -ne 0 ] && { echo "Error: inaccesible loopback device"; exit 1; }

  block_size=($(sudo dumpe2fs -h $loopdevice | grep 'Block size' | tr -s ' ' | cut -d ' ' -f3))
  min_size_blocks=($(sudo resize2fs -P $loopdevice | awk '{print $NF}'))

  new_size_sectors=$(( $min_size_blocks * $block_size / $sector_size ))
  align_partition_size new_size_sectors $sector_size

  echo -e "Root filesystem size:"
  echo -e "\nminimal: $(( $min_size_blocks * $block_size ))"
  echo -e "\naligned: $(( $new_size_sectors * $sector_size ))"
  echo -e "\nsectors: $new_size_sectors"

  sudo e2fsck -y -f $loopdevice
  sudo resize2fs -p $loopdevice ${new_size_sectors}s
  sudo e2fsck -y -f $loopdevice

  sudo losetup -d $loopdevice
  sudo losetup $loopdevice $raw_disk_image

  if [[ $count -eq 1 ]]; then
    create_single_disk_partition_table $loopdevice $bootstart $new_size_sectors
  elif [[ $count -eq 2 ]]; then
    echo
    create_double_disk_partition_table $loopdevice $rootfsstart $new_size_sectors
  fi

  sudo partprobe
  endsector=($(sudo parted $loopdevice -ms unit s print | grep "^$count" | cut -f3 -d: | sed 's/[^0-9]*//g'))

  sudo losetup -d $loopdevice
  echo "Image new endsector: $endsector"
  truncate -s $((($endsector+1) * $sector_size)) $raw_disk_image
  echo "Root filesystem size (sectors): $new_size_sectors"
}

do_raw_disk_image_create_partitions() {
  if [ -z "${raw_disk_image}" ]; then
    echo "Raw disk image not set. Aborting."
    exit 1
  fi

  if [ -z "${device_type}" ]; then
    echo "Target device type name not set. Aborting."
    exit 1
  fi

  if [[ ! -f ${raw_disk_image} ]]; then
    echo "Raw disk image not found. Aborting."
    exit 1
  fi

  mkdir -p $output_dir && cd $output_dir

  # In case of missing .sdimg name use the default format.
  [ -z $mender_disk_image ] && mender_disk_image=$output_dir/mender_${device_type}.sdimg \
                            || mender_disk_image=$output_dir/$mender_disk_image

  analyse_raw_disk_image ${raw_disk_image} pboot_start pboot_size prootfs_size \
                         sector_size image_type

  [ -z "${prootfs_size}" ] && \
    { echo "root filesystem size not set. Aborting."; exit 1; }

  local mender_disk_image_size=
  calculate_mender_disk_size $pboot_start $pboot_size  \
                             $prootfs_size $data_part_size_mb  \
                             $sector_size pdata_size mender_disk_image_size

  echo -e "Creating Mender disk image:\
           \nimage size: ${mender_disk_image_size} bytes\
           \nroot filesystem size: ${prootfs_size} sectors\
           \ndata partition size: $pdata_size sectors\n"

  create_test_config_file $device_type $partition_alignment $vfat_storage_offset \
                          $pboot_size $prootfs_size $pdata_size $mender_disk_image_size \
                          $sector_size

  create_mender_disk $mender_disk_image $mender_disk_image_size
  format_mender_disk $mender_disk_image $mender_disk_image_size $pboot_start \
                     $pboot_size $prootfs_size $pdata_size $sector_size
  verify_mender_disk $mender_disk_image partitions_number

  create_device_maps $mender_disk_image mender_disk_mappings
  make_mender_disk_filesystem ${mender_disk_mappings[@]}

  case "$device_type" in
    "beaglebone")
      do_make_sdimg_beaglebone
      ;;
    "raspberrypi3")
      do_make_sdimg_raspberrypi3
      ;;
  esac

  rc=$?

  echo -e "\nCleaning..."
  # Clean and detach.
  detach_device_maps ${mender_disk_mappings[@]}
  detach_device_maps ${raw_disk_mappings[@]}
  sync
  rm -rf $embedded_base_dir
  rm -rf $sdimg_base_dir

  [ $rc -eq 0 ] && { echo -e "\n$mender_disk_image image created."; } \
                || { echo -e "\n$mender_disk_image image composing failure."; }
}

do_make_sdimg_beaglebone() {
  local ret=0

  create_device_maps $raw_disk_image raw_disk_mappings

  mount_mender_disk ${mender_disk_mappings[@]}
  mount_raw_disk ${raw_disk_mappings[@]}

  echo -e "\nSetting boot partition..."
  stage_2_args="$sdimg_boot_dir $embedded_rootfs_dir"
  ${tool_dir}/bbb-convert-stage-2.sh ${stage_2_args} || ret=$?
  [[ $ret -ne 0 ]] && { echo "Aborting."; return $ret; }

  echo -e "\nSetting root filesystem..."
  stage_3_args="$sdimg_primary_dir $embedded_rootfs_dir"
  ${tool_dir}/bbb-convert-stage-3.sh ${stage_3_args} || ret=$?
  [[ $ret -ne 0 ]] && { echo "Aborting."; return $ret; }

  set_fstab $device_type

  return $ret
}

do_make_sdimg_raspberrypi3() {
  image_boot_part=$(fdisk -l ${raw_disk_image} | grep FAT32)

  boot_part_start=$(echo ${image_boot_part} | awk '{print $2}')
  boot_part_end=$(echo ${image_boot_part} | awk '{print $3}')
  boot_part_size=$(echo ${image_boot_part} | awk '{print $4}')

  extract_file_from_image ${raw_disk_image} ${boot_part_start} \
                          ${boot_part_size} "boot.vfat"

  image_rootfs_part=$(fdisk -l ${raw_disk_image} | grep Linux)

  rootfs_part_start=$(echo ${image_rootfs_part} | awk '{print $2}')
  rootfs_part_end=$(echo ${image_rootfs_part} | awk '{print $3}')
  rootfs_part_size=$(echo ${image_rootfs_part} | awk '{print $4}')

  extract_file_from_image ${raw_disk_image} ${rootfs_part_start} \
                          ${rootfs_part_size} "rootfs.img"

  echo -e "\nSetting boot partition..."
  stage_2_args="$output_dir ${mender_disk_mappings[0]}"
  ${tool_dir}/rpi3-convert-stage-2.sh ${stage_2_args} || ret=$?
  [[ $ret -ne 0 ]] && { echo "Aborting."; return $ret; }

  echo -e "\nSetting root filesystem..."
  stage_3_args="$output_dir ${mender_disk_mappings[1]}"
  ${tool_dir}/rpi3-convert-stage-3.sh ${stage_3_args} || ret=$?
  [[ $ret -ne 0 ]] && { echo "Aborting."; return $ret; }

  mount_mender_disk ${mender_disk_mappings[@]}

  # Add mountpoints.
  sudo install -d -m 755 ${sdimg_primary_dir}/uboot
  sudo install -d -m 755 ${sdimg_primary_dir}/data

  set_fstab $device_type
}

do_install_mender_to_mender_disk_image() {
  # Mender executables, service and configuration files installer.
  if [ -z "$mender_disk_image" ] || [ -z "$device_type" ] || [ -z "$mender_client" ] || \
     [ -z "$artifact_name" ]; then
    show_help
    exit 1
  fi
  # mender-image-1.5.0
  stage_4_args="-m $mender_disk_image -d $device_type -g ${mender_client} -a ${artifact_name}"

  if [ -n "$demo_host_ip" ]; then
    stage_4_args="${stage_4_args} -i ${demo_host_ip}"
  fi

  if [ -n "$server_cert" ]; then
    stage_4_args="${stage_4_args} -c ${server_cert}"
  fi

  if [ -n "$server_url" ]; then
    stage_4_args="${stage_4_args} -u ${server_url}"
  fi

  if [ -n "${tenant_token}" ]; then
    stage_4_args="${stage_4_args} -t ${tenant_token}"
  fi

  eval set -- " ${stage_4_args}"

  export -f create_device_maps
  export -f detach_device_maps

  ${tool_dir}/convert-stage-4.sh ${stage_4_args}

  # Update test configuration file
  update_test_config_file $device_type artifact-name $artifact_name
}

do_install_bootloader_to_mender_disk_image() {
  if [ -z "$mender_disk_image" ] || [ -z "$device_type" ] || \
     [ -z "$bootloader_toolchain" ]; then
    show_help
    exit 1
  fi

  case "$device_type" in
    "beaglebone")
      stage_5_args="-m $mender_disk_image -d $device_type -b ${bootloader_toolchain} $keep"
      eval set -- " ${stage_5_args}"
      export -f create_device_maps
      export -f detach_device_maps
      ${tool_dir}/bbb-convert-stage-5.sh ${stage_5_args}

      # Update test configuration file
      update_test_config_file $device_type distro-feature "mender-grub" \
                                           mount-location "\/boot\/efi"
      ;;
    "raspberrypi3")
      stage_5_args="-m $mender_disk_image -d $device_type -b ${bootloader_toolchain} $keep"
      eval set -- " ${stage_5_args}"
      export -f create_device_maps
      export -f detach_device_maps
      export -f mount_mender_disk
      ${tool_dir}/rpi3-convert-stage-5.sh ${stage_5_args}

      # Update test configuration file
      update_test_config_file $device_type mount-location "\/uboot"
      ;;
  esac
}

do_mender_disk_image_to_artifact() {
  if [ -z "${mender_disk_image}" ]; then
    echo "Mender disk image not set. Aborting."
    exit 1
  fi

  if [ -z "${device_type}" ]; then
    echo "Target device_type name not set. Aborting."
    exit 1
  fi

  if [ -z "${artifact_name}" ]; then
    echo "Artifact name not set. Aborting."
    exit 1
  fi

  if [ -z "${rootfs_partition_id}" ]; then
    echo "Rootfs partition id not set - rootfs_a will be used by default."
    rootfs_partition_id="rootfs_a"
  fi

  inarray=$(echo ${rootfs_partition_ids[@]} | grep -o $rootfs_partition_id | wc -w)

  [[ $inarray -eq 0 ]] && \
      { echo "Error: invalid rootfs type provided. Aborting."; exit 1; }

  local count=
  local bootstart=
  local rootfs_a_start=
  local rootfs_a_size=
  local rootfs_b_start=
  local rootfs_b_size=
  local rootfs_path=
  local sdimg_device_type=
  local abort=0

  get_mender_disk_info $mender_disk_image count sector_size rootfs_a_start \
                       rootfs_a_size rootfs_b_start rootfs_b_size
  ret=$?
  [[ $ret -ne 0 ]] && \
      { echo "Error: cannot validate Mender disk image. Aborting."; exit 1; }

  create_device_maps $mender_disk_image mender_disk_mappings
  mount_mender_disk ${mender_disk_mappings[@]}

  if [[ $rootfs_partition_id == "rootfs_a" ]]; then
    prootfs_size=$rootfs_a_size
    rootfs_path=$sdimg_primary_dir
  elif [[ $rootfs_partition_id == "rootfs_b" ]]; then
    prootfs_size=$rootfs_b_size
    rootfs_path=$sdimg_secondary_dir
  fi

  # Find .sdimg file's dedicated device type.
  sdimg_device_type=$( cat $sdimg_data_dir/mender/device_type | sed 's/[^=].*=//' )

  # Set 'artifact name' as passed in the command line.
  sudo sed -i '/^artifact/s/=.*$/='${artifact_name}'/' "$rootfs_path/etc/mender/artifact_info"

  if [ "$sdimg_device_type" != "$device_type" ]; then
    echo "Error: .mender and .sdimg device type not matching. Aborting."
    abort=1
  fi

  if [[ $(which mender-artifact) = 1 ]]; then
    echo "Error: mender-artifact not found in PATH. Aborting."
    abort=1
  fi

  if [ $abort -eq 0 ]; then
    local rootfs_file=${output_dir}/rootfs.ext4

    echo "Creating a ext4 file-system image from modified root file-system"
    dd if=/dev/zero of=$rootfs_file seek=${prootfs_size} count=0 bs=512 status=none

    sudo mkfs.ext4 -FF $rootfs_file -d $rootfs_path

    fsck.ext4 -fp $rootfs_file

    mender_artifact=${output_dir}/${device_type}_${artifact_name}.mender
    echo "Writing Mender artifact to: ${mender_artifact}"

    #Create Mender artifact
    mender-artifact write rootfs-image \
      --update ${rootfs_file} \
      --output-path ${mender_artifact} \
      --artifact-name ${artifact_name} \
      --device-type ${device_type}

    ret=$?
    [[ $ret -eq 0 ]] && \
      { echo "Writing Mender artifact to ${mender_artifact} succeeded."; } || \
      { echo "Writing Mender artifact to ${mender_artifact} failed."; }

    rm $rootfs_file
  fi

  # Clean and detach.
  detach_device_maps ${mender_disk_mappings[@]}

  rm -rf $sdimg_base_dir
}

do_from_raw_disk_image() {
  do_raw_disk_image_create_partitions
  do_install_mender_to_mender_disk_image
  do_install_bootloader_to_mender_disk_image
}

#read -s -p "Enter password for sudo: " sudoPW
#echo ""

PARAMS=""

# Load necessary functions.
source ${tool_dir}/mender-convert-functions.sh

while (( "$#" )); do
  case "$1" in
    -p | --rootfs-partition-id)
      rootfs_partition_id=$2
      shift 2
      ;;
    -m | --mender-disk-image)
      mender_disk_image=$2
      shift 2
      ;;
    -r | --raw-disk-image)
      raw_disk_image=$(get_path $2)
      shift 2
      ;;
    -s | --data-part-size-mb)
      data_part_size_mb=$2
      shift 2
      ;;
    -d | --device-type)
      device_type=$2
      shift 2
      ;;
    -a | --artifact-name)
      artifact_name=$2
      shift 2
      ;;
    -g | --mender-client)
      mender_client=$(get_path $2)
      shift 2
      ;;
    -b | --bootloader-toolchain)
      bootloader_toolchain=$2
      shift 2
      ;;
    -i | --demo-host-ip)
      demo_host_ip=$2
      shift 2
      ;;
    -c | --server-cert)
      server_cert=$2
      shift 2
      ;;
    -u | --server-url)
      server_url=$2
      shift 2
      ;;
    -t | --tenant-token)
      tenant_token=$2
      shift 2
      ;;
    -k | --keep)
      keep="-k"
      shift 1
      ;;
    -h | --help)
      show_help
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -*)
      echo "Error: unsupported option $1" >&2
      exit 1
      ;;
    *)
      PARAMS="$PARAMS $1"
      shift
      ;;
  esac
done

[ -z "${data_part_size_mb}" ] && \
    { echo "Default 'data' partition size set to 128MB"; data_part_size_mb=128; }

eval set -- "$PARAMS"

# Some commands expect elevated privileges.
sudo true

case "$1" in
  raw-disk-image-shrink-rootfs)
    do_raw_disk_image_shrink_rootfs
    ;;
  raw-disk-image-create-partitions)
    do_raw_disk_image_create_partitions
    ;;
  install-mender-to-mender-disk-image)
    do_install_mender_to_mender_disk_image
    ;;
  install-bootloader-to-mender-disk-image)
    do_install_bootloader_to_mender_disk_image
    ;;
  mender-disk-image-to-artifact)
    do_mender_disk_image_to_artifact
    ;;
  from-raw-disk-image)
    do_from_raw_disk_image
    ;;
  *)
    show_help
    ;;
esac

