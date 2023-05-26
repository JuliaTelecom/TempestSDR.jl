# TempestSDR.jl 

## Introduction 

<img src="./docs/logo.png" width="75%" height="75%">

This package proposes a Graphical User Interface (GUI) to perform real time screen eavesdrop.

The GUI is build using [Makie](https://docs.makie.org/stable/) and helps to find the screen leakage and to extract the remote screen configuration that is used. This application is inspired by the amazing work of Marinov proposed in open source in the [TempestSDR project](https://github.com/martinmarinov/TempestSDR) 

This package should be used with a Software Defined Radio (SDR) that receives Electromagnetic signal and samples it. This package is build on top of [AbstractSDRs](https://github.com/JuliaTelecom/AbstractSDRs.jl) to propose automatic configuration of the SDR. 


The application works as follows 
- Configure a SDR on a given carrier frequency and given bandwidth (typically 20MHz). The chosen carrier frequency has to be a multiple of a HDMI//VGA norm and are often multiple of 148,5MHz 
- Propose useful iterative metrics in order to find the appropriate screen configuration (refresh rate, size) 
- Renderer in real time the grayscale image associated to the captured signal. If the chosen carrier frequency matches a side channel leakage, an image of the screen will appear !   

Note that the GUI can also be used as a post processing application fed by a binary file in which a signal has been pre-recorded by a SDR (for instance through GNURadio recording).

## Why TempestSDR in pure Julia ?

There are several implementation proposed for TempestSDR such as the one proposed initially by Marinov. Most of them falls into the 2 language problem. 

- The GUI part and the interface are often written in high level language (such as Java) 

- The processing part is often written in low level language as the proxying requires real time processing with computational intensive processing. For instance, finding the configuration requires lot of autocorrelation and the frame synchronisation requires a O(n^2) complexity with n the size of the width and the heigh.   


This is a project that both 

- Exhibits the power of Julia language as the same algorithms has been used for prototyping (find screen leakage in my lab) and for the final application 

- Demonstrate the interest of side channel analysis in research project ([French ANR RedInBlack](https://files.inria.fr/redinblack/))

## Greetings 

This work is funded by DGA and Brittany region under the Creach Lab founding and by the French National Research Agency (ANR) under the grant number ANR-22-CE25-0007-01 (RedInBlack project).
