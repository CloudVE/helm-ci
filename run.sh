#!/bin/bash

CHART_NAME="$1"
CHARTS_REPO="$2"
GIT_BRANCH="$3"
PR_LABELS="$4"
GIT_TOKEN="$5"
CHARTS_TOKEN="$6"
PACKAGING_COMMAND="$7"

GIT_BRANCH=${GIT_BRANCH:-master}
CHART_FILE="$CHART_NAME/Chart.yaml"
REPOSITORY=${INPUT_REPOSITORY:-$GITHUB_REPOSITORY}
CHART_REMOTE="https://$GITHUB_ACTOR:$GIT_TOKEN@github.com/$REPOSITORY.git"

CHARTS_BRANCH=${CHARTS_BRANCH:-$GIT_BRANCH}
CHARTS_REMOTE="https://$GITHUB_ACTOR:$CHARTS_TOKEN@github.com/$CHARTS_REPO.git"
BASE_DIR=$(dirname $(pwd))
CHARTS_DIR=$(basename "$CHARTS_REPO")

BUMP_AWK=$(cat << "EOF"
/[0-9]+\./ {
  n = split(versionDiff, versions, ".")
  if(n>NF) nIter=n; else nIter=NF
  lastNonzero = nIter
  for(i = 1; i <= nIter; ++i) {
    if(int(versions[i]) > 0) {
      lastNonzero = i
    }
    $i = versions[i] + $i
  }
  for(i = lastNonzero+1; i <= nIter; ++i) {
    $i = 0
  }
  print
}
EOF
)

# Exit on error
set -e

error() {
  exit 1
}

setup_git() {
  # Initialize git info
  git config --local user.email "action@github.com"
  git config --local user.name "GitHub Action"
}

update_anvil_version() {
  # Update anvil version number
  # For example, update anvil.0 to anvil.1 while leaving chart version the same:
  #   version: 5.0.0-anvil.0
  #   version: 5.0.0-anvil.1
  echo "Updating anvil version"
  version=$(awk '/^version/{print $2}' "$CHART_FILE")
  old_anvil_version=$(echo ${version##*.})
  echo "Old anvil version: $old_anvil_version"
  new_anvil_version="$(($old_anvil_version+1))"
  echo "New anvil version: $new_anvil_version"
  chart_version=$(awk '/^version/{print $2}' "$CHART_FILE" | awk -F- '{print $1}')
  sed -i "s/^version: .\+/version: $chart_version-anvil.$new_anvil_version/" "$CHART_FILE"
  new_version=$(awk '/^version/{print $2}' "$CHART_FILE")  # Var needed in rest of script
}

extract_label() {
  # Decide which part of the version to increment (if any)
  echo "Extracting PR label information"
  bump=$(echo "$PR_LABELS" | awk \
    '/version/{print "1"; exit;}
    /release/{print "1"; exit;}
    /major/{print "1"; exit;}
    /feature/{print "0.1"; exit;}
    /enhancement/{print "0.1"; exit;}
    /minor/{print "0.1"; exit;}
    /patch/{print "0.0.1"; exit;}
    /bug/{print "0.0.1"; exit;}
    /values/{print "0.0.1"; exit;}
	//{print ""; exit;}')
  version=$(awk '/^version/{print $2}' "$CHART_FILE")
}

bump_version() {
  # Bump the part of the version defined by $bump and update the chart
  echo "Bumping version"
  # source: https://stackoverflow.com/a/64933139
  new_version=$(awk -v versionDiff="$bump" -F. "$BUMP_AWK" OFS=. <<< "$version")
  echo "New chart version is $new_version"
  sed -i "s/^version: .\+/version: $new_version/" "$CHART_FILE"
}

push_version() {
  # Push the updated version to the source repo
  echo "Pushing to branch $GIT_BRANCH"
  git add .
  git commit -m "Automatic Version Bumping from $version to $new_version"
  git push "$CHART_REMOTE" "HEAD:$GIT_BRANCH" -v -v
}

package() {
  # Package helm chart
  (cd "$CHART_NAME" || error
  rm -rf charts requirements.lock
  helm dependency update)

  (cd "$BASE_DIR"
  git clone "$CHARTS_REMOTE"
  cd ./"$CHARTS_DIR" || error
  git checkout "$CHARTS_BRANCH")

  # Custom packaging command
  eval "$PACKAGING_COMMAND"
}

push_package() {
  # Push updated chart to branch $CHARTS_BRANCH of repo $CHARTS_REPO
  echo "Pushing to branch $CHARTS_BRANCH of repo $CHARTS_REPO"
  (cd "$BASE_DIR/$CHARTS_DIR" || error
  helm repo index . --url "https://raw.githubusercontent.com/$CHARTS_REPO/$CHARTS_BRANCH/"
  setup_git
  git add . && git commit -m "Automatic Packaging of $CHART_NAME-$pushed_version chart"
  git push "$CHARTS_REMOTE" "HEAD:$CHARTS_BRANCH")
}

echo "Bumping version if necessary..."
setup_git
git remote -v
git pull
if ! git diff --name-status origin/"$GIT_BRANCH" | grep "$CHART_FILE"; then
  # `galaxy`chart's `anvil` branch has its own versioning
  if [[ "$CHART_NAME" = "galaxy" ]] && [[ "$GIT_BRANCH" = "anvil" ]]; then
    update_anvil_version
    push_version
  else
    extract_label
    if [ "$bump" ]; then
      bump_version
      push_version
    fi
  fi
fi

pushed_version=${new_version:-$version}

echo "Packaging and pushing version $pushed_version..."
package
push_package
