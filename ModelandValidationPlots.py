# -*- coding: utf-8 -*-
"""
Created on Thu Nov  5 07:40:28 2020

@author: djamal
"""

import numpy as np
import matplotlib.pyplot as plt
import math
import pandas as pd

#External Module
import filetranslation
import MB_Model
import rwtparameters
import pyFrame3DDValidation as Frame3DD


##_____________________________________________________Input Parameters____________________________________________________________________##


# Define turbine and drivetrain characteristics
Parameters = rwtparameters.RWTParameters()
#FF_timestep, g, m_gr, m_s, m_rh, rho, L_gr, L_g, L_s, L_r, L_h, C, e, X, Y = Parameters.RWT_15MW()
#FF_timestep, g, m_gr, m_s, m_rh, rho, L_gr, L_g, L_s, L_r, L_h, C, e, X, Y = Parameters.RWT_10MW()
FF_timestep, g, m_gr, m_s, m_rh, rho, L_gr, L_g, L_s, L_r, L_h, C1, e1, X1, Y1, C2, e2, X2 = Parameters.RWT_5MW()


#Define load channel inputs
Data = filetranslation.Filetranslation()
data, ChanName, info = Data.load_binary_output("5MWFastData.outb")
rot_speed = data[:2000,7] #translate rotor speed to planet speed (rpm)
torque = data[:2000,5] * 1E3 # in N-m
RotThrust = data[:2000,6] * 1E3 # in N
m_y = data[:2000,8] * 1E3 # in N-m
m_z = data[:2000,9] * 1E3 # in N-m
f_y = data[:2000,10] * 1E3 # in N
f_z = data[:2000,11] * 1E3 # in-N

#Assign Model Parameters for Analytical Model
MainBearingCalc = MB_Model.MB_Model(
    FF_timestep = FF_timestep,
    m_s = m_s,
    m_gr = m_gr,
    m_rh =  m_rh,
    g = g,
    L_gr = L_gr,
    L_g = L_g,
    L_s = L_s,
    L_r = L_r,
    L_h = L_h,
    rho = rho,
    )

##_____________________________________________________Validation Model____________________________________________________________________##


# Shaft Specification for Frame3DD
diameter  = 0.75 # m
thickness = 0.25 # m
length    = 3 # m
tilt      = 5 # deg

# Hub forces & moments
i=0
f_r1v = []
f_r2v = []
f_a1v = []
f_total1v = []
    


while i<2000:
        F_hub = [-RotThrust[i] + m_rh*g*np.sin(rho) + m_gr*g*np.sin(rho) + m_s*g*np.sin(rho),-f_y[i], -f_z[i]]
        M_hub = [torque[i],m_y[i], m_z[i]]
        
        # Run Frame3DD and print results to screen
        F_mb1, F_mb2 = Frame3DD.run(diameter, thickness, length, tilt, F_hub, M_hub)
        f_r1v.append((F_mb1[1]**2 + F_mb1[2]**2)**0.5)
        f_r2v.append(X2*(F_mb2[1]**2 + F_mb2[2]**2)**0.5)
        f_a1v.append(F_mb1[0])
        f_total1v.append(X1*f_r1v[i] + Y1*F_mb1[0])
        i=i+1
        
##_____________________________________________________Analytical Model____________________________________________________________________##

    

f_r1, f_r2, f_a1, f_total1 = MainBearingCalc.MB_forces(rho,torque, RotThrust, m_y, m_z, f_y, f_z, rot_speed, X1, Y1, X2)


##_____________________________________________________PLOTS____________________________________________________________________##

#Radial Forces on MB1 (FWMB)
plt.plot(range(len(f_r1)), f_r1, alpha=0.5, label = "Analytical Model") 
plt.plot(range(len(f_r1v)), f_r1v, alpha=0.5, label = "Frame3DD") 
plt.tight_layout()
plt.xlabel("Time(s)")
plt.ylabel("Load (N)")
plt.legend(loc='lower right')
plt.title("Radial Force of MB1")
plt.show()

