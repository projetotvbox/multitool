#!/bin/bash

function round_sectors() {

	SECTORS="$1"

	ROUNDED=$(((($SECTORS / 8) + 1) * 8))

	echo $ROUNDED

}

BACKTITLE="TUI Multitool Image Builder"

FINAL_MESSAGE=""
RUN_START_EPOCH="$(date +%s)"
LOGS_DIR=""
LOG_FILE=""
CURRENT_STAGE="startup"
LAST_CMD_STATUS=""
LAST_CMD_TEXT=""

#------------------------------------------------------------------------------
# Function: show_error
# Description: Shows a blocking error dialog, logs the error context, and exits.
# Parameters: $1=error_message, $2=optional_status_code_for_log
# Author: Pedro Rigolin
#------------------------------------------------------------------------------
function show_error() {

    local explicit_status="$2"
    local status_to_log="${explicit_status:-${LAST_CMD_STATUS:-$?}}"
    log_error "$1" "$status_to_log"

    dialog \
        --backtitle "$BACKTITLE" \
        --title "Error" \
        --ok-label "Exit" \
        --msgbox "\n$1" 8 50

    exit 1

}

#------------------------------------------------------------------------------
# Function: show_wait
# Description: Updates current stage and shows a non-blocking progress dialog.
# Parameters: $1=stage_or_progress_message
# Author: Pedro Rigolin
#------------------------------------------------------------------------------
function show_wait(){

    log_stage "$1"

    dialog \
        --backtitle "$BACKTITLE" \
        --title "Please wait" \
        --infobox "\n$1" 8 50

}

#------------------------------------------------------------------------------
# Function: show_info
# Description: Shows an informational blocking dialog requiring user acknowledgment.
# Parameters: $1=information_message
# Author: Pedro Rigolin
#------------------------------------------------------------------------------
function show_info() {

    dialog \
        --backtitle "$BACKTITLE" \
        --title "Info" \
        --ok-label "OK" \
        --msgbox "\n$1" 8 50

}

#------------------------------------------------------------------------------
# Function: show_warning
# Description: Shows a warning dialog for non-fatal events.
# Parameters: $1=warning_message
# Author: Pedro Rigolin
#------------------------------------------------------------------------------
function show_warning() {

    dialog \
        --backtitle "$BACKTITLE" \
        --title "Warning" \
        --ok-label "OK" \
        --msgbox "\n$1" 8 50

}

#------------------------------------------------------------------------------
# Function: log_write
# Description: Writes a timestamped structured line to LOG_FILE when available.
# Parameters: $1=level, $2=message
# Author: Pedro Rigolin
#------------------------------------------------------------------------------
function log_write() {

    local level="$1"
    local message="$2"

    if [ -z "$LOG_FILE" ]; then
        return 0
    fi

    printf "%s [%s] %s\n" "$(date "+%Y-%m-%d %H:%M:%S")" "$level" "$message" >> "$LOG_FILE" 2>/dev/null

}

#------------------------------------------------------------------------------
# Function: log_stage
# Description: Updates CURRENT_STAGE and logs a stage transition.
# Parameters: $1=stage_name
# Author: Pedro Rigolin
#------------------------------------------------------------------------------
function log_stage() {

    CURRENT_STAGE="$1"
    log_write "INFO" "stage: $1"

}

#------------------------------------------------------------------------------
# Function: log_error
# Description: Logs an error entry bound to CURRENT_STAGE and status code.
# Parameters: $1=error_message, $2=optional_status_code
# Author: Pedro Rigolin
#------------------------------------------------------------------------------
function log_error() {

    local message="$1"
    local status_code="$2"

    log_write "ERROR" "stage: $CURRENT_STAGE | status: ${status_code:-unknown} | message: $message"

}

#------------------------------------------------------------------------------
# Function: log_vars
# Description: Logs scoped variable snapshots for debugging and traceability.
# Parameters: $1=scope, $2..$n=details_key_value_pairs
# Author: Pedro Rigolin
#------------------------------------------------------------------------------
function log_vars() {

    local scope="$1"
    shift

    local details="$*"
    log_write "VARS" "$scope | $details"

}

#------------------------------------------------------------------------------
# Function: run_logged
# Description: Executes command with logging of text, output markers, and exit.
# Parameters: $@=command_and_arguments
# Returns: command_exit_status
# Author: Pedro Rigolin
#------------------------------------------------------------------------------
function run_logged() {

    local status

    log_write "CMD" "$*"
    LAST_CMD_TEXT="$*"

    if [ -n "$LOG_FILE" ]; then
        log_write "CMD_OUT_START" "$*"
        "$@" >> "$LOG_FILE" 2>&1
        log_write "CMD_OUT_END" "$*"
    else
        "$@" >/dev/null 2>&1
    fi

    status=$?
    LAST_CMD_STATUS="$status"
    log_write "CMD_RET" "exit=$status :: $*"

    return $status

}

#------------------------------------------------------------------------------
# Function: run_logged_capture
# Description: Executes command, captures stdout in a variable, and logs status.
# Parameters: $1=destination_var_name, $2..$n=command_and_arguments
# Returns: command_exit_status
# Author: Pedro Rigolin
#------------------------------------------------------------------------------
function run_logged_capture() {

    local output_var="$1"
    shift

    local output
    local status

    log_write "CMD" "$*"
    LAST_CMD_TEXT="$*"

    if [ -n "$LOG_FILE" ]; then
        output="$("$@" 2>> "$LOG_FILE")"
    else
        output="$("$@" 2>/dev/null)"
    fi

    status=$?
    LAST_CMD_STATUS="$status"
    log_write "CMD_RET" "exit=$status :: $*"

    if [ -n "$output" ]; then
        log_write "RAW_CAPTURE" "$output"
    fi

    printf -v "$output_var" '%s' "$output"

    return $status

}

