#!/bin/bash

telegram_send_message() {
  # use environment variables
  local token=$TG_TOKEN
  local chat=$TG_CHAT
  local message=$1 
  local disable_web_page_preview=$2

  if [ -z "$token" ] || [ -z "$chat" ]; then
    return
  fi

  if [ -z "$message" ]; then
    echo "No message passed. Aborting."
    return
  fi

  local send_message_response=$(curl -s "https://api.telegram.org/bot$token/sendMessage" -d chat_id="$chat" -d text="$message" -d parse_mode=MARKDOWN -d disable_web_page_preview="$disable_web_page_preview")
  if [ "$(echo "$send_message_response" | jq -r '.ok')" == "true" ]; then
    echo "Message sent to Telegram."
  else
    echo "Error sending message to Telegram."
  fi
}

telegram_send_file() {
  # use environment variables
  local token=$TG_TOKEN
  local chat=$TG_CHAT
  local file=$1
  local caption=$2

  if [ -z "$token" ] || [ -z "$chat" ]; then
    return
  fi

  if [ -z "$file" ]; then
    echo "No file passed. Aborting."
    exit 1
  fi

  local send_file_response=$(curl -s "https://api.telegram.org/bot$token/sendDocument" -F chat_id="$chat" -F document=@"$file" -F caption="$caption")
  if [ "$(echo "$send_file_response" | jq -r '.ok')" == "true" ]; then
    echo "File $file sent to Telegram."
  else
    echo "Error sending file $file to Telegram."
  fi
}

update_tg() {
  local message="$1"
  telegram_send_message "*$message*" true
}

logt() {
  local message="$1"
  update_tg "$message"
  echo "$message"
}

resolve_dependencies() {
  local packages=('repo' 'git-core' 'gnupg' 'flex' 'bison' 'build-essential' 'zip' 'curl' 'zlib1g-dev' 'libc6-dev-i386' 'libncurses5' 'lib32ncurses5-dev' 'x11proto-core-dev' 'libx11-dev' 'lib32z1-dev' 'libgl1-mesa-dev' 'libxml2-utils' 'xsltproc' 'unzip' 'openssl' 'libssl-dev' 'fontconfig' 'jq' 'openjdk-8-jdk')
  echo "Updating package lists..."
  sudo apt-get update -y 
  echo "Installing dependencies..."
  sudo apt-get install -y "${packages[@]}"
  echo "Dependencies check complete."
}

git_setup() {
  local name="$1"
  local email="$2"
  echo "Setting up git with email: $email and name: $name"
  git config --global user.email "$email"
  git config --global user.name "$name"
  git config --global pull.rebase true
}

git_clone() {
  # take arguments as -r repo -d dir -b branch
  while [[ "$#" -gt 0 ]]; do
    case $1 in
      -r|--repo) repo="$2"; shift ;;
      -d|--dir) dir="$2"; shift ;;
      -b|--branch) branch="$2"; shift ;;
      *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
  done

  # Check if the directory exists
  if [ -d "$dir" ]; then
    echo "Already cloned $repo into $dir."
    echo "Pulling latest changes..."
    (
      cd "$dir" || exit
      git pull
    )
    return
  else # Clone the repo into the directory
    # If branch is not null
    if [ "$branch" != "null" ]; then
      echo "Cloning $repo into $dir with branch $branch..."
      git clone "$repo" -b "$branch" "$dir"
    else
      echo "Cloning $repo into $dir..."
      git clone "$repo" "$dir"
    fi
  fi

  # Clear variables
  unset repo dir branch
}

git_clone_json() {
  local json_file="$1"
  local before_sync="$2"
  # Check if the file exists
  if [ ! -f "$json_file" ]; then
    logt "File $json_file does not exist. Aborting."
    exit 1
  fi

  if [ "$before_sync" == "true" ]; then
    echo "Pulling repos required before sync..."
  else
    echo "Pulling repos required after sync..."
  fi

  for repo in $(jq -r '.repos[].repo' $json_file); do
    before_sync_repo=$(jq -r --arg repo "$repo" '.repos[] | select(.repo == $repo) | .before_sync' $json_file)

    # if before_sync is true then clone only the repos with before_sync set to true
    if [ "$before_sync" == "true" ]; then
      if [ "$before_sync_repo" != "true" ]; then
        continue
      fi
    fi

    # if before_sync is false or null then skip the repos with before_sync set to true
    if [ -z "$before_sync" ] || [ "$before_sync" == "false" ]; then
      if [ "$before_sync_repo" == "true" ]; then
        continue
      fi
    fi

    dir=$(jq -r --arg repo "$repo" '.repos[] | select(.repo == $repo) | .dir' $json_file)
    branch=$(jq -r --arg repo "$repo" '.repos[] | select(.repo == $repo) | .branch' $json_file)
    pre_command=$(jq -r --arg repo "$repo" '.repos[] | select(.repo == $repo) | .pre_command' $json_file)
    post_command=$(jq -r --arg repo "$repo" '.repos[] | select(.repo == $repo) | .post_command' $json_file)

    # If pre_command is not null
    if [ "$pre_command" != "null" ]; then
      echo "Running pre_commands for $repo..."
      eval "$pre_command"
    fi
    
    # if branch is not specified
    if [ "$branch" == "null" ]; then
      echo "Repo: $repo Dir: $dir"
      git_clone -r "$repo" -d "$dir"
    else
      echo "Repo: $repo Dir: $dir Branch: $branch"
      git_clone -r "$repo" -d "$dir" -b "$branch"
    fi

    # If post_commands is not null
    if [ "$post_command" != "null" ]; then
      echo "Running post_commands for $repo..."
      eval "$post_command"
    fi
  done
}

