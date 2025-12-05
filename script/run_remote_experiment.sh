#!/bin/bash
# Remote Experiment Runner Script
# This script syncs code and executes experiment.py on a remote CloudLab server
#
# Usage: ./run_remote_experiment.sh [remote_workspace_path]
# Example: ./run_remote_experiment.sh ~/narwhal-1

REMOTE_HOST="wucy@pc30.cloudlab.umass.edu"
REMOTE_PORT="25411"
# Parse arguments: first arg is workspace path (if not --skip-build), second can be --skip-build
if [ "$1" = "--skip-build" ]; then
    REMOTE_WORKSPACE="~/narwhal"
    SKIP_BUILD_ARG="--skip-build"
elif [ "$2" = "--skip-build" ]; then
    REMOTE_WORKSPACE="${1:-~/narwhal}"
    SKIP_BUILD_ARG="--skip-build"
else
    REMOTE_WORKSPACE="${1:-~/narwhal}"
    SKIP_BUILD_ARG=""
fi
SCRIPT_NAME="experiment.py"
SSH_PASSPHRASE="michael"  # SSH key passphrase

# Function to execute SSH command with automatic passphrase input
ssh_with_passphrase() {
    local command="$1"
    # Create expect script using environment variable to pass command
    export SSH_CMD="$command"
    local expect_script=$(mktemp)
    
    cat > "$expect_script" <<'EXPECT_SCRIPT_EOF'
set timeout 7200
set cmd $env(SSH_CMD)
spawn ssh -p 25411 wucy@pc30.cloudlab.umass.edu $cmd
expect {
    "Enter passphrase for key" {
        send "michael\r"
        exp_continue
    }
    "passphrase:" {
        send "michael\r"
        exp_continue
    }
    "Password:" {
        send "michael\r"
        exp_continue
    }
    eof
}
catch wait result
set exit_code [lindex $result 3]
exit $exit_code
EXPECT_SCRIPT_EOF
    
    expect -f "$expect_script"
    local exit_code=$?
    unset SSH_CMD
    rm -f "$expect_script" 2>/dev/null
    return $exit_code
}

# Get the script directory and workspace root
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=========================================="
echo "Remote Experiment Runner"
echo "=========================================="
echo "Remote Host: $REMOTE_HOST:$REMOTE_PORT"
echo "Remote Workspace: $REMOTE_WORKSPACE"
echo "Local Workspace: $WORKSPACE_DIR"
echo "Script: $SCRIPT_NAME"
echo ""

# Step 1: Sync code from GitHub
echo "Step 1: Syncing code from GitHub..."
echo "----------------------------------------"

# Get git remote URL and branch from local repo
GIT_REPO_URL="${GIT_REPO_URL:-$(cd "$WORKSPACE_DIR" && git remote get-url origin 2>/dev/null || echo "https://github.com/Michael112233/narwhal.git")}"
GIT_BRANCH="${GIT_BRANCH:-$(cd "$WORKSPACE_DIR" && git branch --show-current 2>/dev/null || echo "narwhal")}"

echo "Repository: $GIT_REPO_URL"
echo "Branch: $GIT_BRANCH"
echo "Remote workspace: $REMOTE_WORKSPACE"
echo ""

