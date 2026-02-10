# Installing VaST on Linux

## Ubuntu / Debian

Install the required build dependencies:

```bash
sudo apt-get update
sudo apt-get install build-essential gfortran libx11-dev libpng-dev ghostscript curl wget file bc git
```

Clone the repository and build:

```bash
git clone https://github.com/kirxkirx/vast.git
cd vast
make
```

### Optional Python dependencies

Some VaST utilities require Python 3 with additional packages:

```bash
sudo apt-get install python3 python3-pip
pip3 install astropy sympy skyfield numpy pandas requests
```

## Fedora

Install the required build dependencies:

```bash
sudo dnf install gcc gcc-c++ gcc-gfortran make libX11-devel libpng-devel ghostscript curl wget file bc git
```

Clone the repository and build:

```bash
git clone https://github.com/kirxkirx/vast.git
cd vast
make
```

## Alpine Linux

Alpine Linux uses `musl` instead of `glibc` and `busybox` for core utilities.
VaST requires `bash` to be installed explicitly.

```bash
apk add bash gcc g++ gfortran make musl-dev libx11-dev libpng-dev git curl wget file bc ghostscript
```

Clone the repository and build:

```bash
git clone https://github.com/kirxkirx/vast.git
cd vast
make
```

## General notes

- Always use plain `make` (not `make -j`) since parallel builds are not supported.
- The `make` command will inform you of any missing packages.
- For more details, see [the project homepage](http://scan.sai.msu.ru/vast/)
  and [the VaST paper](http://adsabs.harvard.edu/abs/2018A%26C....22...28S).
