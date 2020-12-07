# Main Bearing Analytical Model Repository

This directory contains the code to a wind turbine main bearing analytical model that estimates bearing loads and reliability using OpenFAST data and reference wind turbine parameters. This is a low-fidelity, computationally-inexpensive model adapted for direct-drive, double main bearing configuration wind turbines. This repo also contains all the necessary drivetrain and main bearing parameters to run this model for the modified 5MW, IEA 10MW, and IEA 15MW reference wind turbine. 

It is recommended to clone this repository for further development or copy-and-paste sections of the code into your own model. 

This directory contains four primary files:

1] MainBearing_Analytical_Model contains the functions necessary to translate OpenFAST data, calculate bearing loads and L10 life, and plot these results,

2] Example folder contains a example run of this model with sample data and plot generation using a modified 5MW reference wind turbine,

3] Validation folder contains the pyframe3DD source code, validation program, and an example run of the validation process,

4] Report file contains previous research, project motive, model formulation, and validation method for this project in greater detail. 

NOTE: An IDE is recommended to run this program

# Citation

If this main bearing model played a role in your research, please cite it. This software can be cited as:

Main Bearing Analytical Model. (2020). Available at https://github.com/djamal2727/Main-Bearing-Analytical-Model. For LaTeX users:

@misc{MBModel_2020, author = {Daniyal Jamal, Caitlyn Clark}, title = {{Main Bearing Model}}, year = {2020}, publisher = {GitHub}, journal = {GitHub repository}, url = {https://github.com/djamal2727/Main-Bearing-Analytical-Model} }

# Dependencies
RBLO has dependencies on various math, statistics, and plotting libraries in addition to other general purpose packages. For the simulation and tool modules, the dependencies are: numpy, scipy, pandas, math, and matplotlib. 
