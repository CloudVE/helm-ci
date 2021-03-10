#!/bin/bash

CHART_NAME="$1"
CHARTS_REPO="$2"
GIT_BRANCH="$3"
PR_LABELS="$4"
GIT_TOKEN="$5"
CHARTS_TOKEN="$6"
PACKAGING_COMMAND="$7"
DEP_NAME="$8"

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

# exit on error
set -e

error() {
  exit 1
}

setup_git() {
  # initializes git info
  git config --local user.email "action@github.com"
  git config --local user.name "GitHub Action"
}

extract_label() {
  # decides which part of the version to increment (if any)
  echo "Extracting label information"
  bump=$(echo "$PR_LABELS" | awk \
    '/version/{print "1"; exit;}
    /release/{print "1"; exit;}
    /major_bump/{print "1"; exit;}
    /feature/{print "0.1"; exit;}
    /enhancement/{print "0.1"; exit;}
    /minor_bump/{print "0.1"; exit;}
    /patch/{print "0.0.1"; exit;}
    /bug/{print "0.0.1"; exit;}
    /values/{print "0.0.1"; exit;}
	//{print ""; exit;}')
  version=$(awk '/^version/{print $2}' "$CHART_FILE")
}

bump_version() {
  # bumps the part of the version defined by $bump and updates
  # the chart 
  echo "Bumping version"
  # source: https://stackoverflow.com/a/64933139
  new_version=$(awk -v versionDiff="$bump" -F. "$BUMP_AWK" OFS=. <<< "$version")
  sed -i "s/^version: .\+/version: $new_version/" "$CHART_FILE"
}

bump_dep_version() {
  echo "Bumping dependecy version for $DEP_NAME"
  dep_version=$(sed -n "/$DEP_NAME/,/version/{p; /version/q}" "$CHART_FILE" | awk '/version/{print $2}')
  new_dep_version=$(awk -v versionDiff="$bump" -F. "$BUMP_AWK" OFS=. <<< "$dep_version")
  sed -i -e "/name: $dep_name/,/version: $dep_version/  s/version: $dep_version/version: $new_dep_version/" "$CHART_FILE"
}

push_version() {
  # pushes the updated version to the charts repo
  echo "Pushing to branch $GIT_BRANCH"
  git add "$CHART_NAME"
  git commit -m "Bumping $CHART_NAME from $version to $new_version"
  git push "$CHART_REMOTE" "HEAD:$GIT_BRANCH" -v -v
}

package() {
  # packages helm chart
  (cd "$CHART_NAME" || error
  rm -rf charts requirements.lock Chart.lock
  helm dependency update)

  (cd "$BASE_DIR"
  git clone "$CHARTS_REMOTE"
  cd ./"$CHARTS_DIR" || error
  git checkout "$CHARTS_BRANCH")

  # custom packaging command
  eval "$PACKAGING_COMMAND"
}

push_package() {
  # push updated chart
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
  extract_label
  if [ "$bump" ]; then
    bump_version
    if [ ! -z "$DEP_NAME" ]; then
      bump_dep_version
    fi
    push_version
  fi
fi

pushed_version=${new_version:-$version}

echo "Packaging and pushing..."
package
push_package
