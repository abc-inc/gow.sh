# gow&#46;sh - Go Wrapper

## Why gow&#46;sh?

Go has a [wrapper](https://go.googlesource.com/dl) for downloading different SDK versions to the home directory.
However, the tool is written in Go and needs to be compiled upfront.

`gow.sh` solves the chicken and egg problem.
The Bash script aims to be a rewrite of the official Go wrapper - nothing more and nothing less.

## Usage

```bash
gow.sh go1.16 download
```

`gow.sh` checks if the desired Go SDK is already installed into `${HOME}/sdk/{version}`.
If not, it downloads the SDK from `https://storage.googleapis.com/golang/${version}.${goos}-${arch}${ext}` and installs it.

```plain
/home/USER/sdk/
├── go1.14.3
│   └── ...
├── go1.15.3
│   └── ...
└── go1.16
    ├── api
    ├── AUTHORS
    ├── bin
    ├── CONTRIBUTING.md
    ├── CONTRIBUTORS
    ├── doc
    ├── favicon.ico
    ├── go1.16.linux-amd64.tar.gz
    ├── lib
    ├── LICENSE
    ├── misc
    ├── PATENTS
    ├── pkg
    ├── README.md
    ├── robots.txt
    ├── SECURITY.md
    ├── src
    ├── test
    └── VERSION
```

Then `gow.sh` can be used to switch between different SDK versions:

```bash
gow.sh go1.16 build main.go
# equivalent to
${HOME}/sdk/go1.16/bin/go build main.go
```

It is advised to add `${HOME}/sdk/${version}/bin` to the `PATH` environment variable so that `go` can be invoked comfortably.

## Uninstall a Go SDK

To uninstall an SDK installed with the Go wrapper, simply delete the directory:

```bash
rm -r ${HOME}/sdk/go1.16
```

## Different Architecture / Operating System

By default `gow.sh` attempts to determine the architecture and the operating system automatically.
In case a different SDK shall be downloaded, the environment variables `GOARCH` and `GOOS` can be set:

```bash
GOARCH=arm64 GOOS=android gow.sh go1.15 download
```

## Install into Custom Directory

`GOROOT` is the root directory of the Go SDK.
If not set, it defaults to `${HOME}/sdk/{version}` e.g., `/home/user/sdk/go1.15`.
To install Go system-wide, set `GOROOT` accordingly:

```bash
sudo GOROOT=/usr/local/go gow.sh go1.15 download
```

## Download from a Mirror

In environments, where direct access to <https://storage.googleapis.com/golang> is prohibited, `gow.sh` can fetch SDKs from a custom web server:

```bash
GOBASEURL=https://company.host/downloads/go gow.sh go1.13 download
# downloads https://company.host/downloads/go/go1.13.linux-amd64.tar.gz (on Linux)
```

## Further Information

### Determine/Install latest Go version

This can be used to download the latest stable release:

```bash
version="$(curl -fs https://go.dev/VERSION?m=text)" # go1.17.5
gow.sh "${version}" download
```

## Similar Projects

* <https://go.googlesource.com/dl> - official Go wrapper
* <https://github.com/golang/tools/tree/master/cmd/getgo> - a proof-of-concept command-line installer for Go
* <https://github.com/canha/golang-tools-install-script> - Bash script to automate installation and removal of single user Go language tools
* <https://github.com/udhos/update-golang> - script to easily fetch and install new Golang releases with minimum system intrusion
