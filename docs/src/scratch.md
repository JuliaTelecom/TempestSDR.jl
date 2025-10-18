# If you don’t know what Julia is (and don’t want to know)

Julia is a fast and powerful programming language made for scientific and numerical computing.  
But if you just want to try out TempestSDR without learning to code — this guide is for you.

More info: https://julialang.org

---

## What you’ll do
1. Install Julia  
2. Install TempestSDR  
3. Run the app

---

## 1. Install Julia

### Recommended: JuliaUp
- Go to: https://github.com/JuliaLang/juliaup
- Click “Download” and install JuliaUp.
- Follow the on-screen instructions.

### Manual method
- Go to: https://julialang.org/downloads/
- Download the correct installer for your system (Windows / macOS / Linux).
- Install it like any normal program.

### Check the installation
- Open a terminal (or PowerShell on Windows).
- Type
```
julia
```
- If you see (the version 1.12.0 below may be not the same as below, no problem):
```
  _       _ _(_)_     |  Documentation: https://docs.julialang.org
  (_)     | (_) (_)    |
   _ _   _| |_  __ _   |  Type "?" for help, "]?" for Pkg help.
  | | | | | | |/ _` |  |
  | | |_| | | | (_| |  |  Version 1.12.0 (2025-10-07)
 _/ |\__'_|_|_|\__'_|  |  Official https://julialang.org release
|__/                   |

julia>
```


## 2. Install TempestSDR (only once)

We now have to install the package. If you are familiar with pip from Python, this is a similar approach with the following command 
```
julia import Pkg
julia> Pkg.add("TempestSDR")
```
This may take a while ! Be patient, take a coffee and wait until the end of the installation 


## 3. Use TempestSDR 


You can now use TempestSD. This require 3 steps 
- Open Julia (i.e Open a terminal (or PowerShell on Windows) and type julia)
- In Julia type 
```
using TempestSDR 
``` 
- Then call the method based on what you want to do (see the cod the for arguments)
```
TempestSDR.gui(;sdr=:bladerf,carrierFreq=600e6,samplingRate=20e6, gain = 30,addr="usb:1.7.5")
````


Note 
- By using this steps, the package is installed in your global environment : You can instal it into an isolated env (see https://pkgdocs.julialang.org/v1/). If you are not plan to use Julia a lot, global env is fine. 
