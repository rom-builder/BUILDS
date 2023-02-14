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
    exit 1
  fi

  curl -s "https://api.telegram.org/bot$token/sendMessage" -d chat_id="$chat" -d text="$message" -d parse_mode=MARKDOWN -d disable_web_page_preview="$disable_web_page_preview"
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

  curl -s "https://api.telegram.org/bot$token/sendDocument" -F chat_id="$chat" -F document=@"$file" -F caption="$caption"
}

update_tg() {
  local message="$1"
  telegram_send_message "Build $ROM_NAME for $DEVICE %0A%0A *$message*" true
}

logt() {
  message="$1"
  update_tg "$message"
  echo "$message"
}

resolve_dependencies() {
  packages=("repo" "git-core" "gnupg" "flex" "bison" "build-essential" "zip" "curl" "zlib1g-dev" "libc6-dev-i386" "libncurses5" "lib32ncurses5-dev" "x11proto-core-dev" "libx11-dev" "lib32z1-dev" "libgl1-mesa-dev" "libxml2-utils" "xsltproc" "unzip" "openssl" "libssl-dev" "fontconfig" "jq")
  echo "Updating package lists..."
  sudo apt-get update -y 
  echo "Installing dependencies..."
  sudo apt-get install -y ${packages[@]}
  echo "Dependencies check complete."
}

git_setup() {
  declare -r name="$1"
  declare -r email="$2"
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
    cd "$dir"
    git pull
    cd - > /dev/null
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

repo_exists() {
  local repo="$1"
  local token="$2"
  local response=$(curl -s -H "Authorization: Bearer $token" "https://api.github.com/repos/$repo")
  if [[ $response == *"\"message\": \"Not Found\""* ]]; then
    return 1 # repo does not exist
  else
    return 0 # repo exists
  fi
}

create_repo() {
  local repo="$1"
  local token="$2"
  #  split repo from owner/repo
  local repo_name=$(echo "$repo" | cut -d'/' -f2)
  local org=$(echo "$repo" | cut -d'/' -f1)
  local response=$(curl -s -H "Authorization: Bearer $token" -d "{\"name\":\"$repo_name\",\"private\":false, \"description\": \"Builds for $repo_name\", \"auto_init\": true}" "https://api.github.com/orgs/$org/repos")
  echo $response
  if [[ $response == *"\"message\": \"Validation Failed\""* ]]; then
    echo "Failed to create repository: $response"
    return 1
  else
    echo "Repository created: $owner/$repo"
    return 0
  fi
}


git_clone_json() {
  local json_file="$1"
  # Check if the file exists
  if [ ! -f "$json_file" ]; then
    logt "File $json_file does not exist. Aborting."
    exit 1
  fi
  for repo in $(jq -r '.repos[].repo' $json_file); do
    dir=$(jq -r --arg repo "$repo" '.repos[] | select(.repo == $repo) | .dir' $json_file)
    branch=$(jq -r --arg repo "$repo" '.repos[] | select(.repo == $repo) | .branch' $json_file)

    # if branch is not specified
    if [ "$branch" == "null" ]; then
      echo "Repo: $repo Dir: $dir"
      git_clone -r "$repo" -d "$dir"
    else
      echo "Repo: $repo Dir: $dir Branch: $branch"
      git_clone -r "$repo" -d "$dir" -b "$branch"
    fi
  done
}

clean_build() {
  declare -r dir="$1"
  echo "Cleaning build directory: $dir"
  if [ -d "$dir" ]; then
    rm -rf "$dir"
  else
    echo "Build directory does not exist."
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

  # Check if $OUT_DIR is set
  if [ -z "$OUT_DIR" ]; then
    logt "OUT_DIR is not set. Aborting upload."
    exit 1
  fi

  # Check if files exist
  echo "Checking if files exist..."
  if [ -z "$(ls -A $OUT_DIR | grep -E "$pattern")" ]; then
    echo $(ls -A $OUT_DIR | grep -E "$pattern")
    logt "No files found matching pattern $pattern. Aborting upload."
    exit 1
  else
    echo "Files found matching pattern $pattern."
  fi

  # Check if repo exists
  echo "Checking if repo exists..."
  if repo_exists "$repo" "$token"; then
    echo "Repository already exists: $owner/$repo"
  else
    echo "Creating repository: $owner/$repo"
    create_repo "$repo" "$token"
  fi

  # Get the SHA of the latest commit in the repository
  echo "Gethering latest commit SHA..."
  latest_sha=$(curl -s -H "Authorization: token $token" "https://api.github.com/repos/$repo/commits" | jq -r '.[0].sha')

  # Create the new tag
  echo "Creating tag $tag..."
  tag_response=$(curl -s -H "Authorization: token $token" "https://api.github.com/repos/$repo/git/tags" -d "{\"tag\":\"$tag\",\"message\":\"Release $tag\",\"object\":\"$latest_sha\",\"type\":\"commit\",\"tagger\":{\"name\":\"$GIT_COMMITTER_NAME\",\"email\":\"$GIT_COMMITTER_EMAIL\"}}")
  tag_sha=$(echo $tag_response | jq -r '.sha')

  if [ "$tag_sha" = "null" ]; then
    logt "Failed to create tag $tag in $repo. Aborting upload."
    exit 1
  fi

  # Create the release
  echo "Creating release $tag..."
  release_response=$(curl -s -H "Authorization: token $token" "https://api.github.com/repos/$repo/releases" -d "{\"tag_name\":\"$tag\",\"name\":\"$tag\"}")
  release_id=$(echo $release_response | jq -r '.id')

  # Upload each file that matches the pattern
  for file in $(ls -A $OUT_DIR | grep -E "$pattern"); do
    logt "Uploading $file..."
    filename=$(basename "$file")
    curl -s -H "Authorization: token $token" -H "Content-Type: application/octet-stream" --data-binary @"$file" "https://uploads.github.com/repos/$repo/releases/$release_id/assets?name=$filename"
  done

  logt "Uploaded files to release $tag in $repo."
  
}

# Export functions
export -f resolve_dependencies git_setup git_clone git_clone_json clean_build github_release telegram_send_message telegram_send_file update_tg logt