clean_build() {
  local dir="$1"
  echo "Cleaning build directory: $dir"
  if [ -d "$dir" ]; then
    rm -rf "$dir"
  else
    echo "Build directory does not exist."
  fi
}

# Create a function to check if github repo exists or not
check_github_repo() {
  local repo=$1
  local token=$2
  local response=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $token" https://api.github.com/repos/$repo)
  if [[ $response -eq 200 ]]; then
    return 0  # true
  else
    return 1  # false
  fi
}

# Create a function to create a github repo
create_github_repo() {
  local repo_name=$1
  local token=$2
  local repo=$(echo $repo_name | cut -d'/' -f2)
  local org=$(echo $repo_name | cut -d'/' -f1)
  local data="{\"name\":\"$repo\",\"auto_init\":true,\"private\":false, \"has_issues\": false, \"has_projects\": false, \"has_wiki\": false, \"description\": \"Automated build releases for $DEVICE-$ROM_NAME\"}"
  # Spit owner and repo from owner/repo
  local response=$(curl -s -H "Authorization: Bearer $token" -d "$data" https://api.github.com/orgs/$org/repos)
  local status=$(echo $response | jq -r '.message')
  if [[ "$status" == "null" ]]; then
    echo "Repository $repo_name created successfully."
    return 0  # true
  else
    echo "Error creating repository: $status"
    return 1  # false
  fi
}

github_release() {
  while [[ "$#" -gt 0 ]]; do
    case $1 in
      -tk|--token) token="$2"; shift ;;
      -r|--repo) repo="$2"; shift ;;
      -tg|--tag) tag="$2"; shift ;;
      -p|--pattern) pattern="$2"; shift ;;
      *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
  done

  # check if all variables are set
  required_vars=(token repo tag pattern)
  for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
      echo "Variable $var is not set. Aborting."
      return
    fi
  done

  # Check if $RELEASE_OUT_DIR is set
  if [ -z "$RELEASE_OUT_DIR" ]; then
    logt "RELEASE_OUT_DIR is not set. Aborting upload."
    exit 1
  fi

  # Check if files exist
  echo "Checking if files exist..."
  if [ -z "$(ls -A $RELEASE_OUT_DIR | grep -E "$pattern")" ]; then
    echo $(ls -A $RELEASE_OUT_DIR | grep -E "$pattern")
    update_tg "Build had no files to upload."
    echo "No files found matching pattern $pattern. Aborting upload."
    return
  else
    echo "Files found matching pattern $pattern."
  fi

  # Check if github repo exists
  if ! check_github_repo "$repo" "$token"; then
    echo "Github repo $repo does not exist. Creating..."
    if create_github_repo "$repo" "$token"; then
      echo "Github: $repo created successfully."
    else
      logt "Failed to create github repo $repo. Aborting upload."
      return
    fi
  fi

  # Create the release
  echo "Creating release $tag..."
  local release_response=$(curl -s -H "Authorization: Bearer $token" "https://api.github.com/repos/$repo/releases" -d "{\"tag_name\":\"$tag\",\"name\":\"$ROM_NAME $tag\",\"body\":\"Release version **$tag**\n\nDevice: $DEVICE\nROM: $ROM_NAME\n\n***Happy flashing!***\",\"generate_release_notes\":false}")
  local release_url=$(echo $release_response | jq -r '.html_url')
  if [ -z "$release_url" ]; then
    logt "Release URL is null. Some error occured when creating the release. Aborting upload."
    echo "Release response: $release_response"
    return
  else
    local release_id=$(echo $release_response | jq -r '.id')
    echo "Release URL: $release_url"
  fi
  telegram_send_message "Created [Release]($release_url)" true
  echo "Release created at $release_url"

  # Upload each file that matches the pattern
  for file in $(ls -A $RELEASE_OUT_DIR | grep -E "$pattern"); do
    echo "Uploading $file..."
    file_release=$(curl -s -H "Authorization: Bearer $token" -H "Content-Type: application/octet-stream" -T "$RELEASE_OUT_DIR/$file" "https://uploads.github.com/repos/$repo/releases/$release_id/assets?name=$file")
    file_url=$(echo $file_release | jq -r '.browser_download_url')
    # if file_url is null or empty
    if [ -z "$file_url" ]; then
      logt "File URL is null. Some error occured when uploading the file. Aborting upload."
      echo "File release response: $file_release"
      return
    else
      echo "File URL: $file_url"
    fi
    telegram_send_message "[$file]($file_url)" true
  done

  telegram_send_message "Uploaded files to [release $tag in $repo]($release_url)" true
  echo "Uploaded files to release $tag in $repo"
  
}

compute_build_time() {
  local start_time="$1"
  local end_time="$2"
  local build_time=$((end_time - start_time))
  local hours=$((build_time / 3600))
  local minutes=$((build_time % 3600 / 60))
  local seconds=$((build_time % 60))
  if [ "$hours" -gt 0 ]; then
    echo "$hours h $minutes m $seconds s"
  elif [ "$minutes" -gt 0 ]; then
    echo "$minutes m $seconds s"
  else
    echo "$seconds s"
  fi
}

# Export functions
export -f resolve_dependencies git_setup git_clone git_clone_json clean_build github_release telegram_send_message telegram_send_file update_tg logt
