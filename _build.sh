#!/bin/bash

source _utils.sh
source ._env # remove this line if you want to environment variables to be set in the shell or use a different method to set them

# Check if required variables are set
req_vars=("DEVICE" "ROM_NAME" "GIT_NAME" "GIT_EMAIL" "REPOS_JSON" "SETUP_SOURCE_COMMAND" "SYNC_SOURCE_COMMAND" "RELEASE_GITHUB_TOKEN" "GITHUB_RELEASE_REPO" "RELEASE_OUT_DIR" "RELEASE_FILES_PATTERN")
for var in "${req_vars[@]}"; do
    if [ -z "${!var}" ]; then
        echo "Required variable $var is not set. Please set it in ._env"
        exit 1
    fi
done

telegram_send_message "⏳"
telegram_send_message "*Build Initiated*: [$ROM_NAME for $DEVICE]($GITHUB_RUN_URL)" true

# Check either BUILD_VANILLA_COMMAND or BUILD_GAPPS_COMMAND is set
if [ -z "$BUILD_VANILLA_COMMAND" ] && [ -z "$BUILD_GAPPS_COMMAND" ]; then
    logt "Either BUILD_VANILLA_COMMAND or BUILD_GAPPS_COMMAND is not set. Please set it in ._env"
    exit 1
fi

start_time=$(date +%s)

# Install dependencies
resolve_dependencies | tee resolve_dependencies_log.txt

# Setup git
git_setup $GIT_NAME $GIT_EMAIL

# Cleanup old builds
clean_build $RELEASE_OUT_DIR

# if PRE_SETUP_SOURCE_COMMAND is set then run it
if [ -n "$PRE_SETUP_SOURCE_COMMAND" ]; then
    echo "Running pre-setup source command..."
    eval $PRE_SETUP_SOURCE_COMMAND
fi

# Setup source
echo "Setting up source..."
eval $SETUP_SOURCE_COMMAND

# if POST_SETUP_SOURCE_COMMAND is set then run it
if [ -n "$POST_SETUP_SOURCE_COMMAND" ]; then
    echo "Running post-setup source command..."
    eval $POST_SETUP_SOURCE_COMMAND
fi

# Call git_clone_json for repos with before_sync true
git_clone_before_sync_log_file="clone_repos_before_sync_log.txt"
(git_clone_json $REPOS_JSON true | tee $git_clone_before_sync_log_file)
if [ $? -ne 0 ]; then
    logt "Cloning repos for before_sync failed. Aborting."
    telegram_send_file $git_clone_before_sync_log_file "Cloning repos log"
    exit 1
fi

# if PRE_SYNC_SOURCE_COMMAND is set then run it
if [ -n "$PRE_SYNC_SOURCE_COMMAND" ]; then
    echo "Running pre-sync source command..."
    eval $PRE_SYNC_SOURCE_COMMAND
fi

# Sync source
logt "Syncing source..."
start_time_sync=$(date +%s)
(eval  $SYNC_SOURCE_COMMAND | tee sync_source_log.txt)
if [ $? -ne 0 ]; then
    echo "Sync failed. Aborting."
    telegram_send_message "Sync failed. Aborting."
    telegram_send_file sync_source_log.txt "Sync source log"
    exit 1
fi
end_time_sync=$(date +%s)
sync_time_taken=$(compute_build_time $start_time_sync $end_time_sync)
logt "Sync completed in $sync_time_taken"


# if POST_SYNC_SOURCE_COMMAND is set then run it
if [ -n "$POST_SYNC_SOURCE_COMMAND" ]; then
    echo "Running post-sync source command..."
    eval $POST_SYNC_SOURCE_COMMAND
fi

# Clone repos
(git_clone_json $REPOS_JSON | tee clone_repos_log.txt)
if [ $? -ne 0 ]; then
    logt "Cloning repos failed. Aborting."
    telegram_send_file clone_repos_log.txt "Clone repos log"
    exit 1
fi

# if PRE_BUILD_COMMAND is set then run it
if [ -n "$PRE_BUILD_COMMAND" ]; then
    echo "Running pre-build command..."
    eval $PRE_BUILD_COMMAND
fi

# Build Vanilla
# if BUILDS_VANILLA_SCRIPT is set else skip
if [ -n "$BUILD_VANILLA_COMMAND" ]; then
    start_time_vanilla=$(date +%s)
    logt "Building vanilla..."
    # if LOG_OUTPUT is set to false then don't log output
    if [ "$LOG_OUTPUT" == "false" ]; then
        (eval $BUILD_VANILLA_COMMAND)
        if [ $? -ne 0 ]; then
            logt "Vanilla build failed. Aborting."
        fi
    else
        vanilla_log_file="vanilla_build_log.txt"
        (eval $BUILD_VANILLA_COMMAND | tee $vanilla_log_file)
        if [ $? -ne 0 ]; then
            logt "Vanilla build failed. Aborting."
        fi
        telegram_send_file $vanilla_log_file "Vanilla build log"
    fi
    end_time_vanilla=$(date +%s)
    vanilla_time_taken=$(compute_build_time $start_time_vanilla $end_time_vanilla)
    logt "Vanilla build completed in $vanilla_time_taken"
else
    echo "BUILDS_VANILLA_COMMAND is not set. Skipping vanilla build."
fi

# Build GApps
# if BUILDS_GAPPS_SCRIPT is set else skip
if [ -n "$BUILD_GAPPS_COMMAND" ]; then
    start_time_gapps=$(date +%s)
    gapps_log_file="gapps_build_log.txt"
    logt "Building GApps..."
    # if LOG_OUTPUT is set to false then don't log output
    if [ "$LOG_OUTPUT" == "false" ]; then
        (eval $BUILD_GAPPS_COMMAND)
        if [ $? -ne 0 ]; then
            logt "GApps build failed. Aborting."
        fi
    else
        (eval $BUILD_GAPPS_COMMAND | tee $gapps_log_file)
        if [ $? -ne 0 ]; then
            logt "GApps build failed. Aborting."
        fi
        telegram_send_file $gapps_log_file "GApps build log"
    fi
    end_time_gapps=$(date +%s)
    gapps_time_taken=$(compute_build_time $start_time_gapps $end_time_gapps)
    logt "GApps build completed in $gapps_time_taken"
else
    echo "BUILDS_GAPPS_COMMAND is not set. Skipping GApps build."
fi

# Release builds
tag=$(date +'v%d-%m-%Y-%H%M')
(github_release --token $RELEASE_GITHUB_TOKEN --repo $GITHUB_RELEASE_REPO --tag $tag --pattern $RELEASE_FILES_PATTERN)
if [ $? -ne 0 ]; then
    logt "Releasing builds failed. Aborting."
fi

end_time=$(date +%s)
# convert seconds to hours, minutes and seconds
time_taken=$(compute_build_time $start_time $end_time)
telegram_send_message "Total time taken *$time_taken*"
echo "Total time taken $time_taken"

logt "Build finished."

# if POST_BUILD_COMMAND is set then run it
if [ -n "$POST_BUILD_COMMAND" ]; then
    echo "Running post-build command..."
    eval $POST_BUILD_COMMAND
fi
