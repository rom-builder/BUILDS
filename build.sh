#!/bin/bash

source util.sh
source .env # remove this line if you want to environment variables to be set in the shell or use a different method to set them

# Check if required variables are set
req_vars=("GIT_NAME" "GIT_EMAIL" "REPOS_JSON" "SETUP_SOURCE_COMMAND" "SYNC_SOURCE_COMMAND" "BUILD_VANILLA_COMMAND" "RELEASE_GITHUB_TOKEN" "GITHUB_RELEASE_REPO" "OUT_DIR" "RELEASE_FILES_PATTERN")
for var in "${req_vars[@]}"; do
    if [ -z "${!var}" ]; then
        echo "Required variable $var is not set. Please set it in .env"
        exit 1
    fi
done

# Install dependencies
resolve_dependencies

# Setup git
git_setup $GIT_NAME $GIT_EMAIL

# Clone repos
git_clone_json $REPOS_JSON

# Cleanup old builds
clean_build $OUT_DIR

# Setup source
$SETUP_SOURCE_COMMAND

# Sync source
$SYNC_SOURCE_COMMAND

# Build Vanilla
# if tee log.txt command is found in BUILD_VANILLA_COMMAND then don't add extra tee command or LOG_OUTPUT is set to false
if [[ $BUILD_VANILLA_COMMAND == *"tee log.txt"* ]] || [ "$LOG_OUTPUT" == "false" ]; then
    $BUILD_VANILLA_COMMAND
else
    $BUILD_VANILLA_COMMAND | tee vanilla.log
fi

# Build GApps
# if BUILDS_GAPPS_SCRIPT is set else skip
if [ -n "$BUILD_GAPPS_COMMAND" ]; then
    $BUILD_GAPPS_COMMAND | tee gapps.log
else
    echo "BUILDS_GAPPS_COMMAND is not set. Skipping GApps build."
fi

# Release builds
tag=$(date +'v%d-%m-%Y-%H%M%S')
github_release --token $RELEASE_GITHUB_TOKEN --repo $GITHUB_RELEASE_REPO --tag $tag --pattern $RELEASE_FILES_PATTERN
