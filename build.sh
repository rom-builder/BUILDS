#!/bin/bash

source util.sh
source .env # remove this line if you want to environment variables to be set in the shell or use a different method to set them

# Check if required variables are set
req_vars=("DEVICE" "ROM_NAME" "GIT_NAME" "GIT_EMAIL" "REPOS_JSON" "SETUP_SOURCE_COMMAND" "SYNC_SOURCE_COMMAND" "BUILD_VANILLA_COMMAND" "RELEASE_GITHUB_TOKEN" "GITHUB_RELEASE_REPO" "OUT_DIR" "RELEASE_FILES_PATTERN")
for var in "${req_vars[@]}"; do
    if [ -z "${!var}" ]; then
        echo "Required variable $var is not set. Please set it in .env"
        exit 1
    fi
done

telegram_send_message "---------------------------------"
update_tg "Build Initiated: [$ROM_NAME for $DEVICE]($GITHUB_RUN_URL)"

update_tg "Starting build..."
echo "Starting build..."
start_time=$(date +%s)

# Install dependencies
resolve_dependencies

# Setup git
git_setup $GIT_NAME $GIT_EMAIL

# Clone repos
git_clone_json $REPOS_JSON

# Cleanup old builds
clean_build $OUT_DIR

# Setup source
update_tg "Setting up source..."
echo "Setting up source..."
eval $SETUP_SOURCE_COMMAND

# Sync source
update_tg "Syncing source..."
echo "Syncing source..."
eval  $SYNC_SOURCE_COMMAND

# Build Vanilla
update_tg "Building vanilla..."
echo "Building vanilla..."
# if tee log.txt command is found in BUILD_VANILLA_COMMAND then don't add extra tee command or LOG_OUTPUT is set to false
if [[ $BUILD_VANILLA_COMMAND == *"tee log.txt"* ]] || [ "$LOG_OUTPUT" == "false" ]; then
    eval $BUILD_VANILLA_COMMAND
    telegram_send_file log.txt "Vanilla build log"
else
    vanilla_log_file="vanilla_build_log.txt"
    eval $BUILD_VANILLA_COMMAND | tee $vanilla_log_file
    telegram_send_file $vanilla_log_file "Vanilla build log"
fi

# Build GApps
# if BUILDS_GAPPS_SCRIPT is set else skip
if [ -n "$BUILD_GAPPS_COMMAND" ]; then
    gapps_log_file="gapps_build_log.txt"
    logt "Building GApps..."
    $BUILD_GAPPS_COMMAND | tee $gapps_log_file
    telegram_send_file $gapps_log_file "GApps build log"
else
    echo "BUILDS_GAPPS_COMMAND is not set. Skipping GApps build."
fi

# Release builds
tag=$(date +'v%d-%m-%Y-%H%M%S')
github_release --token $RELEASE_GITHUB_TOKEN --repo $GITHUB_RELEASE_REPO --tag $tag --pattern $RELEASE_FILES_PATTERN

end_time=$(date +%s)
# convert seconds to hours, minutes and seconds
time_taken=$(printf '%dh:%dm:%ds\n' $(($end_time-$start_time))%3600/60 $(($end_time-$start_time))%60)
telegram_send_message "[Build finished in *$time_taken*](https://github.com/$GITHUB_RELEASE_REPO/releases/tag/$tag)]"
telegram_send_message "---------------------------------"
echo "Build finished in $time_taken"
