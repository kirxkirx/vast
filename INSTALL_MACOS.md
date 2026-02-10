# Installing VaST on macOS

VaST requires [XQuartz](https://www.xquartz.org/) for X11 support on macOS.
You may need to log out and log back in after installing XQuartz for the
X11 libraries to become available.

You can install build dependencies using either [Homebrew](https://brew.sh/)
or [MacPorts](https://www.macports.org/).

## Using Homebrew

```bash
brew install gcc
brew install --cask xquartz
```

## Using MacPorts

```bash
sudo port install gcc13 wget xorg-libX11 libpng ghostscript
```

You may substitute a different GCC version (e.g. `gcc14`) depending on what
is available in MacPorts at the time.

## Building

Clone the repository and build:

```bash
git clone https://github.com/kirxkirx/vast.git
cd vast
make
```

The `make` command will inform you of any missing packages.
Always use plain `make` (not `make -j`) since parallel builds are not supported.
For more details, see [the project homepage](http://scan.sai.msu.ru/vast/)
and [the VaST paper](http://adsabs.harvard.edu/abs/2018A%26C....22...28S).
