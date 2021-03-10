# Helm Packaging Action

Automatically bumps version, packages, and pushes chart to remote repository on pull request

## How to use

Make a file at `.github/workflows/packaging.yml` with the following:

```
name: Package
on:
  pull_request:
    types: [closed]
jobs:
  package:
    name: Package and push
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@master
      - uses: cloudve/helm-ci@master
        with:
          chart-name: CHART_NAME
          charts-repo: CHARTS_REPO
          github-token: ${{ secrets.GITHUB_TOKEN }}
          charts-token: ${{ secrets.CHARTS_TOKEN }}
          github-labels: ${{ join(github.event.pull_request.labels.*.name, ', ') }}
          git-branch: ${{ github.event.pull_request.base.ref }}
```

Make sure to replace `CHART_NAME` and `CHARTS_REPO` with the correct values and to set `CHARTS_TOKEN` to a correct GitHub token.