#------------------------------------------------------------------------------
# Function: run_logged_to_file
# Description: Executes command with stdout redirected to file and full logging.
# Parameters: $1=destination_file, $2..$n=command_and_arguments
# Returns: command_exit_status
# Author: Pedro Rigolin
#------------------------------------------------------------------------------
function run_logged_to_file() {

    local dest_file="$1"
    shift

    local status

    log_write "CMD" "$* > $dest_file"
    LAST_CMD_TEXT="$* > $dest_file"

    if [ -n "$LOG_FILE" ]; then
        log_write "CMD_OUT_START" "$* > $dest_file"
        "$@" > "$dest_file" 2>> "$LOG_FILE"
        log_write "CMD_OUT_END" "$* > $dest_file"
    else
        "$@" > "$dest_file" 2>/dev/null
    fi

    status=$?
    LAST_CMD_STATUS="$status"
    log_write "CMD_RET" "exit=$status :: $* > $dest_file"

    return $status

}

#------------------------------------------------------------------------------
# Function: rotate_logs
# Description: Keeps the 10 newest build logs and removes older log files.
# Author: Pedro Rigolin
#------------------------------------------------------------------------------
function rotate_logs() {

    local files=()

    if [ ! -d "$LOGS_DIR" ]; then
        return 0
    fi

    mapfile -t files < <(ls -1t "$LOGS_DIR"/build-*.log 2>/dev/null)

    if [ "${#files[@]}" -le 10 ]; then
        return 0
    fi

    for old_log in "${files[@]:10}"; do
        rm -f "$old_log" >/dev/null 2>&1
    done

}

#------------------------------------------------------------------------------
# Function: init_logs
# Description: Initializes log directory/file and applies log retention policy.
# Returns: 0=success, 1=initialization_failure
# Author: Pedro Rigolin
#------------------------------------------------------------------------------
function init_logs() {

    local run_timestamp

    mkdir -p "$LOGS_DIR" >/dev/null 2>&1

    if [ $? -ne 0 ]; then
        return 1
    fi

    run_timestamp="$(date "+%Y%m%d-%H%M%S")"
    LOG_FILE="$LOGS_DIR/build-${run_timestamp}-unknown.log"

    touch "$LOG_FILE" >/dev/null 2>&1

    if [ $? -ne 0 ]; then
        return 1
    fi

    rotate_logs

    log_write "INFO" "build started"
    log_write "INFO" "cwd: $CWD"

    return 0

}

#------------------------------------------------------------------------------
# Function: log_summary
# Description: Writes final build summary fields (status, image, duration, UUIDs).
# Parameters: $1=final_status
# Author: Pedro Rigolin
#------------------------------------------------------------------------------
function log_summary() {

    local status="$1"
    local elapsed_seconds="$(($(date +%s) - RUN_START_EPOCH))"

    log_write "SUMMARY" "status: $status"
    log_write "SUMMARY" "image: $DEST_IMAGE"
    log_write "SUMMARY" "duration_seconds: $elapsed_seconds"

    if [ -n "$SQUASHFS_PARTITION_PARTUUID" ]; then
        log_write "SUMMARY" "squashfs_partuuid: $SQUASHFS_PARTITION_PARTUUID"
    fi

    if [ -n "$FAT_PARTITION_PARTUUID" ]; then
        log_write "SUMMARY" "fat_partuuid: $FAT_PARTITION_PARTUUID"
    fi

}

#------------------------------------------------------------------------------
# Function: generate_checksum
# Description: Builds checksum metadata for auto-restore validation payload.
# Strategy: full SHA256 for small files; sampled hashes for large files.
# Parameters: $1=file_path
# Author: Pedro Rigolin
#------------------------------------------------------------------------------
function generate_checksum() {

    local FILE="$1"
    local FILE_SIZE=$(stat -c%s "$FILE")
    local FILE_SIZE_MB=$(( $FILE_SIZE / 1048576 ))

    # Full checksum for files under 500MB
    if [ $FILE_SIZE_MB -lt 500 ]; then

        local MODE="full"
        local FULL_HASH=$(sha256sum "$FILE" | awk '{print $1}')

        printf "%s\n%s\n%s" "$FILE_SIZE" "$MODE" "$FULL_HASH"
        return 0

    fi

    # Partial checksum for files 500MB and above
    local MODE="partial"
    local SAMPLE_MB=100

    # For very large files (>3GB), increase sample size
    [ $FILE_SIZE_MB -gt 3072 ] && SAMPLE_MB=200

    local MID_OFFSET=$(( ($FILE_SIZE_MB / 2) - ($SAMPLE_MB / 2) ))

    local HEAD_HASH=$(head -c ${SAMPLE_MB}M "$FILE" | sha256sum | awk '{print $1}')
    local TAIL_HASH=$(tail -c ${SAMPLE_MB}M "$FILE" | sha256sum | awk '{print $1}')
    local MID_HASH=$(dd if="$FILE" bs=1M skip=$MID_OFFSET count=$SAMPLE_MB 2>/dev/null | sha256sum | awk '{print $1}')

    printf "%s\n%s\n%s\n%s\n%s\n%s" "$FILE_SIZE" "$MODE" "$SAMPLE_MB" "$HEAD_HASH" "$TAIL_HASH" "$MID_HASH"
    return 0

}

