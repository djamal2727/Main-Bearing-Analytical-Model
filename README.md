# Main Bearing Analytical Model Repository

This directory contains the code to a wind turbine main bearing analytical model that estimates bearing loads and reliability using OpenFAST data and reference wind turbine parameters. This is a low-fidelity, computationally-inexpensive model adapted for direct-drive, double main bearing configuration wind turbines. This repo also contains all the necessary drivetrain and main bearing parameters to run this model for the modified 5MW, IEA 10MW, and IEA 15MW reference wind turbine. 

This directory contains four primary files:

1] MainBearing_Analytical_Model contains the functions necessary to translate OpenFAST data, calculate bearing loads and L10 life, and plot these results,

2] Example folder contains a example run of this model with sample data and plot generation using a modified 5MW reference wind turbine,

3] Validation folder contains the pyframe3DD source code, validation program, and an example run of the validation process,

4] Report file contains previous research, project motive, model formulation, and validation method for this project in greater detail. 

It is recommended to clone this repository for further development or copy-and-paste sections of the code into your own model. 
The source code repository must be cloned directly from GitHub:
Git clone https://github.com/djamal2727/Main-Bearing-Analytical-Model

NOTE: An IDE is recommended to run this program

# Citation

If this main bearing model played a role in your research, please cite it. This software can be cited as:

Main Bearing Analytical Model. (2020). Available at https://github.com/djamal2727/Main-Bearing-Analytical-Model. For LaTeX users:

@misc{MBModel_2020, author = {Daniyal Jamal, Caitlyn Clark}, title = {{Main Bearing Model}}, year = {2020}, publisher = {GitHub}, journal = {GitHub repository}, url = {https://github.com/djamal2727/Main-Bearing-Analytical-Model} }

# Dependencies
RBLO has dependencies on various math, statistics, and plotting libraries in addition to other general purpose packages. For the simulation and tool modules, the dependencies are: numpy, scipy, pandas, math, and matplotlib. 

License
=======

Copyright 2020 NREL

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

   http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.



