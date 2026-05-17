#!/usr/bin/env bash
# =============================================================================
# Plugin Workshop Setup Script
#
# This script sets up a complete local development environment for the Open edX
# plugin workshop. It will:
#
#   1. Install and activate Node.js 24 via nvm
#   2. Clone the necessary backend and frontend repositories from GitHub
#   3. Install npm dependencies for all micro-frontends (MFEs)
#   4. Configure the Learner Dashboard MFE to load the sample frontend plugin
#      in local development mode (bypassing the npm registry)
#   5. Install Python packages for Tutor and the sample plugin
#   6. Launch a full Tutor dev environment with the sample plugin enabled
#   7. Create a superuser account and import demo course data for testing
#
# Prerequisites (must be installed before running this script):
#   - Python 3.12  (https://www.python.org/downloads/)
#   - nvm          (https://github.com/nvm-sh/nvm#installing-and-updating)
#
# Usage:
#   bash setup.sh
#
# Note: This script uses `set -euxo pipefail`, so it will print each command
# before running it, exit immediately if any command fails, treat unset
# variables as errors, and catch failures in pipelines.
# =============================================================================

set -euxo pipefail

WORKSHOP_DIR="$(pwd)"

# =============================================================================
# Node.js setup
#
# Load nvm and install/activate Node.js 24. We need this to build and run
# MFEs locally outside of Tutor when developing them in dev mode.
# =============================================================================

# shellcheck source=/dev/null
\. "$HOME/.nvm/nvm.sh"
nvm install 24
nvm use 24

# =============================================================================
# Repository cloning
#
# Clone all required repositories from GitHub. The helper function skips a
# clone if the directory already exists, making the script safe to re-run.
# =============================================================================

clone_repo() {
    local repo="$1"
    local branch="$2"
    local org="${3:-openedx}"
    if [ -d "$repo" ]; then
        echo "Skipping clone of $repo, already exists."
        return
    fi
    if [ -n "$branch" ]; then
        git clone --branch "$branch" "https://github.com/${org}/${repo}.git"
    else
        git clone "https://github.com/${org}/${repo}.git"
    fi
}

# Tutor is the local dev platform; sample-plugin is the workshop plugin;
# openedx-tutor-plugins provides the Paragon theme plugin.
clone_repo tutor main overhangio
clone_repo sample-plugin
clone_repo openedx-tutor-plugins

# =============================================================================
# Micro-frontend (MFE) setup
#
# Clone each MFE repository and run `npm ci` to install its dependencies.
# All MFEs live under a single `mfes/` subdirectory to keep things organised.
# =============================================================================

MFES=(
    frontend-app-account
    frontend-app-admin-console
    frontend-app-authn
    frontend-app-authoring
    frontend-app-communications
    frontend-app-discussions
    frontend-app-gradebook
    frontend-app-learner-dashboard
    frontend-app-learning
    frontend-app-ora-grading
    frontend-app-profile
)

mkdir -p mfes
cd mfes
for mfe in "${MFES[@]}"; do
    clone_repo "$mfe"
    (cd "$mfe" && npm ci)
done
cd ${WORKSHOP_DIR}

# =============================================================================
# Frontend plugin configuration
#
# Wire the Learner Dashboard MFE so it loads the sample frontend plugin
# directly from the local source tree instead of from npm. Two files are
# written into the MFE directory:
#
#   env.config.jsx   – declares which plugin should fill the course_list_slot
#   module.config.js – tells the webpack dev server to resolve @openedx/plugin-sample
#                      to the local checkout rather than node_modules
# =============================================================================

LEARNER_DASHBOARD_DIR="${WORKSHOP_DIR}/mfes/frontend-app-learner-dashboard"
FRONTEND_PLUGIN_DIR="${WORKSHOP_DIR}/sample-plugin/frontend-plugin-sample"
BACKEND_PLUGIN_DIR="${WORKSHOP_DIR}/sample-plugin/backend-plugin-sample"

cat > "${LEARNER_DASHBOARD_DIR}/env.config.jsx" << 'EOF'
import { DIRECT_PLUGIN, PLUGIN_OPERATIONS } from '@openedx/frontend-plugin-framework';
import { CourseList } from '@openedx/plugin-sample';

const config = {
  pluginSlots: {
    course_list_slot: {
      keepDefault: false,
      plugins: [
        {
          op: PLUGIN_OPERATIONS.Insert,
          widget: {
            id: 'custom_course_list',
            type: DIRECT_PLUGIN,
            priority: 60,
            RenderWidget: CourseList,
          },
        },
      ],
    },
  },
};

export default config;
EOF

cat > "${LEARNER_DASHBOARD_DIR}/module.config.js" << EOF
module.exports = {
  localModules: [
    {
      moduleName: '@openedx/plugin-sample',
      dir: '${FRONTEND_PLUGIN_DIR}',
      dist: 'src',
    },
  ],
};
EOF

# =============================================================================
# Python package installation
#
# Install Tutor and the sample/Paragon plugins as editable packages so that
# local changes to them are reflected immediately without reinstalling.
# These don't need to be editable for the workshop as planned, but it's
# convenient in case we do find we need to make changes on the fly.
# =============================================================================

pip install -e './tutor' -e './sample-plugin/tutor-contrib-sample' -e './openedx-tutor-plugins/plugins/tutor-contrib-paragon'

# =============================================================================
# Tutor environment configuration
#
# Save the initial Tutor config, then enable the plugins needed for the
# workshop (sample plugin and Paragon theme).
# =============================================================================

tutor config save
tutor plugins disable indigo
tutor plugins install mfe
tutor plugins enable sample
tutor plugins enable paragon

# Mount the backend plugin so Tutor picks up local source changes live.
tutor mounts add "${BACKEND_PLUGIN_DIR}"

# =============================================================================
# Tutor dev environment launch
#
# Launch the full dev stack, then stop the MFE container. During development,
# we run the MFE we're working on locally at the port Tutor expects, rather
# than inside the container — this makes for a faster dev loop with webpack
# watching for changes directly.
#
# Normally, mounting a local checkout causes Tutor to spin up a dedicated dev
# container for that MFE with your local directory mounted, while the main MFE
# container stops serving it. We bypass that here by adding the mount and then
# starting only the MFE container — so Tutor continues serving all the other
# MFEs while we spin up the one we're developing locally ourselves.
# =============================================================================

tutor dev launch

tutor dev stop mfe

tutor mounts add "${LEARNER_DASHBOARD_DIR}"

tutor dev start mfe

# =============================================================================
# Demo data setup
#
# Create a staff/superuser account for testing and import the standard Open
# edX demo course so there is content to interact with right away.
# =============================================================================

tutor dev do createuser --staff --superuser -p openedx openedx openedx@example.com
tutor dev do importdemocourse