CWD=$(pwd)
SOURCES_PATH="$CWD/sources"
TOOLS_PATH="$CWD/tools"
LOGS_DIR="$CWD/logs"

USERID=$(id -u)

if [ "$USERID" != "0" ]; then
	echo "This script can only work with root permissions"
	exit 26
fi

MOUNTED_DEVICES=()

LOOP_DEVICES=()

MOUNTED_POINTS=()

#------------------------------------------------------------------------------
# Function: cleanup
# Description: Best-effort cleanup for mounts, loop devices, and temp paths.
# Side Effects: unmounts tracked mount points, detaches tracked loop devices,
#               removes tracked temporary directories.
# Author: Pedro Rigolin
#------------------------------------------------------------------------------
function cleanup() {

    log_write "INFO" "cleanup started"

    for device in "${MOUNTED_DEVICES[@]}"; do
        log_vars "cleanup-mount" "candidate=$device"

        if mountpoint -q "$device"; then
            log_write "INFO" "cleanup unmounting mountpoint=$device"

            umount "$device" >/dev/null 2>&1

        fi

    done

    for loop in "${LOOP_DEVICES[@]}"; do
        log_vars "cleanup-loop" "candidate=$loop"

        if losetup -l | grep -q "$loop"; then
            log_write "INFO" "cleanup detaching loop=$loop"

            losetup -d "$loop" >/dev/null 2>&1

        fi

    done

    for point in "${MOUNTED_POINTS[@]}"; do
        log_vars "cleanup-temp" "removing=$point"

        rm -rf "$point" >/dev/null 2>&1

    done

    clear

    echo "Script finished. All temporary devices cleaned up."

    log_write "INFO" "cleanup finished"

}

trap cleanup EXIT

#------------------------------------------------------------------------------
# Function: mount_device
# Description: Mounts a device/path into a mount point and tracks it for cleanup.
# Parameters: $1=device_or_partition, $2=mount_point
# Returns: mount command exit status
# Author: Pedro Rigolin
#------------------------------------------------------------------------------
function mount_device() {

    local device="$1"
    local mount_point="$2"

    run_logged mount "$device" "$mount_point"

    if [ $? -ne 0 ]; then
        return $?
    fi

    MOUNTED_DEVICES+=("$mount_point")
    MOUNTED_POINTS+=("$mount_point")

}

#------------------------------------------------------------------------------
# Function: unmount_device
# Description: Unmounts a tracked mount point when currently mounted.
# Parameters: $1=mount_point
# Returns: umount command exit status when executed, otherwise 0
# Author: Pedro Rigolin
#------------------------------------------------------------------------------
function unmount_device() {

    local device="$1"

    if mountpoint -q "$device"; then

        run_logged umount "$device"

        if [ $? -ne 0 ]; then
            return $?        
        fi

        for i in "${!MOUNTED_DEVICES[@]}"; do

            if [ "${MOUNTED_DEVICES[$i]}" == "$device" ]; then
                unset 'MOUNTED_DEVICES[i]'
                break
            fi

        done

    fi

}

#------------------------------------------------------------------------------
# Function: attach_loop
# Description: Attaches an image file to a free loop device and tracks it.
# Parameters: $1=image_file_path
# Returns: 0 on success, non-zero on failure
# Author: Pedro Rigolin
#------------------------------------------------------------------------------
function attach_loop() {

    local file="$1"

    local loop=""

    run_logged_capture loop losetup -fP --show "$file"

    if [ $? -ne 0 ]; then
        return $?
    fi

    LOOP_DEVICE="$loop"
    LOOP_DEVICES+=("$loop")

    return 0

}

#------------------------------------------------------------------------------
# Function: detach_loop
# Description: Detaches a loop device if present and removes it from tracking.
# Parameters: $1=loop_device_path
# Returns: losetup detach exit status when executed, otherwise 0
# Author: Pedro Rigolin
#------------------------------------------------------------------------------
function detach_loop() {

    local loop="$1"

    if losetup -l | grep -q "$loop"; then

        run_logged losetup -d "$loop"

        if [ $? -ne 0 ]; then
            return $?
        fi

        for i in "${!LOOP_DEVICES[@]}"; do

            if [ "${LOOP_DEVICES[$i]}" == "$loop" ]; then
                unset 'LOOP_DEVICES[i]'
                break
            fi

        done

    fi

}

if ! init_logs; then

    LOG_FILE=""
    show_warning "Could not initialize log file in $LOGS_DIR"

fi

shopt -s nullglob

