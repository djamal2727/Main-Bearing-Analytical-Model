# Main Bearing Analytical Model Example

This directory contains the code to an example use of analytical model presented in this repository. The example model uses the modified 5MW reference wind turbine (RWT) to generate drivetrain and main bearing parameters as well as a sample OpenFAST data. The figures generated from this example model are shown as well. 

This directory contains four primary files:

1] ExampleModel calls the analytical model functions, necessary parameters, and OpenFAST data to plot the main bearing loads and output bearing life,

2] 5MWFastData file contains the OpenFAST data for the NREL 5MW reference wind turbines with 12 m/s wind speed, 10% TI, and 0.1 shear,

3] rwtparameters file contain the reference wind turbine parameters for the modified 5MW, IEA 10MW, and the IEA 15MW reference wind turbines found obtained from technical documents and previous research referenced below,

4] Load_Estimation_Results present the figures generated from the example mode, which produce a time series of the radial and axial loads in upwind main bearing (MB1) and radial loads in the downwind main bearing (MB2), as well as total force in MB1. 



# References:

IEA 15MW RWT

[1] Evan Gaertner, Jennifer Rinker, Latha Sethuraman, Frederik Zahle, Benjamin An-derson, Garrett E. Barter, Nikhar J. Abbas, Fanzhong Meng, Pietro Bortolotti,Witold Skrzypinski, George N. Scott, Roland Feil, Henrik Bredmose, Katherine Dykes,Matthew Shields, Christopher Allen, and Anthony Viselli. IEA Wind TCP Task 37:Definition of the IEA 15-Megawatt Offshore Reference Wind Turbine. 2020.

IEA 10MW RWT

[2] Pietro Bortolotti, Helena Canet Tarres, Katherine Dykes, Karl Merz, Latha Sethura-man, David Verelst, and Frederik Zahle. IEA Wind TCP Task 37 Systems Engineeringin Wind Energy-WP2.1 Reference Wind Turbines Technical Report. Technical report, 2019.

[3] Ebbe Berge Smith. DESIGN AV NACELLE FOR EN 10 MW VINDTURBIN.NTNUMasterThesis, 2012.

Modified 5MW RWT

[4] Latha Sethuraman, Yihan Xing, Zhen Gao, Vengatesan Venugopal, Markus Mueller,and Torgeir Moan. A 5MW direct-drive generator for floating spar-buoy wind turbine:Development and analysis of a fully coupled Mechanical model.ProceedingsoftheInstitutionofMechanicalEngineers,PartA:JournalofPowerandEnergy, 228(7):718–741, 11 2014.

[5] Jm Jonkman, S Butterfield, W Musial, and G Scott. Definition of a 5-MW referencewind turbine for offshore system development.Contract, (February):1–75, 2009

