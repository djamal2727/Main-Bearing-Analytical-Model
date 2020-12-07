# Jamal_NREL2020
Main Bearing Analytical Model Repo

This directory contains the code to a main bearign analytical model that estimates bearing loads and reliability using OpenFAST data and reference wind turbine parameters. This directory contains three files:

1] MainBearing_Analytical_Model contains the functions necessary to translate OpenFAST data, calculate bearing loads and L10 life

2] ExampleModel runs this model using the 5MW RWT. Load_Estimation_Results folder contains the results from this example run. 

3] Sample_Data folder contains the 5MW OpenFAST data used for the ExampleModel

4] Validation folder contains the frame3DD source code, validation program, and example run of validation process


If this main bearing model played a role in your research, please cite it. This software can be cited as:

RBLO. Version 1.0.0 (2019). Available at https://github.com/caitlynclark/RBLO. For LaTeX users:

@misc{RBLO_2019, author = {Daniyal Jamal}, title = {{Main Bearing Model}}, year = {2020}, publisher = {GitHub}, journal = {GitHub repository}, url = {https://github.com/caitlynclark/RBLO} }
