[![build_and_test_ubuntu](https://github.com/kirxkirx/vast/actions/workflows/build_and_test_ubuntu.yml/badge.svg)](https://github.com/kirxkirx/vast/actions/workflows/build_and_test_ubuntu.yml)
[![build_and_test_macos](https://github.com/kirxkirx/vast/actions/workflows/build_and_test_macos.yml/badge.svg)](https://github.com/kirxkirx/vast/actions/workflows/build_and_test_macos.yml)
[![build_freebsd](https://github.com/kirxkirx/vast/actions/workflows/build_only_freebsdvm.yml/badge.svg)](https://github.com/kirxkirx/vast/actions/workflows/build_only_freebsdvm.yml)
![circlci build test](https://circleci.com/gh/kirxkirx/vast.svg?style=svg)
[![Version](https://img.shields.io/github/v/release/kirxkirx/vast.svg?sort=semver)](https://github.com/kirxkirx/vast/releases)

## VaST: A Software Tool for Finding Variable Objects

The **Variability Search Toolkit (VaST)** is a software tool that helps in finding variable objects in a series of astronomical images. VaST can process a series of CCD frames or digitized photographic plates that are taken with the same instrument using the same filter and saved in the FITS format. The input images may be shifted, rotated, or flipped with respect to each other, but they have to have the same scale (arcsec/pix) and overlap with each other by at least ~40%. It is not necessary to have World Coordinate System (WCS) information in the FITS image header for basic processing and light curve construction. However, VaST may need to plate-solve the images using the [astrometry.net](https://github.com/dstndstn/astrometry.net) code if automated object identification is required. VaST relies on [Source Extractor](https://github.com/astromatic/sextractor) for source detection and photometry.

VaST is written in **C** (and partly in **Bash**) and is intended to work on **Linux**. VaST can also be used on **macOS** (with [XQuartz](https://www.xquartz.org/) and [MacPorts](https://www.macports.org/) or [Homebrew](https://brew.sh/)) and **FreeBSD**. On **Windows**, the recommended approach is [WSL2](https://learn.microsoft.com/en-us/windows/wsl/install) (Windows Subsystem for Linux); alternatively, you can run Linux in a [VirtualBox](https://www.virtualbox.org/) virtual machine.

## Installation

To install VaST, clone this repository and type `make`. The build process will inform you of any missing packages. Generally, to compile VaST you need `gcc`, `g++`, `gfortran`, `X11` libraries, and optionally `libpng`.

Platform-specific installation guides:

- [Linux (Ubuntu, Fedora, Alpine)](INSTALL_LINUX.md)
- [macOS (Homebrew, MacPorts)](INSTALL_MACOS.md)
- [FreeBSD](INSTALL_FREEBSD.md)
- [Windows via WSL2](INSTALL_WINDOWS_WSL2.md)

A more detailed description of VaST and its features can be found at [the project homepage](http://scan.sai.msu.ru/vast/) and in [the VaST paper](http://adsabs.harvard.edu/abs/2018A%26C....22...28S).

Bug reports, pull requests, and feature suggestions are warmly welcomed!