#Axial Forces on MB1 (FWMB)
plt.plot(range(len(f_a1)), f_a1, alpha=0.5, label = "Analytical Model") 
plt.plot(range(len(f_a1v)), f_a1v, alpha=0.5, label = "Frame3DD") 
plt.tight_layout()
plt.xlabel("Time(s)")
plt.ylabel("Load (N)")
plt.legend(loc='lower right')
plt.title("Axial Force of MB1")
plt.show()

#Total Forces on MB1 (FWMB)
plt.plot(range(len(f_total1)), f_total1, alpha=0.5, label = "Analytical Model") 
plt.plot(range(len(f_total1v)), f_total1v, alpha=0.5, label = "Frame3DD") 
plt.tight_layout()
plt.xlabel("Time(s)")
plt.ylabel("Load (N)")
plt.legend(loc='lower right')
plt.title("Total Force of MB1")
plt.show()

#Radial Forces on MB2 (FWMB)
plt.plot(range(len(f_r2)), f_r2, alpha=0.5, label = "Analytical Model") 
plt.plot(range(len(f_r2v)), f_r2v, alpha=0.5, label = "Frame3DD") 
plt.tight_layout()
plt.xlabel("Time(s)")
plt.ylabel("Load (N)")
plt.legend(loc='lower right')
plt.title("Radial Force of MB2")
plt.show()


##_____________________________________________________L10 Calculations____________________________________________________________________##


L101v, L10_total_MB1v = MainBearingCalc.L10_Calc(rot_speed, f_total1v, C1, e1)
L102v, L10_total_MB2v = MainBearingCalc.L10_Calc(rot_speed, f_r2v, C2, e2)

print('Validation MB1 L10 Calculated: ', L10_total_MB1v, "hours or", L10_total_MB1v/24/365 , "years" )
print('Validation MB2 L10 Calculated: ', L10_total_MB2v, "hours or", L10_total_MB2v/24/365 , "years" )

L101, L10_total_MB1 = MainBearingCalc.L10_Calc(rot_speed, f_total1, C1, e1)
L102, L10_total_MB2 = MainBearingCalc.L10_Calc(rot_speed, f_r2, C2, e2)
print('MB1 L10 Calculated: ', L10_total_MB1, "hours or", L10_total_MB1/24/365 , "years" )
print('MB2 L10 Calculated: ', L10_total_MB2, "hours or", L10_total_MB2/24/365 , "years" )

print('MB1 Error: ', abs(L10_total_MB1 - L10_total_MB1v))
print('MB2 Error: ', abs(L10_total_MB2 - L10_total_MB2v))

##_____________________________________________________RMS Error____________________________________________________________________##

f1varray = np.array(f_total1v)
f1rarray = np.array(f_r2v)

RMSE = np.sqrt(sum((f_total1 - f1varray)**2)/len(f_total1))

#print(RMSE)


##_____________________________________________________BOXPLOT____________________________________________________________________##




# frame1 = pd.DataFrame(f_total1, columns = ["Force (N)"])
# frame1.insert(1, "Main Bearing", "MB1")
# frame1.insert(2, "Model", "Analytical Model")

# frame2 = pd.DataFrame(f1varray, columns = ["Force (N)"])
# frame2.insert(1, "Main Bearing", "MB1")
# frame2.insert(2, "Model", "Validation Model")

# frame3 = pd.DataFrame(f_r2, columns = ["Force (N)"])
# frame3.insert(1, "Main Bearing", "MB2")
# frame3.insert(2, "Model", "Analytical Model")

# frame4 = pd.DataFrame(f1rarray, columns = ["Force (N)"])
# frame4.insert(1, "Main Bearing", "MB2")
# frame4.insert(2, "Model", "Validation Model")

# df = pd.concat([frame1,frame2,frame3,frame4])

# import seaborn as sns
# ax = sns.boxplot(x="Main Bearing", y="Force (N)", hue = "Model", data= df)
