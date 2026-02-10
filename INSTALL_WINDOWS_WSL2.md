# Installing VaST on Windows (WSL2)

The recommended way to run VaST on Windows is through the **Windows Subsystem
for Linux (WSL2)**, which provides a full Linux environment.

## Step 1: Enable WSL2

Open PowerShell as Administrator and run:

```powershell
wsl --install
```

This will enable WSL2 and install Ubuntu by default. You may be asked to
restart your computer.

If you already have WSL1 installed, you can upgrade to WSL2 by running:

```powershell
wsl --set-default-version 2
```

See the [Microsoft WSL documentation](https://learn.microsoft.com/en-us/windows/wsl/install)
for more details.

## Step 2: Set up Ubuntu

After installation, open the **Ubuntu** app from the Start menu. On the first
launch, you will be asked to create a Linux username and password.

## Step 3: Install build dependencies

Inside the Ubuntu terminal, run:

```bash
sudo apt-get update
sudo apt-get install build-essential gcc g++ gfortran make libx11-dev libpng-dev ghostscript curl wget file bc git
```

## Step 4: Clone and build VaST

**Important:** Work within the Linux filesystem (`~/`), not in `/mnt/c/` or
other Windows mount points. File operations on the Windows filesystem from
WSL are significantly slower and may cause issues.

```bash
cd ~
git clone https://github.com/kirxkirx/vast.git
cd vast
make
```

## General notes

- Always use plain `make` (not `make -j`) since parallel builds are not
  supported.
- The `make` command will inform you of any missing packages.
- An alternative to WSL2 is to run Linux in a virtual machine using
  [VirtualBox](https://www.virtualbox.org/).
- For more details, see [the project homepage](http://scan.sai.msu.ru/vast/)
  and [the VaST paper](http://adsabs.harvard.edu/abs/2018A%26C....22...28S).
