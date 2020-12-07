# Main Bearing Analytical Model Validation

This directory contains the source code for pyFrame3DD, a python-wrapped static and dynamic structural analysis program used for model validation in this project. The directory also contains a validation model that uses pyFrame3DD and a program that runs both the validation and analytical model and compares the discrepancies that result.  

This directory contains three primary files:

1] pyFrame3DD-master is the directory for the python-wrapped Frame3DD program which is obtained from the WISDEM repository [1],

2] pyFrame3DDValidation is the validation program generated using pyFrame3DD with the help of Garett Barter from NREL,

3] RunValidation file runs both the analytical and validation program using a subset of the 5MW OpenFAST data as well as 5MW RWT parameters. This program plots the load results for both models and employs root-mean-square error and boxplots to quantify error and compare distribution of data, respectively.  

Note: pyFrame3DD installation instructions 


# References:

[1] Andrew Ning, Katherine Dykes, Pierre-Elouan Réthoré, and Garett Bart. The Wind-Plant Integrated System Design and Engineering Model (WISDEM), 2020. https://github.com/WISDEM