conf_files=(sources/*.conf)
log_vars "config-discovery" "found_conf_files=${#conf_files[@]}"

if [ "${#conf_files[@]}" -eq 0 ]; then

    show_error "No configuration files found in sources/ directory"

    exit 1

fi

options=()

for i in "${!conf_files[@]}"; do

  file="${conf_files[$i]}"

  base="$(basename "$file" .conf)"

  pretty="$(echo "$base" | sed -E 's/[_-]+/ /g')"

  options+=("$i" "$pretty")

done

choice=$(dialog \
        --clear \
        --stdout \
        --backtitle "$BACKTITLE" \
        --title "Choose" \
        --ok-label "Select" \
        --cancel-label "Exit" \
        --menu "\nChoose a configuration" 15 70 12 "${options[@]}")

status=$?
log_vars "config-selection" "dialog_status=$status selected_index=$choice"

if [ "$status" -ne 0 ]; then

    log_write "INFO" "configuration selection canceled by user"

	echo "Please specify a target configuration"

	exit 40

fi

TARGET_CONF="$CWD/${conf_files[$choice]}"
log_vars "config-selection" "target_conf=$TARGET_CONF"

if [ ! -f "$TARGET_CONF" ]; then

    show_error "Could not find ${conf_files[$choice]} target configuration file"

	exit 42

fi

. "${TARGET_CONF}"

if [ $? -ne 0 ]; then

    show_error "Could not source ${TARGET_CONF}"

	exit 41

fi

BOARD_NAME=$(echo "$TARGET_CONF" | sed -E 's/.*sources\/(.*)\.conf/\1/')

log_write "INFO" "target conf: $TARGET_CONF"

log_vars "board" "board_name=$BOARD_NAME"

NEW_LOG_FILENAME="${LOG_FILE/-unknown/-${BOARD_NAME}}"
mv "$LOG_FILE" "$NEW_LOG_FILENAME" >/dev/null 2>&1
if [ $? -ne 0 ]; then

    log_write "WARNING" "Could not rename log file to include board name"

else

    LOG_FILE="$NEW_LOG_FILENAME"
    log_write "INFO" "Log file renamed to $LOG_FILE"

fi

EMBEDDED_IMAGE=""
log_stage "embedded-image-selection"

# Embedded image selection state machine.
# Author: Pedro Rigolin
#
# Flow summary:
# 1) First screen (no file selected yet):
#    - Yes  => open Zenity file picker
#    - No   => continue build without embedded image
# 2) Second screen (file already selected):
#    - Yes  => proceed with current selection
#    - No   => reset selection and return to first screen
#
# The loop only exits in two valid terminal states:
# - User chooses to skip embedding (no file selected + press No)
# - User confirms the selected file (file selected + press Yes)
while true; do

    HAS_EMBEDDED_IMAGE=1
    YES_LABEL="Select file"
    NO_LABEL="Skip"
    YESNO="\nDo you want to embed an additional gz image into the backup folder?"
    HEIGHT=10
    WIDTH=60

    # If a file is already selected, switch dialog semantics from
    # "select or skip" to "proceed or reset" and expand dialog size
    # to better display the full selected path.
    if [ -n "$EMBEDDED_IMAGE" ]; then
        YES_LABEL="Proceed"
        NO_LABEL="Reset"
        YESNO="\nCurrently selected embedded image:\n\n$EMBEDDED_IMAGE\n\nDo you want to proceed?"
        HAS_EMBEDDED_IMAGE=0
        HEIGHT=12
        WIDTH=70
    fi

    log_vars "embedded-image-dialog" "current_selection=${EMBEDDED_IMAGE:-none} has_embedded_image=$HAS_EMBEDDED_IMAGE"

    dialog \
        --backtitle "$BACKTITLE" \
        --title " Embedded Image " \
        --yes-label "$YES_LABEL" \
        --no-label "$NO_LABEL" \
        --yesno "$YESNO" $HEIGHT $WIDTH

    DIALOG_RC=$?
    log_vars "embedded-image-dialog" "dialog_rc=$DIALOG_RC yes_label=$YES_LABEL no_label=$NO_LABEL"

    # Case A: User pressed Yes and there is no selected file yet.
    # Open file picker and validate that the chosen file is a valid .gz.
    if [ "$DIALOG_RC" -eq 0 ] && [ "$HAS_EMBEDDED_IMAGE" -eq 1 ]; then

        EMBEDDED_IMAGE=$(zenity --file-selection --title="Select gz image to embed in backup folder" --file-filter="*.gz" 2>/dev/null)
        log_vars "embedded-image-selection" "zenity_selected=${EMBEDDED_IMAGE:-none}"

        # If user picked a file, perform a lightweight gzip integrity check.
        # On failure, show error and force a new selection cycle.
        if [ -n "$EMBEDDED_IMAGE" ]; then

            run_logged pigz -l "$EMBEDDED_IMAGE"

            if [ $? -ne 0 ]; then

                log_write "WARNING" "invalid embedded image selected: $EMBEDDED_IMAGE"
                show_error "The selected file is not a valid gz file"

                EMBEDDED_IMAGE=""

            fi

        fi

    # Case B: User pressed No while a file is already selected.
    # This means "Reset" in this state, so clear selection and loop again.
    elif [ "$DIALOG_RC" -ne 0 ] && [ "$HAS_EMBEDDED_IMAGE" -eq 0 ]; then

        log_write "INFO" "embedded image selection reset by user"
        EMBEDDED_IMAGE=""

    # Case C: terminal conditions.
    # - No selected file + No pressed => continue without embedded image.
    # - Selected file + Yes pressed   => continue with selected image.
    else

        log_vars "embedded-image-selection" "final_selection=${EMBEDDED_IMAGE:-none}"
        break

    fi

done

AUTO_RESTORE_ENABLED=1
log_vars "auto-restore" "default_enabled=$AUTO_RESTORE_ENABLED"

# Auto-restore toggle for embedded image workflow.
# Default value is 1 (disabled/no) to keep a safe behavior when:
# - there is no embedded image selected, or
# - the prompt is skipped/cancelled for any reason.
if [ -n "$EMBEDDED_IMAGE" ]; then

    # Ask whether the generated image should boot with auto-restore enabled.
    # If enabled, Multitool will automatically restore the latest backup from
    # the NTFS partition to the target eMMC on startup.
    dialog \
        --backtitle "$BACKTITLE" \
        --title " Auto restore " \
        --yes-label "Yes" \
        --no-label "No" \
        --yesno "\nDo you want to enable auto-restore for this image?\n\nThis will automatically restore the latest backup found in the NTFS partition to the device's eMMC when the image is booted." 12 70

    # Store dialog return code directly:
    # 0 = Yes (enable auto-restore)
    # 1 = No  (keep disabled)
    # 255 = Esc/Cancel (treated as disabled by downstream checks)
    AUTO_RESTORE_ENABLED=$?
    log_vars "auto-restore" "dialog_rc=$AUTO_RESTORE_ENABLED embedded_image=$EMBEDDED_IMAGE"

fi

# Target-specific sources path
TS_SOURCES_PATH="$CWD/sources/${BOARD_NAME}"

# Destination path and image
DIST_PATH="${CWD}/dist-${BOARD_NAME}"
DEST_IMAGE="${DIST_PATH}/multitool.img"

log_vars "paths" "ts_sources_path=$TS_SOURCES_PATH dist_path=$DIST_PATH dest_image=$DEST_IMAGE"

run_logged mkdir -p "$DIST_PATH"

if [ ! -f "$DIST_PATH/root.img" ]; then

    show_wait "Creating debian base rootfs. This will take a while..."

    cd "${SOURCES_PATH}/multistrap"
    run_logged multistrap -f multistrap.conf

	if [ $? -ne 0 ]; then

        show_error "Failed to run multistrap. Check log file for details"
		
	fi    

    show_wait "Creating squashfs from rootfs..."

    run_logged mksquashfs rootfs "$DIST_PATH/root.img" -noappend -all-root

    if [ $? -ne 0 ]; then

        show_error "Failed to create squashfs from rootfs"

    fi

fi

ROOTFS_SIZE=$(du -k "$DIST_PATH/root.img" 2>/dev/null | awk '{print $1}')

# Validate size right after collection (must be a positive integer).
if [[ ! "$ROOTFS_SIZE" =~ ^[0-9]+$ ]] || [ "$ROOTFS_SIZE" -le 0 ]; then
    show_error "Could not determine size of squashfs root filesystem"
fi

ROOTFS_SECTORS_RAW=$((ROOTFS_SIZE * 2))
ROOTFS_SECTORS=$(round_sectors "$ROOTFS_SECTORS_RAW")

# Validate rounded sectors as well (defensive check).
if [[ ! "$ROOTFS_SECTORS" =~ ^[0-9]+$ ]] || [ "$ROOTFS_SECTORS" -le 0 ]; then
    show_error "Could not calculate rootfs sectors"
fi

log_vars "rootfs" "rootfs_size_kb=$ROOTFS_SIZE rootfs_sectors_raw=$ROOTFS_SECTORS_RAW rootfs_sectors_rounded=$ROOTFS_SECTORS"
log_write "RAW" "rootfs_size_kb=$ROOTFS_SIZE"

cd "$CWD"

show_wait "Creating empty image in $DEST_IMAGE"

# Define the base image size in Megabytes, same as the original script
# @author: Pedro Rigolin
BASE_SIZE_MB=512

# Convert the base size to Kilobytes for calculations
# @author: Pedro Rigolin
BASE_SIZE_KB=$((BASE_SIZE_MB * 1024))

# Add an extra security buffer (e.g.: 50MB) to ensure everything fits
# @author: Pedro Rigolin
BUFFER_KB=51200

# Initialize the size of the file to be embedded as zero
# @author: Pedro Rigolin
EMBED_FILE_SIZE_KB=0
EMBED_FILE_PRESENT="no"
EMBED_FILE_NAME="none"

# If the user specified a file to embed...
# @author: Pedro Rigolin
if [ -n "$EMBEDDED_IMAGE" ]; then

    # ...calculate its size in Kilobytes
    # @author: Pedro Rigolin
    EMBED_FILE_SIZE_KB=$(du "$EMBEDDED_IMAGE" | cut -f 1)
    EMBED_FILE_PRESENT="yes"
    EMBED_FILE_NAME="$(basename "$EMBEDDED_IMAGE")"
    log_vars "embedded-image" "embed_file=$EMBEDDED_IMAGE embed_file_size_kb=$EMBED_FILE_SIZE_KB"

fi

# Calculate the final image size by adding base + embedded file + buffer
# @author: Pedro Rigolin
FINAL_IMAGE_SIZE_KB=$((BASE_SIZE_KB + EMBED_FILE_SIZE_KB + BUFFER_KB))
log_vars "image-size" "base_size_mb=$BASE_SIZE_MB base_size_kb=$BASE_SIZE_KB buffer_kb=$BUFFER_KB embed_file_present=$EMBED_FILE_PRESENT embed_file_name=$EMBED_FILE_NAME embed_file_size_kb=$EMBED_FILE_SIZE_KB final_image_size_kb=$FINAL_IMAGE_SIZE_KB"

# Create the image with the calculated final size (using 'K' for Kilobytes)
run_logged fallocate -l ${FINAL_IMAGE_SIZE_KB}K "$DEST_IMAGE"

if [ $? -ne 0 ]; then

    show_error "Error while creating $DEST_IMAGE empty file"

fi

show_wait "Mounting as loop device"

LOOP_DEVICE=""
attach_loop "$DEST_IMAGE"

if [ $? -ne 0 ]; then

    show_error "Could not loop mount $DEST_IMAGE"

fi

log_vars "loop" "loop_device=$LOOP_DEVICE"

show_wait "Creating partition table and partitions..."

run_logged parted -s -- "$LOOP_DEVICE" mktable msdos

if [ $? -ne 0 ]; then

    show_error "Could not create partitions table"

fi

START_ROOTFS=$BEGIN_USER_PARTITIONS
END_ROOTFS=$(($START_ROOTFS + $ROOTFS_SECTORS - 1))
START_FAT=$(round_sectors $END_ROOTFS)
END_FAT=$(($START_FAT + 131072 - 1)) # 131072 sectors = 64Mb
START_NTFS=$(round_sectors $END_FAT)
log_vars "partition-layout" "begin_user_partitions=$BEGIN_USER_PARTITIONS start_rootfs=$START_ROOTFS end_rootfs=$END_ROOTFS start_fat=$START_FAT end_fat=$END_FAT start_ntfs=$START_NTFS"
run_logged parted -s -- "$LOOP_DEVICE" unit s mkpart primary ntfs $START_NTFS -1s

if [ $? -ne 0 ]; then

	show_error "Could not create ntfs partition"

fi

run_logged parted -s -- "$LOOP_DEVICE" unit s mkpart primary fat32 $START_FAT $END_FAT

if [ $? -ne 0 ]; then

	show_error "Could not create fat partition"

fi

run_logged parted -s -- "$LOOP_DEVICE" unit s mkpart primary $START_ROOTFS $END_ROOTFS

if [ $? -ne 0 ]; then

	show_error "Could not create rootfs partition"

fi

run_logged parted -s -- "$LOOP_DEVICE" set 1 boot off set 2 boot on set 3 boot off

if [ $? -ne 0 ]; then

	show_error "Could not set partition flags"

fi

sync
sleep 1

# First check: in containers, it may happen that loop device partitions
# spawns as soon as they are created. We check their presence. If they already
# are there, we don't remount the device
SQUASHFS_PARTITION="${LOOP_DEVICE}p3"
NTFS_PARTITION="${LOOP_DEVICE}p1"
FAT_PARTITION="${LOOP_DEVICE}p2"
log_vars "partitions-initial" "squashfs_partition=$SQUASHFS_PARTITION fat_partition=$FAT_PARTITION ntfs_partition=$NTFS_PARTITION"

if [ ! -b "$SQUASHFS_PARTITION" -o ! -b "$FAT_PARTITION" -o ! -b "$NTFS_PARTITION" ]; then

    show_wait "Remounting loop device with partitions..."

    detach_loop "$LOOP_DEVICE"
	sleep 1

    if [ $? -ne 0 ]; then

        show_error "Could not umount loop device $LOOP_DEVICE"

    fi

    LOOP_DEVICE=""
    attach_loop "$DEST_IMAGE"

    if [ $? -ne 0 ]; then

        show_error "Could not remount loop device $LOOP_DEVICE"

    fi

	SQUASHFS_PARTITION="${LOOP_DEVICE}p3"
	NTFS_PARTITION="${LOOP_DEVICE}p1"
	FAT_PARTITION="${LOOP_DEVICE}p2"
    log_vars "partitions-remount" "loop_device=$LOOP_DEVICE squashfs_partition=$SQUASHFS_PARTITION fat_partition=$FAT_PARTITION ntfs_partition=$NTFS_PARTITION"
    run_logged lsblk "$LOOP_DEVICE"

    sleep 1    

else

    log_write "INFO" "remount not required; partitions already present"

fi

if [ ! -b "$SQUASHFS_PARTITION" ]; then

	show_error "Could not find expected partition $SQUASHFS_PARTITION"

fi

if [ ! -b "$FAT_PARTITION" ]; then

	show_error "Could not find expected partition $FAT_PARTITION"

fi

if [ ! -b "$NTFS_PARTITION" ]; then

	show_error "Could not find expected partition $NTFS_PARTITION"

fi

show_wait "Copying squashfs rootfilesystem..."
run_logged dd if="${DIST_PATH}/root.img" of="$SQUASHFS_PARTITION" bs=4k conv=sync,fsync

if [ $? -ne 0 ]; then

	show_error "Could not install squashfs filesystem"

fi

# ---- boot install -----
log_write "CMD" "source ${TS_SOURCES_PATH}/boot_install"
if [ -n "$LOG_FILE" ]; then
    log_write "CMD_OUT_START" "source ${TS_SOURCES_PATH}/boot_install"
    source "${TS_SOURCES_PATH}/boot_install" >> "$LOG_FILE" 2>&1
    log_write "CMD_OUT_END" "source ${TS_SOURCES_PATH}/boot_install"
else
    source "${TS_SOURCES_PATH}/boot_install" >/dev/null 2>&1
fi
LAST_CMD_STATUS="$?"
LAST_CMD_TEXT="source ${TS_SOURCES_PATH}/boot_install"
log_write "CMD_RET" "exit=$LAST_CMD_STATUS :: source ${TS_SOURCES_PATH}/boot_install"

if [ "$LAST_CMD_STATUS" -ne 0 ]; then

    show_error "Could not execute boot_install" "$LAST_CMD_STATUS"

fi

show_wait "Formatting FAT32 partition..."

run_logged mkfs.vfat -s 16 -n "BOOTSTRAP" "$FAT_PARTITION"

if [ $? -ne 0 ]; then

	show_error "Could not format FAT32 partition"

fi

show_wait "Formatting NTFS partition..."

run_logged mkfs.ntfs -f -L "MULTITOOL" -p $START_NTFS "$NTFS_PARTITION"

if [ $? -ne 0 ]; then

	show_error "Could not format NTFS partition"

fi

TEMP_DIR=$(mktemp -d)
log_vars "mount" "temp_dir=$TEMP_DIR"

show_wait "Mounting NTFS partition..."

mount_device "$NTFS_PARTITION" "$TEMP_DIR"

if [ $? -ne 0 ]; then

	show_error "Could not mount $NTFS_PARTITION to $TEMP_DIR"

fi

show_wait "Populating partition..."

run_logged cp "${CWD}/LICENSE" "${TEMP_DIR}/LICENSE"

if [ $? -ne 0 ]; then

	show_error "Could not copy LICENSE to partition"

fi

# ===============================================================
# CREATING A CREDITS AND LICENSE FILE INDICATING THAT
# MODIFICATIONS WERE MADE TO THE ORIGINAL SOFTWARE FOR THE TVBOX PROJECT
# ===============================================================

# Define the path of the new file inside the image
CREDITS_FILE="${TEMP_DIR}/CREDITS"

# Get current system date and time
BUILD_DATE=$(date)

# 1. Create the NEW file and write the modification header first.
echo "===========================================================================" > "${CREDITS_FILE}"
echo "This software has been modified by Pedro Rigolin for the TVBox Project" >> "${CREDITS_FILE}"
echo "at the Instituto Federal de São Paulo - IFSP, Salto campus." >> "${CREDITS_FILE}"
echo "" >> "${CREDITS_FILE}"
echo "TVBox Project Mod Version: 1.0" >> "${CREDITS_FILE}"
echo "Build Date: ${BUILD_DATE}" >> "${CREDITS_FILE}"
echo "" >> "${CREDITS_FILE}"
echo "- Original Multitool Repository (Paolo Sabatino):" >> "${CREDITS_FILE}"
echo "  https://github.com/paolosabatino/multitool" >> "${CREDITS_FILE}"
echo "" >> "${CREDITS_FILE}"
echo "- Projeto TVBox Fork Repository:" >> "${CREDITS_FILE}"
echo "  https://github.com/projetotvbox/multitool" >> "${CREDITS_FILE}"
echo "===========================================================================" >> "${CREDITS_FILE}"
echo "" >> "${CREDITS_FILE}"

# 2. NOW, append the original license content to the END of your modified header.
echo "Original license text follows:" >> "${CREDITS_FILE}"
echo "--------------------------------" >> "${CREDITS_FILE}"
echo "" >> "${CREDITS_FILE}"

cat "${TEMP_DIR}/LICENSE" >> "${CREDITS_FILE}"

# =============================================================

run_logged_to_file "${TEMP_DIR}/CHANGELOG" git log --no-merges --pretty="%as: %s"

if [ $? -ne 0 ]; then

	show_error "Could not store CHANGELOG to partition"

fi

run_logged_to_file "${TEMP_DIR}/ISSUE" git log -1 --pretty="%h - %aD"

if [ $? -ne 0 ]; then

	show_error "Could not store ISSUE to paritition"

fi

printf "%s\n" "${BOARD_NAME}" > "${TEMP_DIR}/TARGET"

if [ $? -ne 0 ]; then

	show_error "Could not store TARGET to partition"

fi

run_logged mkdir -p "${TEMP_DIR}/backups"

if [ $? -ne 0 ]; then

	show_error "Could not create backup directory"

fi

run_logged mkdir -p "${TEMP_DIR}/images"

if [ $? -ne 0 ]; then

	show_error "Could not create images directory"

fi

run_logged mkdir -p "${TEMP_DIR}/bsp"

if [ $? -ne 0 ]; then

	show_error "Could not create bsp directory"

fi

if [ -n "$EMBEDDED_IMAGE" ]; then

    # If an embedded image was selected in the interactive flow, copy it into
    # the NTFS backups directory so it is available on first boot.
    show_wait "Copying embedded image into backup directory..."

    # Keep only the filename for storage in backup folder and in auto-restore
    # metadata; this avoids persisting host absolute paths inside the image.
    EMBEDDED_IMAGE_BASENAME="$(basename "$EMBEDDED_IMAGE")"

    # Final destination inside the mounted NTFS partition.
    EMBEDDED_DEST="${TEMP_DIR}/backups/${EMBEDDED_IMAGE_BASENAME}"
    log_vars "embedded-image-copy" "source=$EMBEDDED_IMAGE dest=$EMBEDDED_DEST auto_restore_enabled=$AUTO_RESTORE_ENABLED"

    run_logged cp "$EMBEDDED_IMAGE" "${EMBEDDED_DEST}"

    if [ $? -ne 0 ]; then

        show_error "Could not copy embedded image to backup directory"

    fi

    if [ "$AUTO_RESTORE_ENABLED" -eq 0 ]; then

        # Auto-restore enabled means we must pre-create auto_restore.flag with
        # the selected filename plus checksum payload for integrity validation
        # during Multitool startup.
        show_wait "Calculating checksum of the selected backup file, please wait..."

        CHECKSUM_DATA=$(generate_checksum "$EMBEDDED_DEST")

        if [ -z "$CHECKSUM_DATA" ]; then

            log_write "ERROR" "checksum generation failed for embedded image: $EMBEDDED_DEST"
            show_error "Could not generate checksum data for auto-restore"

        fi

        # Persist auto-restore metadata:
        # line 1 -> backup filename
        # line 2+ -> checksum data returned by generate_checksum
        { printf "%s\n" "$EMBEDDED_IMAGE_BASENAME"; printf "%s" "$CHECKSUM_DATA"; } > "${TEMP_DIR}/auto_restore.flag"
        log_write "INFO" "auto_restore.flag written for embedded image $EMBEDDED_IMAGE_BASENAME"

        if [ $? -ne 0 ]; then

            log_write "ERROR" "failed to persist auto_restore.flag for embedded image"
            show_error "Could not write auto_restore.flag"

        else

            log_write "INFO" "auto_restore.flag generated for embedded image $EMBEDDED_IMAGE_BASENAME"

        fi

    fi

fi

show_wait "Copying board support package blobs into bsp directory..."

run_logged cp "${DIST_PATH}/uboot.img" "${TEMP_DIR}/bsp/uboot.img"

if [ -f "${DIST_PATH}/trustos.img" ]; then
    run_logged cp "${DIST_PATH}/trustos.img" "${TEMP_DIR}/bsp/trustos.img"
fi

if [ -f "${DIST_PATH}/legacy-uboot.img" ]; then
    run_logged cp "${DIST_PATH}/legacy-uboot.img" "${TEMP_DIR}/bsp/legacy-uboot.img"
fi

show_wait "Unmount NTFS partition..."

unmount_device "$TEMP_DIR"

if [ $? -ne 0 ]; then

	show_error "Could not umount $NTFS_PARTITION"

fi

show_wait "Mounting FAT32 partition..."

mount_device "$FAT_PARTITION" "$TEMP_DIR"

if [ $? -ne 0 ]; then

	show_error "Could not mount $FAT_PARTITION to $TEMP_DIR"

fi

show_wait "Populating partition..."

run_logged cp "${TS_SOURCES_PATH}/${KERNEL_IMAGE}" "${TEMP_DIR}/kernel.img"

if [ $? -ne 0 ]; then

	show_error "Could not copy kernel"
    
fi

run_logged cp "${TS_SOURCES_PATH}/${DEVICE_TREE}" "${TEMP_DIR}/${DEVICE_TREE}"

if [ $? -ne 0 ]; then

	show_error "Could not copy device tree"

fi

run_logged mkdir -p "${TEMP_DIR}/extlinux"

if [ $? -ne 0 ]; then

	show_error "Could not create extlinux directory"

fi

run_logged cp "${TS_SOURCES_PATH}/extlinux.conf" "${TEMP_DIR}/extlinux/extlinux.conf"

if [ $? -ne 0 ]; then

	show_error "Could not copy extlinux.conf"

fi

# Gather the PARTUUID of the squashfs partition loop device
# blkid is friendlier in case of containers, so we use it here in place of lsblk
run_logged_capture SQUASHFS_PARTITION_PARTUUID blkid -o value -s PARTUUID "$SQUASHFS_PARTITION"
log_vars "partuuid" "squashfs_partition_partuuid=$SQUASHFS_PARTITION_PARTUUID"

if [ $? -ne 0 ]; then

	show_error "Could not get SQUASHFS PARTUUID"

fi

[[ -z $SQUASHFS_PARTITION_PARTUUID ]] && FINAL_MESSAGE+="\n\n--- warning: empty squashfs partition PARTUUID ---"

FINAL_MESSAGE+="\n\nSquashfs partition partuuid: $SQUASHFS_PARTITION_PARTUUID"

# Gather the PARTUUID of the FAT partition of the loop device
# blkid is friendlier in case of containers, so we use it here in place of lsblk
run_logged_capture FAT_PARTITION_PARTUUID blkid -o value -s PARTUUID "$FAT_PARTITION"
log_vars "partuuid" "fat_partition_partuuid=$FAT_PARTITION_PARTUUID"

if [ $? -ne 0 ]; then

	show_error "Could not get FAT PARTUUID"

fi

[[ -z $FAT_PARTITION_PARTUUID ]] && FINAL_MESSAGE+="\n\n--- warning: empty FAT boot partition PARTUUID ---"

FINAL_MESSAGE+="\n\nFat partition partuuid: $FAT_PARTITION_PARTUUID"

run_logged sed -i "s/#SQUASHFS_PARTUUID#/$SQUASHFS_PARTITION_PARTUUID/g" "${TEMP_DIR}/extlinux/extlinux.conf"

if [ $? -ne 0 ]; then

	show_error "Could not substitute SQUASHFS PARTUUID in extlinux.conf"

fi

run_logged sed -i "s/#FAT_PARTUUID#/$FAT_PARTITION_PARTUUID/g" "${TEMP_DIR}/extlinux/extlinux.conf"

if [ $? -ne 0 ]; then

	show_error "Could not substitute FAT PARTUUID in extlinux.conf"

fi

show_wait "Unmount FAT32 partition..."

unmount_device "$TEMP_DIR"

if [ $? -ne 0 ]; then

	show_error "Could not umount $FAT_PARTITION"

fi

run_logged rm -rf "$TEMP_DIR"

if [ $? -ne 0 ]; then

	show_error "Could not remove temporary directory $TEMP_DIR"

fi

show_wait "Unmounting loop device..."

detach_loop "$LOOP_DEVICE"

if [ $? -ne 0 ]; then

	show_error "Could not unmount $LOOP_DEVICE"

fi

sync
sleep 2

log_summary "success"

FINAL_MESSAGE="\nDone! Available image in ${DEST_IMAGE}${FINAL_MESSAGE}"

if [ -n "$LOG_FILE" ]; then
    FINAL_MESSAGE+="\n\nLog file: ${LOG_FILE}"
fi

dialog \
    --backtitle "$BACKTITLE" \
    --title "Success" \
    --ok-label "OK" \
    --msgbox "$FINAL_MESSAGE" 15 60