# Sync code using git pull or clone
ssh_with_passphrase "bash -c '
    eval remote_workspace=\"$REMOTE_WORKSPACE\"
    echo \"Checking remote workspace: \$remote_workspace\"
    if [ -d \"\$remote_workspace/.git\" ]; then
        echo \"Git repository found, pulling latest changes...\"
        cd \"\$remote_workspace\" && git fetch origin && git reset --hard origin/$GIT_BRANCH && git clean -fd
    else
        echo \"Git repository not found at \$remote_workspace/.git\"
        if [ -d \"\$remote_workspace\" ]; then
            echo \"Directory \$remote_workspace exists but is not a git repository, removing it...\"
            rm -rf \"\$remote_workspace\"
        else
            echo \"Directory \$remote_workspace does not exist, will clone...\"
        fi
        parent_dir=\$(dirname \"\$remote_workspace\")
        repo_name=\$(basename \"\$remote_workspace\")
        echo \"Cloning repository to: \$parent_dir/\$repo_name\"
        mkdir -p \"\$parent_dir\"
        cd \"\$parent_dir\" && git clone -b $GIT_BRANCH $GIT_REPO_URL \"\$repo_name\"
    fi
'"

SYNC_EXIT_CODE=$?

if [ $SYNC_EXIT_CODE -ne 0 ]; then
    echo ""
    echo "Error: Code sync failed with exit code: $SYNC_EXIT_CODE"
    exit $SYNC_EXIT_CODE
fi

echo ""
echo "Code sync from GitHub completed successfully!"
echo ""

# Step 2: Build the project
# Check if user wants to skip build
SKIP_BUILD="${SKIP_BUILD:-false}"
if [ "$SKIP_BUILD_ARG" = "--skip-build" ]; then
    SKIP_BUILD="true"
fi

if [ "$SKIP_BUILD" != "true" ]; then
    echo "Step 2: Building the project on remote server..."
    echo "----------------------------------------"
    echo "Note: This may take 10-30 minutes for a full build."
    echo "You can skip this step by setting SKIP_BUILD=true or using --skip-build"
    echo ""
    echo "Executing cargo build --release..."
    echo "(This may take a while, please be patient...)"
    echo ""
    
    ssh_with_passphrase "bash -c 'source ~/.cargo/env 2>/dev/null || export PATH=\"\$HOME/.cargo/bin:\$PATH\"; cd $REMOTE_WORKSPACE && cargo build --release'"
    
    BUILD_EXIT_CODE=$?
    
    echo ""
    if [ $BUILD_EXIT_CODE -eq 0 ]; then
        echo "Build completed successfully!"
    else
        echo "Warning: Build failed with exit code: $BUILD_EXIT_CODE"
        echo "Continuing anyway..."
    fi
    echo ""
else
    echo "Step 2: Skipping build (SKIP_BUILD=true or --skip-build flag set)"
    echo "----------------------------------------"
    echo ""
fi

# Step 3: Install Python dependencies
echo "Step 3: Installing Python dependencies..."
echo "----------------------------------------"
echo "Installing fabric and other required packages..."

ssh_with_passphrase "bash -c '
    cd $REMOTE_WORKSPACE/benchmark
    # Check if pip is available, if not try to install it
    if ! python3 -m pip --version &> /dev/null && ! command -v pip3 &> /dev/null; then
        echo \"pip not found, attempting to install...\"
        curl -sS https://bootstrap.pypa.io/get-pip.py -o /tmp/get-pip.py && python3 /tmp/get-pip.py --user 2>&1 | grep -v \"dpkg\|apt-get\|Permission denied\" || echo \"pip installation attempted\"
        export PATH=\"\$HOME/.local/bin:\$PATH\"
    fi
    # Filter out dpkg/apt errors as they are usually harmless for --user installs
    if [ -f requirements.txt ]; then
        python3 -m pip install --user -r requirements.txt 2>&1 | grep -v \"dpkg\|apt-get\|Permission denied\|Unable to acquire\" || (export PATH=\"\$HOME/.local/bin:\$PATH\" && pip3 install --user -r requirements.txt 2>&1 | grep -v \"dpkg\|apt-get\|Permission denied\|Unable to acquire\" || true)
    else
        echo \"Warning: requirements.txt not found, installing fabric directly...\"
        python3 -m pip install --user fabric==2.6.0 boto3==1.16.0 2>&1 | grep -v \"dpkg\|apt-get\|Permission denied\|Unable to acquire\" || (export PATH=\"\$HOME/.local/bin:\$PATH\" && pip3 install --user fabric==2.6.0 boto3==1.16.0 2>&1 | grep -v \"dpkg\|apt-get\|Permission denied\|Unable to acquire\" || true)
        # Skip matplotlib if it fails (not critical for experiment.py)
        python3 -m pip install --user matplotlib==3.3.4 2>&1 | grep -v \"dpkg\|apt-get\|Permission denied\|Unable to acquire\" || echo \"Note: matplotlib installation skipped (not critical)\"
    fi
'"

DEPS_EXIT_CODE=$?

echo ""
if [ $DEPS_EXIT_CODE -eq 0 ]; then
    echo "Python dependencies installed successfully!"
else
    echo "Warning: Failed to install Python dependencies with exit code: $DEPS_EXIT_CODE"
    echo "Continuing anyway..."
fi
echo ""

# Step 4: Execute the script remotely
echo "Step 4: Executing $SCRIPT_NAME on remote server..."
echo "----------------------------------------"
# Use absolute path expansion by running in a shell that expands ~
# Load Rust environment (cargo) and Python user bin (fab) before executing the script
ssh_with_passphrase "bash -c 'export PATH=\"\$HOME/.local/bin:\$HOME/.cargo/bin:\$PATH\"; source ~/.cargo/env 2>/dev/null || true; cd $REMOTE_WORKSPACE/script && export PATH=\"\$HOME/.local/bin:\$HOME/.cargo/bin:\$PATH\" && python3 $SCRIPT_NAME'"

EXIT_CODE=$?

echo ""
if [ $EXIT_CODE -eq 0 ]; then
    echo "=========================================="
    echo "Remote execution completed successfully!"
    echo "=========================================="
else
    echo "=========================================="
    echo "Remote execution failed with exit code: $EXIT_CODE"
    echo "=========================================="
fi

exit $EXIT_CODE

