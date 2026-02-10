# Installing VaST on FreeBSD

## Dependencies

Install the required packages using `pkg`:

```bash
pkg install bash gcc gmake libX11 curl wget pgplot
```

`bash` is required because VaST scripts are written in Bash, which is not
included in the FreeBSD base system.

## Building

Clone the repository and build:

```bash
git clone https://github.com/kirxkirx/vast.git
cd vast
make
```

VaST's `Makefile` detects FreeBSD and calls `gmake` internally, so you can
use the plain `make` command. Do not use `make -j` or `gmake -j` since
parallel builds are not supported.

## General notes

- The `make` command will inform you of any missing packages.
- For more details, see [the project homepage](http://scan.sai.msu.ru/vast/)
  and [the VaST paper](http://adsabs.harvard.edu/abs/2018A%26C....22...28S).
